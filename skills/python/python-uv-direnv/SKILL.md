---
name: python-uv-direnv
description: Python-specific conventions for managing a uv-managed venv with direnv auto-activation. Covers two layouts — single-package (`pyproject.toml` at the repo root) and polyglot monorepo (Python project in a subfolder, venv activated from a root `.envrc`). Trigger when initializing a Python project, writing/editing the venv-activation block in a `.envrc`, choosing between root-vs-subfolder venv locations, or wiring uv into a polyglot repo. For generic direnv conventions (env-file mechanics, gitignore, stdlib helpers, per-stack cheatsheets like GCP / Terraform / JVM / Node), see the `direnv-local-env` skill — this one composes on top of it.
---

# Python venvs with uv + direnv auto-activation

- **Package manager**: `uv` (not Poetry, not Pipenv). Fast, modern,
  lockfile-based. Commits `pyproject.toml` and `uv.lock`.
- **Activation**: a `.envrc` block that creates the venv with `uv venv` on
  first allow, then exports `VIRTUAL_ENV` + adds `.venv/bin` to `PATH` so
  `python`, `pytest`, `uvicorn`, `ruff`, etc. resolve from any cwd in the
  repo without an explicit `source .venv/bin/activate`.

For the generic mechanics (committed `.envrc.example`, gitignored `.envrc`,
`direnv allow` workflow, `.envrc.local` secret split, per-stack vars) see
the **`direnv-local-env`** skill — this one only covers the Python+uv
specifics that layer on top.

## Pattern 1 — single-package (`pyproject.toml` at the repo root)

Inside the repo-root `.envrc`:

```bash
# venv auto-activation (uv-managed)
if [ ! -d ".venv" ]; then
  echo "Creating .venv with uv..."
  uv venv
fi
export VIRTUAL_ENV="$(pwd)/.venv"
PATH_add "$VIRTUAL_ENV/bin"
```

## Pattern 2 — polyglot monorepo (Python project in a subfolder)

The Python project lives at e.g. `<repo>/bff/`. The repo also has a JS
frontend, a `docker-compose.yml`, etc. **One root `.envrc`** activates the
venv that lives inside the subfolder, so `python`/`uvicorn`/`pytest`
resolve from anywhere in the repo.

```bash
# venv lives in bff/.venv; activate it from the root.
BFF_DIR="$(pwd)/bff"
if [ ! -d "$BFF_DIR/.venv" ]; then
  echo "Creating bff/.venv with uv..."
  (cd "$BFF_DIR" && uv venv)
fi
export VIRTUAL_ENV="$BFF_DIR/.venv"
PATH_add "$VIRTUAL_ENV/bin"
```

**Run `uv` commands from the Python subfolder** (`cd bff && uv sync`) — uv
discovers `pyproject.toml` from cwd. The active `VIRTUAL_ENV` is the same
`bff/.venv` either way, so `uv sync`, `uv add`, and `uv run` all hit the
right environment.

### Why one root `.envrc` and not one per subfolder

- direnv loads the **closest** `.envrc` walking up. With a child `.envrc`
  in `bff/`, `cd ui` would unload Python vars. With one root file, the
  venv stays activated everywhere.
- Single source of truth for shared values (e.g. `GOOGLE_CLIENT_ID` once,
  reused as `VITE_GOOGLE_CLIENT_ID` *and* `MY_APP_GOOGLE_CLIENT_ID`).
- `docker compose` interpolation Just Works from any cwd inside the repo.

If a subfolder genuinely needs *additional* setup the root doesn't, see
Layout B in the `direnv-local-env` skill (`source_up` from a child file).

## uv command cheatsheet

```bash
uv venv                          # create .venv (if missing)
uv sync                          # install deps from pyproject.toml + uv.lock
uv add <pkg>                     # add a runtime dep
uv add --dev <pkg>               # add a dev dep
uv run <cmd>                     # run a command in the venv (alt. to activating)
uv lock --upgrade-package <pkg>  # upgrade just one dep
uv python pin 3.13               # write .python-version
```

## Gitignore essentials (Python-specific)

```
.venv/                # Pattern 1: at root. Pattern 2: inside the subfolder.
.python-version       # only if NOT committed (some teams pin it deliberately)
__pycache__/
.pytest_cache/
.ruff_cache/
```

Commit: `pyproject.toml`, `uv.lock`. Generic direnv ignores
(`.envrc`, `.direnv/`) live in the `direnv-local-env` skill.
