# docker compose

Compose interpolates `${VAR}` in `docker-compose.yml` from the parent
shell. Direnv populates that shell — no `.env` file needed.

```yaml
# docker-compose.yml
services:
  api:
    environment:
      GOOGLE_CLIENT_ID: "${GOOGLE_CLIENT_ID:?direnv allow the repo-root .envrc}"
```

The `:?` guard turns a missing var into a loud error pointing at the fix.
