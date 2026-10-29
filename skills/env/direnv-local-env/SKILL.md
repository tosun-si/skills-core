---
name: direnv-local-env
description: Stack-agnostic conventions for managing local environment variables with direnv. Covers the committed `.envrc.example` + gitignored `.envrc` pattern, common stdlib helpers (`PATH_add`, `source_up`, `source_env_if_exists`, `layout`), monorepo layouts, the secret-split pattern (`.envrc.local`), and per-stack cheatsheets (GCP / Terraform / Terragrunt / Java / Kotlin / Node). Trigger when writing/editing any `.envrc`, choosing repo-root vs per-subfolder direnv, deciding between direnv and `.env` files, or wiring env vars for GCP, Terraform, JVM tooling, or any non-Python project. For uv-managed venv activation specifically, see the `python-uv-direnv` skill (it composes on top of this one).
---

# Local env vars with direnv

`direnv` reads a `.envrc` script the moment you `cd` into a directory and
exports its variables into the shell. Tools like `gcloud`, `terraform`,
`gradle`, `pnpm`, `docker compose`, `pydantic-settings`, and Vite all read
from the process environment — so direnv is the single point that makes
**every** local tool agree on the same values, without `.env` files.

## Core rules

- **No `.env` files.** Direnv writes straight into the process env.
  Frameworks that parse `.env` (pydantic-settings, Vite, dotenv-cli) read
  the process env first — duplicating into a `.env` is dead weight.
- **Commit `.envrc.example`**, gitignore the real `.envrc` and `.direnv/`.
- The `.envrc.example` is a runnable bash script: `cp .envrc.example .envrc`,
  fill in placeholders, then `direnv allow`. No special syntax — just
  `export FOO=bar` and direnv stdlib calls.
- One repo, **one root `.envrc`** by default. Add per-subfolder `.envrc`
  only when subfolders need *additional* setup the root doesn't (and then
  start the child file with `source_up` to inherit).

## Gitignore essentials

```
.envrc                 # secrets — commit .envrc.example instead
.envrc.local           # if you use the secret-split pattern below
.direnv/               # direnv's per-shell cache
```

## direnv stdlib cheatsheet

These are bash functions direnv injects into `.envrc`:

| Helper | What it does |
|---|---|
| `PATH_add <dir>` | Prepend `<dir>` to `PATH` for this shell. |
| `path_add <var> <dir>` | Same but for any colon-separated var (`MANPATH`, etc.). |
| `source_up [<file>]` | Source the closest parent `.envrc` walking upward. Use in a child `.envrc` to inherit the root. |
| `source_env_if_exists <file>` | Source `<file>` only if present — perfect for the `.envrc.local` secret split. |
| `dotenv [<file>]` | Load a `.env` file. **Avoid** — pulls you back into `.env` land. |
| `watch_file <file>` | Reload the `.envrc` whenever `<file>` changes (e.g. `pyproject.toml`). |
| `layout <stack>` | Bundled per-stack helpers (`layout python`, `layout node`, …). Useful but opaque — prefer explicit `export VIRTUAL_ENV=...` + `PATH_add` for transparency. |
| `has <cmd>` | Returns true if `<cmd>` is on `PATH`. Guard optional setup. |

## Secret-split pattern

Some teams want a committed `.envrc` that holds the *layout* (PATH munging,
tool selection) but gitignored secrets. Pattern:

```bash
# .envrc — committed
export CLOUDSDK_CORE_PROJECT=my-dev-project
export TF_VAR_environment=dev
source_env_if_exists .envrc.local      # secrets live here, gitignored
```

```bash
# .envrc.local — gitignored, copied from .envrc.local.example
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/gcloud/keys/my-sa.json"
export TF_VAR_db_password=hunter2
```

Use this when the layout is repo-public knowledge and only the secrets are
sensitive. For prototypes, the simpler "everything in gitignored `.envrc`,
commit `.envrc.example`" is fine.

## Monorepo layouts

### Layout A — single root `.envrc` (recommended default)

All env lives at the repo root. Subfolders inherit automatically because
direnv walks up looking for the closest `.envrc` and finds the root one.

```
<repo>/
├── .envrc              # gitignored — exports everything
├── .envrc.example      # committed template
├── bff/                # no .envrc here
├── ui/                 # no .envrc here
└── docker-compose.yml  # reads ${VAR} from the shell direnv populated
```

Best when subfolders don't need stack-specific setup beyond inheriting the
root env.

### Layout B — root `.envrc` + per-subfolder additions

When a subfolder needs *extra* setup (e.g. a JVM-only subproject needing
`JAVA_HOME` switching), add a child `.envrc` starting with `source_up`:

```bash
# api/.envrc
source_up                              # inherit the root .envrc first
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
PATH_add "$JAVA_HOME/bin"
```

This keeps the root file uncluttered while specialising on `cd api`.

## Per-stack cheatsheets

The core rules above apply to every stack. For the `.envrc` block of a stack,
read **only** the matching file:

| Stack | Reference |
|-------|-----------|
| GCP (`gcloud`, ADC, impersonation) | [`references/gcp.md`](references/gcp.md) |
| Terraform / Terragrunt | [`references/terraform.md`](references/terraform.md) |
| Java / Kotlin (JVM) | [`references/jvm.md`](references/jvm.md) |
| Node / pnpm / Vite | [`references/node.md`](references/node.md) |
| docker compose | [`references/docker-compose.md`](references/docker-compose.md) |
| Python + uv | the `python-uv-direnv` skill |

## When NOT to use direnv

- **CI**: CI runners get env from the platform (GitHub Actions `env:`,
  Cloud Build substitutions). Don't ship `.envrc` for CI.
- **Production runtimes**: Cloud Run / Kubernetes / systemd inject env via
  their own mechanisms. `.envrc` is a *local-dev* convenience.
- **Truly sensitive secrets**: keep them in a secret manager (1Password,
  GCP Secret Manager) and have `.envrc` *fetch* them at allow-time, e.g.
  `export DB_PASSWORD="$(op read 'op://Dev/my-db/password')"`.
