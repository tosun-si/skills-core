---
name: python-docker-multistage
description: Python-specific extensions to the universal Docker conventions — uv as the builder, alpine vs slim decision rules for Python (most prebuilt scientific wheels need glibc → slim), `uv sync --frozen --no-dev` pattern, layered caching with pyproject.toml + uv.lock, runtime image without uv. Trigger when creating, editing, or reviewing a Dockerfile in a Python project using uv. For the universal multi-stage + non-root + base-image patterns this skill builds on, see `docker-image-conventions`.
---

# Python Dockerfiles with uv

Builds on top of the universal `docker-image-conventions` skill — apply all
five rules there (multi-stage, non-root, alpine when possible, split
ENTRYPOINT/CMD, `WORKDIR=/usr/local/src/app`). This skill only covers what
changes for Python + uv.

## Base images

- **Builder**: `ghcr.io/astral-sh/uv:python3.13-bookworm-slim` (debian-slim).
  The uv-distributed images ship `uv` itself plus the matching CPython —
  zero extra layers for the toolchain.
- **Runtime**: `python:3.13-slim-bookworm` by default. uv is **not** needed
  at runtime — only the venv it produced.
- **Alpine variant** — `ghcr.io/astral-sh/uv:python3.13-alpine` +
  `python:3.13-alpine` — works when the project has **no glibc-linked
  binary wheels**. Most pure-Python apps fit. Things that don't:
  - `numpy`, `scipy`, `pandas`, `scikit-learn`, `pytorch`, `tensorflow`
  - `pyarrow`, `polars` (prebuilt wheels)
  - `psycopg2-binary`, `grpcio` (prebuilt), `lxml` (prebuilt)
  - Anything pulling `manylinux*` wheels — those are glibc-only.
  → For any of the above, stay on `-slim`.

## Reference shape

Start from [`assets/Dockerfile`](assets/Dockerfile) (copied to the project
root) and [`assets/dockerignore`](assets/dockerignore) (copied as
`.dockerignore`). Replace `<package>` with the import package. The shape:

- **builder** on the uv image: deps first (`pyproject.toml` + `uv.lock`,
  `--no-install-project`), then the package — the deps layer stays cached
  until the lockfile changes;
- **runtime** on `python:*-slim` without uv: only `.venv` and the package,
  owned by the system user `app`, `USER app` before `ENTRYPOINT`;
- `uvicorn` as `ENTRYPOINT`, the app and its flags as `CMD`, on port **8080**
  (Cloud Run's default, the port `cloud-run-cicd-gha` deploys with).

## uv-specific env vars (builder)

| Var | Why |
|---|---|
| `UV_COMPILE_BYTECODE=1` | Pre-compile `.pyc` at install time → faster cold-start. |
| `UV_LINK_MODE=copy` | Avoid hardlinks across the bind-mounted cache (which can fail). |
| `UV_PYTHON_DOWNLOADS=0` | Don't let uv pull its own Python in CI — pin via the base image. |

## What goes in the runtime image

- `${APP_DIR}/.venv` — the uv-built venv (deps + your project, installed
  as a wheel).
- Your source tree if the project is **not** installed as a package
  (importable from `src/...`). If `pyproject.toml` declares an entry
  point or you `pip install -e .`/`uv sync` your package, you may not
  even need to copy `src/` separately — it's already inside `.venv`.

## What NOT to include

- `uv` itself (use `python:*-slim` not `ghcr.io/astral-sh/uv:*` for the
  runtime).
- `pyproject.toml` / `uv.lock` (only the builder needs them).
- Tests, docs, fixtures (`.dockerignore` them).
- Build-time secrets (`uv sync` doesn't need them — fetch index creds
  via `--mount=type=secret`).

## ASGI / WSGI entrypoint

The asset splits `ENTRYPOINT ["uvicorn"]` and `CMD ["<package>.main:app", …]`,
so the container can be run as
`docker run my-image <package>.main:app --reload --port 9000`, overriding just
the args. For a non-ASGI app, use `ENTRYPOINT ["python"]` and
`CMD ["-m", "<package>.main"]`.
