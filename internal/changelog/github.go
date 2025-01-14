package changelog

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"github.com/bradleyfalzon/ghinstallation/v2"
	"github.com/google/go-github/v62/github"
	"github.com/jonashiltl/openchangelog/internal/config"
	"github.com/jonashiltl/openchangelog/internal/store"
	"github.com/naveensrinivasan/httpcache"
)

type ghSource struct {
	client         *github.Client
	Owner          string
	Repo           string
	Path           string
	InstallationID int64
}

func newGHSourceFromStore(cfg config.Config, gh store.GHSource, cache httpcache.Cache) (Source, error) {
	tr := http.DefaultTransport

	if cfg.HasGithubAuth() && cfg.Github.Auth.AppPrivateKey != "" && gh.InstallationID != 0 {
		// Wrap the shared transport for use with the app ID 1 authenticating with installation ID 99.
		itr, err := ghinstallation.NewKeyFromFile(tr, cfg.Github.Auth.AppID, gh.InstallationID, cfg.Github.Auth.AppPrivateKey)
		if err != nil {
			return nil, err
		}
		tr = itr
	}

	if cache != nil {
		cachedTransport := httpcache.NewTransport(cache)
		cachedTransport.Transport = tr
		tr = cachedTransport
	}

	client := github.NewClient(&http.Client{Transport: tr})
	if cfg.HasGithubAuth() && cfg.Github.Auth.AccessToken != "" {
		client = client.WithAuthToken(cfg.Github.Auth.AccessToken)
	}

	return &ghSource{
		client:         client,
		Owner:          gh.Owner,
		Repo:           gh.Repo,
		Path:           gh.Path,
		InstallationID: gh.InstallationID,
	}, nil
}

func (s *ghSource) Load(ctx context.Context, page Pagination) (LoadResult, error) {
	// sanitize params
	if page.IsDefined() && page.PageSize() < 1 {
		return LoadResult{}, nil
	}

	file, dir, _, err := s.client.Repositories.GetContents(ctx, s.Owner, s.Repo, s.Path, nil)
	if err != nil {
		return LoadResult{}, err
	}

	if file != nil {
		c, err := file.GetContent()
		if err != nil {
			return LoadResult{}, err
		}
		return LoadResult{
			Articles: []RawArticle{
				{
					Content: io.NopCloser(strings.NewReader(c)),
				},
			},
		}, nil
	}
	return s.loadDir(ctx, dir, page)
}

func (s *ghSource) loadDir(ctx context.Context, files []*github.RepositoryContent, page Pagination) (LoadResult, error) {
	files = filter(files, func(f *github.RepositoryContent) bool {
		return filepath.Ext(f.GetName()) == ".md"
	})

	startIdx := page.StartIdx()
	endIdx := page.EndIdx()

	// If pagination is not applied, process all files
	if !page.IsDefined() {
		startIdx = 0
		endIdx = len(files) - 1
	}

	if startIdx >= len(files) {
		return LoadResult{
			Articles: []RawArticle{},
			HasMore:  false,
		}, nil
	}

	// sort files in descending order by filename
	sort.Slice(files, func(i, j int) bool {
		return files[i].GetName() >= files[j].GetName()
	})

	var wg sync.WaitGroup
	articles := make([]RawArticle, 0, page.PageSize())
	mutex := &sync.Mutex{}

	for i := startIdx; i <= endIdx && i < len(files); i++ {
		wg.Add(1)
		go func(name string) {
			defer wg.Done()
			read, err := s.loadFile(ctx, name)
			if err != nil {
				return
			}
			mutex.Lock()
			articles = append(articles, RawArticle{
				Content: read,
			})
			mutex.Unlock()
		}(files[i].GetName())
	}
	wg.Wait()

	return LoadResult{
		Articles: articles,
		HasMore:  endIdx+1 < len(files),
	}, nil
}

func (s *ghSource) loadFile(ctx context.Context, filename string) (io.ReadCloser, error) {
	read, _, err := s.client.Repositories.DownloadContents(ctx, s.Owner, s.Repo, fmt.Sprintf("%s/%s", s.Path, filename), nil)
	if err != nil {
		return nil, err
	}
	return read, nil
}

func filter[T any](ss []T, test func(T) bool) (ret []T) {
	for _, s := range ss {
		if test(s) {
			ret = append(ret, s)
		}
	}
	return
}
