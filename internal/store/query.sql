-- name: saveWorkspace :one
INSERT INTO workspaces (
    id, name
) VALUES (?1, ?2)
ON CONFLICT (id)
DO UPDATE SET name = ?2
RETURNING *;

-- name: getWorkspace :one
SELECT sqlc.embed(w), sqlc.embed(t)
FROM workspaces w
LEFT JOIN tokens t ON w.id = t.workspace_id
WHERE id = ?;

-- name: deleteWorkspace :exec
DELETE FROM workspaces
WHERE id = ?;

-- name: createToken :exec
INSERT INTO tokens (
    key, workspace_id
) VALUES (
    ?, ?
);

-- name: getToken :one
SELECT * FROM tokens
WHERE key = ?;

-- technically a workspace can have multiple tokens, but domain only create one token when workspace is created

-- name: getTokenByWorkspace :one
SELECT * FROM tokens
WHERE workspace_id = ?
LIMIT 1;

-- name: createChangelog :one
INSERT INTO changelogs (
    workspace_id,
    id,
    subdomain,
    domain,
    title,
    subtitle,
    logo_src,
    logo_link,
    logo_alt,
    logo_height,
    logo_width,
    color_scheme,
    hide_powered_by,
    protected,
    analytics,
    password_hash
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
RETURNING *;

-- name: deleteChangelog :exec
DELETE FROM changelogs
WHERE workspace_id = ? AND id = ?;

-- name: getChangelog :one
SELECT sqlc.embed(c), sqlc.embed(cs)
FROM changelogs c
LEFT JOIN changelog_source cs ON c.workspace_id = cs.workspace_id AND c.source_id = cs.id
WHERE c.workspace_id = ? AND c.id = ?;

-- name: getChangelogByDomainOrSubdomain :one
SELECT sqlc.embed(c), sqlc.embed(cs)
FROM changelogs c
LEFT JOIN changelog_source cs ON c.workspace_id = cs.workspace_id AND c.source_id = cs.id
-- first search by domain, if not found by subdomain
WHERE c.domain = ? OR c.subdomain = ?
LIMIT 1;

-- name: listChangelogs :many
SELECT sqlc.embed(c), sqlc.embed(cs)
FROM changelogs c
LEFT JOIN changelog_source cs ON c.workspace_id = cs.workspace_id AND c.source_id = cs.id
WHERE c.workspace_id = ?;

-- name: updateChangelog :one
UPDATE changelogs
SET
   subdomain = coalesce(sqlc.narg(subdomain), subdomain),
   hide_powered_by = coalesce(sqlc.narg(hide_powered_by), hide_powered_by),
   title = CASE WHEN cast(@set_title as bool) THEN @title ELSE title END,
   subtitle = CASE WHEN cast(@set_subtitle as bool) THEN @subtitle ELSE subtitle END,
   domain = CASE WHEN cast(@set_domain as bool) THEN @domain ELSE domain END,
   logo_src = CASE WHEN cast(@set_logo_src as bool) THEN @logo_src ELSE logo_src END,
   logo_link = CASE WHEN cast(@set_logo_link as bool) THEN @logo_link ELSE logo_link END,
   logo_alt = CASE WHEN cast(@set_logo_alt as bool) THEN @logo_alt ELSE logo_alt END,
   logo_height = CASE WHEN cast(@set_logo_height as bool) THEN @logo_height ELSE logo_height END,
   logo_width = CASE WHEN cast(@set_logo_width as bool) THEN @logo_width ELSE logo_width END,
   color_scheme = CASE WHEN cast(@set_color_scheme as bool) THEN @color_scheme ELSE color_scheme END,
   protected = coalesce(sqlc.narg(protected), protected),
   analytics = coalesce(sqlc.narg(analytics), analytics),
   password_hash = CASE WHEN cast(@set_password_hash as bool) THEN @password_hash ELSE password_hash END
WHERE workspace_id = sqlc.arg(workspace_id) AND id = sqlc.arg(id)
RETURNING *;

-- name: setChangelogSource :exec
UPDATE changelogs
SET source_id = ?
WHERE workspace_id = ? AND id = ?;

-- name: deleteChangelogSource :exec
UPDATE changelogs
SET source_id = NULL
WHERE workspace_id = ? AND id = ?;

-- name: createGHSource :one
INSERT INTO gh_sources (
    id, workspace_id, owner, repo, path, installation_id
) VALUES (?, ?, ?, ?, ?, ?)
RETURNING *;

-- name: listGHSources :many
SELECT * FROM gh_sources
WHERE workspace_id = ?;

-- name: getGHSource :one
SELECT * FROM gh_sources
WHERE workspace_id = ? AND id = ?;

-- name: deleteGHSource :exec
DELETE FROM gh_sources
WHERE workspace_id = ? AND id = ?;