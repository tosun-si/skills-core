---
name: cloud-run-cicd-gha
description: Conventions for GitHub Actions CI/CD pipelines that build with Docker Bake and deploy to Cloud Run. Covers the dev-on-trunk + tag-on-prd split (ci-cd.yml on push-to-main, release.yml on v*.*.* tags), Workload Identity Federation auth (no JSON keys), per-env service-account impersonation, repo-level Variables (not Secrets) for identifiers, image-and-cache to shared Artifact Registry, deploy-cloudrun GitHub Action, and the GitHub Release publish at the end. Trigger when creating, editing, or reviewing `.github/workflows/{ci-cd,release}.yml`, wiring WIF, designing a Cloud Run promotion model, or splitting CI per env. For the deploy target's IAP shape, see `cloud-run-iap`; for the bake config it builds, see `docker-bake-cache`.
---

# Cloud Run CI/CD with GitHub Actions

Three-file split:

- **`ci-cd.yml`** — runs on every push/PR to `main` and on
  `workflow_dispatch`. Lint + test on every event. Build + deploy to **dev**
  only on push-to-main (or manual dispatch).
- **`release.yml`** — runs on `v*.*.*` tag pushes. Build (same image,
  semver tag), deploy to **prd**, publish a GitHub Release.
- **`iac.yml`** *(optional)* — Terragrunt plan on PR/main, apply on
  `iac-v*.*.*` tags. Out of scope for this skill — see `terragrunt-modular-style`.

## Auth model — Workload Identity Federation, never JSON keys

GitHub's OIDC token is exchanged for short-lived GCP credentials via WIF.
Two service accounts (one per env), both bound to the same WIF pool.

| Env | CI/CD SA impersonated | Workflow file |
|---|---|---|
| dev | `sa-cicd-fac-dev@<bootstrap-project>.iam.gserviceaccount.com` | `ci-cd.yml` |
| prd | `sa-cicd-fac-prd@<bootstrap-project>.iam.gserviceaccount.com` | `release.yml` |

Each CI/CD SA has `roles/run.developer`, `roles/iam.serviceAccountUser` on
the runtime SA, and `roles/artifactregistry.writer` on the AR repos —
**nothing else**. The runtime SA (separate, per-service) gets the app's
actual permissions.

## Repo variables (not secrets) — settings

These are **identifiers**, not credentials. Use **Settings → Variables → Actions**
(org-level if shared across repos, scoped to selected repos):

| Variable | Value | Used by |
|---|---|---|
| `GCP_WIF_PROVIDER` | Full WIF provider resource name (output of foundation) | both |
| `GCP_SA_FAC_DEV` | `sa-cicd-fac-dev@<bootstrap>.iam.gserviceaccount.com` | `ci-cd.yml` |
| `GCP_SA_FAC_PRD` | `sa-cicd-fac-prd@<bootstrap>.iam.gserviceaccount.com` | `release.yml` |

App-specific runtime config (Cloud SQL DSNs, bucket names, etc.) goes in
its own repo variables; secrets (session keys, DB passwords) belong in
**Secret Manager**, mounted at deploy time via `--set-secrets`.

## `ci-cd.yml` — lint, test, build, deploy-to-dev

Start from [`assets/ci-cd.yml`](assets/ci-cd.yml): copy it to
`.github/workflows/ci-cd.yml`, replace `<app>`, `<secret-name>` and the
`KEY*` variables, and adjust the bake targets for monorepos. It runs
lint + test on every push and PR, and builds and deploys to dev on `main`.

Notes:

- **`if:` on the deploy job** — PRs and feature-branch pushes run lint+test
  but never deploy. Manual dispatch from any branch *does* deploy (useful
  for hotfix branches before merge).
- **`--update-env-vars` always passes every app env explicitly** so Cloud
  Run never inherits stale values from a previous revision. Missing
  variables expand to `""` — handle that gracefully in the app
  (pydantic-settings field validator).
- **Tag with `${{ github.sha }}`** for full traceability. The `:latest`
  tag on the AR repo is forbidden by `immutable_tags = true` — every
  deploy is a new immutable artifact.
