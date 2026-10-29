# Node / pnpm / Vite

```bash
# Use a per-project Node version (with fnm / nvm-direnv integration).
# `fnm use --install-if-missing` reads .node-version automatically.

# pnpm store location — share across projects.
export PNPM_HOME="$HOME/.pnpm-store"
PATH_add "$PNPM_HOME"

# Vite reads VITE_* from the process env at dev time AND build time.
# (Build-time values get baked into the bundle.)
export VITE_API_BASE_URL=http://localhost:8000
export VITE_GOOGLE_CLIENT_ID=
```
