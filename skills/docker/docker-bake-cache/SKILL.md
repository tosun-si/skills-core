---
name: docker-bake-cache
description: Conventions for writing Docker Bake (docker-bake.hcl) files with registry-cached builds against a private Artifact Registry repo. Trigger when creating, editing, or reviewing docker-bake.hcl, or when discussing multi-target Docker builds with cache.
---

# Docker Bake with registry cache

- Enable cache via `cache-from` and `cache-to` pointing at the **private Artifact Registry** repo.
- Cache image tag convention: `<image>:buildcache` (same convention as Cloud Build steps).
- **Always set `ignore-error=true` on `cache-from`** — without it, the first build (cache doesn't exist yet) and any local-dev build without AR auth fail with `ERROR importing cache manifest`.

## Reference target

```hcl
target "app" {
  # ignore-error=true lets a missing/inaccessible cache image fall back to a
  # cold build instead of failing the whole bake. Critical for first builds
  # and for local dev without AR auth.
  cache-from = ["type=registry,ref=REGION-docker.pkg.dev/PROJECT/REPO/IMAGE:buildcache,ignore-error=true"]
  cache-to   = ["type=registry,ref=REGION-docker.pkg.dev/PROJECT/REPO/IMAGE:buildcache,mode=max"]
}
```

## Notes

- `mode=max` (on `cache-to`) exports all layers including intermediate ones — best for incremental rebuild performance. Use `mode=min` if cache push bandwidth is a concern.
- `ignore-error=true` belongs on `cache-from` only. On `cache-to`, a push failure usually signals a real permissions problem — let it fail loud.
- For multi-target bakes, each target can have its own `buildcache` tag — keeps caches scoped per artifact rather than colliding.
- The build runner needs `roles/artifactregistry.writer` on the AR repo to push the cache image. Local dev typically only needs `reader` (and even that is optional thanks to `ignore-error=true`).

## Coexisting with `docker-compose.yml` — always pass `-f`

`docker buildx bake` (no args) auto-merges *every* known file in cwd:
`docker-bake.hcl`, `docker-compose.yml`, `compose.yaml`, etc. If your
`docker-compose.yml` uses `${VAR:?...}` interpolation guards, bake's parse
step fails before the build starts when the env isn't set in the shell.

Always invoke with the explicit file:

```bash
docker buildx bake -f docker-bake.hcl              # local builds
docker buildx bake -f docker-bake.hcl --push       # push image + cache
```

Wrap in a `Justfile` (or shell alias) so the flag is never forgotten:

```just
bake:
    docker buildx bake -f docker-bake.hcl \
        --set '*.cache-to=' --set '*.output=type=docker'   # local, no cache push, load into engine

bake-push:
    docker buildx bake -f docker-bake.hcl --push
```