- **Database migrations**, if any, run between bake and deploy.

## `release.yml` — tag-driven prd deploy

Start from [`assets/release.yml`](assets/release.yml), copied to
`.github/workflows/release.yml`: same build as `ci-cd.yml`, but on a
`v*.*.*` tag, with the prd runtime project and SA, the semver as image tag,
and a GitHub Release with generated notes.

The prd job runs in the **GitHub Environment** `prd` (`environment: prd`). On plans that support *deployment protection
rules* (Pro/Team/Enterprise on private repos, or any plan on public repos),
this gates apply behind required reviewers. On **GitHub Free for private
repos**, protection rules aren't available — the `environment:` key becomes a
label, and the human gate moves to the **RC tag pattern**
(`v0.1.0-rc1` → `v0.1.0`). See `release-split-app-iac-groupbees` for the
full pattern.

## Multi-target repos (e.g. SPA + BFF)

When the repo ships multiple Cloud Run services, the bake file already
defines one target per image (see `docker-bake-cache`). The workflow:

1. **Build** stays the same — `docker buildx bake` builds and pushes both
   targets in one step.
2. **Deploy** is one `deploy-cloudrun` step per service, both gated on
   the same `if:` and `needs:`. They can run sequentially (cheap, easy
   to read) or in parallel (separate jobs sharing the build job's image
   tag).
3. **Order matters when** one service needs the other's URL at deploy
   time (e.g. UI's `VITE_API_BASE_URL` baked at build → solve via
   custom domain or a two-pass build).

## Triggers — when each workflow fires

| Trigger | `ci-cd.yml` | `release.yml` |
|---|---|---|
| Push to feature branch | lint+test only | — |
| PR to main | lint+test only | — |
| Push to main | lint+test → build → **deploy dev** | — |
| Manual dispatch (any branch) | lint+test → build → **deploy dev** | — |
| Push tag `v*.*.*` | — | build → **deploy prd** + GitHub Release |
| Push tag `iac-v*` | — | — (handled by `iac.yml`) |

Tag prefix `v` is for app releases; `iac-v` for infra releases — keeps
app tags from accidentally applying infrastructure changes.

## Path filtering — fire only on what matters

When the repo contains more than the app (an `iac/` tree with its own
`iac.yml`, docs, scripts, etc.), gate `ci-cd.yml`'s `push` and `pull_request`
triggers with **`paths-ignore`** — otherwise a pure-IaC change to `main`
re-runs the full app build + dev deploy for nothing:

```yaml
on:
  push:
    branches: [main, 'feature/**']
    paths-ignore:
      - 'iac/**'
      - '.github/workflows/iac.yml'
      - '**/*.md'                       # README / CLAUDE.md / etc.
  pull_request:
    branches: [main]
    paths-ignore:
      - 'iac/**'
      - '.github/workflows/iac.yml'
      - '**/*.md'
  workflow_dispatch:                    # never path-filtered (manual)
```

Apply the symmetric **`paths`** filter on `iac.yml` so an app-only change
doesn't trigger a Terragrunt plan:

```yaml
on:
  pull_request:
    paths:
      - 'iac/**'
      - '.github/workflows/iac.yml'
  push:
    branches: [main]
    tags: ['iac-v*']
    paths:
      - 'iac/**'
      - '.github/workflows/iac.yml'
```

Notes:
- Path filters apply to `push` and `pull_request` **only** — not to
  `workflow_dispatch` or `tags`. Tag-driven releases (`release.yml`, `iac.yml`
  apply) are unaffected, as intended.
- Prefer **`paths-ignore`** on `ci-cd.yml` (a tiny exclusion list of foreign
  concerns) over an inclusion-list `paths` (which forces you to enumerate every
  app path and update it as the repo grows).
- Prefer **`paths`** on `iac.yml` (the IaC concern *is* a small inclusion list).
- This pattern generalizes — any monorepo workflow gains from "fire only on
  what matters". For the dedicated app+IaC split, see
  `release-split-app-iac-groupbees`.
