# 🐝 skills-core

> My transverse engineering skills — Python (hexagonal, uv, tests), Docker,
> CI/CD to Cloud Run, GCP (IAP), Terragrunt, git conventions. Born at
> GroupBees, published for the talk *Industrialiser l'IA en équipe : des
> skills qui encodent vos conventions* (Cloud Nord 2026).

## 🎯 Purpose

A **skills module**: a catalog of engineering conventions, composed with
others in a project's `pollen.yaml`. The `*-groupbees` skills (commits, PRs,
tags, releases) are the GroupBees team's own conventions, kept as a real-world
example of what a team encodes — adapt them to yours. Each skill is a standard
**Agent Skill** (`SKILL.md`, the [agentskills.io](https://agentskills.io) open
standard), read natively by **Claude Code**, **GitHub Copilot** and **Cursor**,
with no per-tool conversion.

## 🚀 Usage

Install with [pollen](https://github.com/groupbees/pollen): add this module to
your project's `pollen.yaml` (or to `~/.config/pollen/pollen.yaml` for every
project, `pollen update -g`), then run `pollen update`.

```yaml
repos:
  - repo: https://github.com/tosun-si/skills-core
    revision: v0.4.0   # then `pollen autoupdate --freeze` pins its commit
    paths:
      - path: skills/python     # or pick domains: skills/docker, skills/cicd…
      - path: skills/docker
```

Everything else about pollen — pinning, updates, errors — is in its docs and in
the `pollen` skill it ships (add `groupbees/pollen` with `path: skills`).

### Modules

skills-core is one module among others. Skill names must
be **unique across modules** (they deploy flat and map to a single `/<name>`).
Bootstrap a new module with the
[`skills-module-generator`](skills/meta/skills-module-generator/SKILL.md) skill.
See [AGENTS.md](AGENTS.md) for the full model.

## 📋 Skills Catalog

<!-- BEGIN skills-table — auto-generated from skills/*/*/SKILL.md by scripts/skills-catalog.sh --readme; do not edit by hand -->
| Domain | Skill | Description |
|--------|-------|-------------|
| CI/CD | [cloud-build-conventions](skills/cicd/cloud-build-conventions/) | Conventions for writing Google Cloud Build configurations (cloudbuild.yaml). Trigger when creating, editing, or reviewing cloudbuild.yaml, or when discussing how to build Docker images in GCP CI/CD pipelines with Buildx + registry cache. |
| CI/CD | [cloud-run-cicd-gha](skills/cicd/cloud-run-cicd-gha/) | Conventions for GitHub Actions CI/CD pipelines that build with Docker Bake and deploy to Cloud Run. Covers the dev-on-trunk + tag-on-prd split (ci-cd.yml on push-to-main, release.yml on v*.*.* tags), Workload Identity Federation auth (no JSON keys), per-env service-account impersonation, repo-level Variables (not Secrets) for identifiers, image-and-cache to shared Artifact Registry, deploy-cloudrun GitHub Action, and the GitHub Release publish at the end. Trigger when creating, editing, or reviewing `.github/workflows/{ci-cd,release}.yml`, wiring WIF, designing a Cloud Run promotion model, or splitting CI per env. For the deploy target's IAP shape, see `cloud-run-iap`; for the bake config it builds, see `docker-bake-cache`. |
| Docker | [docker-bake-cache](skills/docker/docker-bake-cache/) | Conventions for writing Docker Bake (docker-bake.hcl) files with registry-cached builds against a private Artifact Registry repo. Trigger when creating, editing, or reviewing docker-bake.hcl, or when discussing multi-target Docker builds with cache. |
| Docker | [docker-image-conventions](skills/docker/docker-image-conventions/) | Stack-agnostic conventions for writing production-grade Dockerfiles — multi-stage builds (builder + lean runtime), non-root user at runtime, smallest viable base image (alpine when possible, slim/debian when glibc-linked libs force it), split `ENTRYPOINT` / `CMD`, layered caching, `WORKDIR=/usr/local/src/app`. Includes per-language cheatsheets (Node, Go, Rust, JVM, Nginx) and a decision rubric for alpine vs slim. Trigger when creating, editing, or reviewing any Dockerfile, picking a runtime base image, dropping root in an existing image, or discussing image-size / hardening. For Python+uv specifically, see `python-docker-multistage` (it composes on top of this skill). |
| Docker | [python-docker-multistage](skills/docker/python-docker-multistage/) | Python-specific extensions to the universal Docker conventions — uv as the builder, alpine vs slim decision rules for Python (most prebuilt scientific wheels need glibc → slim), `uv sync --frozen --no-dev` pattern, layered caching with pyproject.toml + uv.lock, runtime image without uv. Trigger when creating, editing, or reviewing a Dockerfile in a Python project using uv. For the universal multi-stage + non-root + base-image patterns this skill builds on, see `docker-image-conventions`. |
| Env | [direnv-local-env](skills/env/direnv-local-env/) | Stack-agnostic conventions for managing local environment variables with direnv. Covers the committed `.envrc.example` + gitignored `.envrc` pattern, common stdlib helpers (`PATH_add`, `source_up`, `source_env_if_exists`, `layout`), monorepo layouts, the secret-split pattern (`.envrc.local`), and per-stack cheatsheets (GCP / Terraform / Terragrunt / Java / Kotlin / Node). Trigger when writing/editing any `.envrc`, choosing repo-root vs per-subfolder direnv, deciding between direnv and `.env` files, or wiring env vars for GCP, Terraform, JVM tooling, or any non-Python project. For uv-managed venv activation specifically, see the `python-uv-direnv` skill (it composes on top of this one). |
| GCP | [cloud-run-iap](skills/gcp/cloud-run-iap/) | Conventions for deploying Cloud Run services protected by Identity-Aware Proxy (IAP) — the GA-as-of-March-2026 "IAP-direct" pattern that enables IAP via a single `--iap` flag, NO external load balancer, no extra cost. Covers gcloud commands, IAM bindings (IAP service agent → roles/run.invoker, end users → roles/iap.httpsResourceAccessor), per-service vs shared service-account choice, when an LB is still required (custom domain, Cloud Armor, single domain for multiple services), and the SPA + BFF deployment shape. Trigger when deploying a Cloud Run service that needs browser-side auth, choosing between IAP-direct and IAP-with-LB, planning SPA + API on Cloud Run, or designing per-service IAM. For CI/CD wiring of these deploys, see `cloud-run-cicd-gha`. |
| Git | [commit-groupbees](skills/git/commit-groupbees/) | Commit message conventions for GroupBees repos (github.com/groupbees/*). Trigger when creating a git commit in a GroupBees repository — any repo whose path or remote URL contains "groupbees". Covers descriptive titles, HEREDOC for multi-line bodies, and the rule that NO Co-Authored-By trailer is added even on AI-assisted commits. Do NOT trigger for non-GroupBees personal or other-org work. |
| Git | [pr-groupbees](skills/git/pr-groupbees/) | Pull Request title, description, and labeling conventions for GroupBees repos (github.com/groupbees/*). Trigger when creating or updating a PR in a GroupBees repository — any repo whose path or remote URL contains "groupbees". Includes the structured body template, label-driven release-notes categorization, the prerequisite that labels must be created in the repo before they can be applied (with the GroupBees color convention), and the merge strategy (squash by default, rebase-merge for PRs whose commits each stand on their own). Do NOT trigger for non-GroupBees work. |
| Git | [release-split-app-iac-groupbees](skills/git/release-split-app-iac-groupbees/) | Conventions for releasing a GroupBees repo that contains BOTH application code AND infrastructure-as-code with TWO distinct tag prefixes — `vX.Y.Z` for the app (release.yml) and `iac-vX.Y.Z` for IaC (iac.yml apply). Covers the tag-pattern split, iac.yml plan/apply gating, stack matrix, prd environment gate, GitHub Release allocation, and the IaC-first ordering for a new repo's first release. Trigger when designing/reviewing release.yml + iac.yml in a GroupBees app+IaC monorepo (github.com/groupbees/*), choosing tag prefixes, or deciding the order of the first prd tags. Do NOT trigger for non-GroupBees work. Composes on top of tag-groupbees (semver) and pr-groupbees (release notes). |
| Git | [tag-groupbees](skills/git/tag-groupbees/) | Conventions for creating release tags in GroupBees internal repos (github.com/groupbees/* — private apps, IaC, skills catalogs), where a tag triggers a deployment. Trigger when creating, pushing, or designing a git tag in such a repository — any repo whose path or remote URL contains "groupbees" and that is not a public open-source project. Covers the semver + `v`-prefix scheme, annotated tags with HEREDOC messages, pre-release suffixes (`-rc`, `-alpha`, `-beta`), the pre-tag checklist (CI green on main, PR labels in place), the post-tag CI flow (apply job + release job), and what to avoid (force-moving tags, tagging from feature branches, lightweight tags). Do NOT trigger for public open-source projects, even under the groupbees org (e.g. pollen, skills-opensource) — those use `tag-opensource`; nor for non-GroupBees work. |
| Meta | [agents-md-manager](skills/meta/agents-md-manager/) | Creates and updates a thin, project-local AGENTS.md (the cross-agent context standard read by GitHub Copilot, Cursor and Codex) plus a one-line CLAUDE.md bridge so Claude Code picks it up; holds only durable, non-derivable project context and points to the catalog skills as source of truth. Trigger when creating a new project or service, documenting a project for the next developer or for coding agents, creating or editing AGENTS.md or CLAUDE.md, or when a durable project decision should be recorded for agents. Skip for the design rationale (architecture-conventions) and run commands (README.md). |
| Meta | [skills-module-generator](skills/meta/skills-module-generator/) | Creates a new skills module end to end, in the groupbees org or under a personal account — a repo scaffolded from skills-core (catalog script, CI through the shared groupbees/.github workflow, Dependabot, README/AGENTS/CONTRIBUTING from assets), its first skill, the checks, publication on GitHub (private or public) and the first release. Use when creating a new skills catalog module such as skills-data, a client-specific module, a public open-source one or a personal one. |
| Python | [python-hexagonal-clean-archi](skills/python/python-hexagonal-clean-archi/) | Conventions for structuring a Python service with hexagonal architecture (ports & adapters) and clean-architecture layering — domain / application / infrastructure, one-way dependency rule, single composition root for DI, *UseCase classes for use cases, fake repositories in conftest for tests, SQL-first Alembic migrations. Trigger when initializing a new Python service that needs business-logic separation, adding a new use case / port / adapter to an existing such project, reviewing layer boundaries, or deciding between a manual composition root and a DI library (dependency-injector / wireup / lagom). Framework-agnostic but examples use FastAPI + SQLAlchemy + asyncpg. For CLIs, SDKs, MCP servers and open-source tool cores, use python-hexagonal-flat instead. |
| Python | [python-hexagonal-flat](skills/python/python-hexagonal-flat/) | Flat hexagonal architecture (ports & adapters) for Python tech products — CLIs, SDKs, MCP servers and open-source cores that a SaaS later builds on. One package with core/ (pure rules), ports.py (Protocols), service.py (one function per operation, ports as keyword arguments), adapters/, wiring.py (lazy adapters), thin entrypoints (cli.py, mcp.py), structural fakes in tests. Trigger when initializing such a tool, adding an operation, port, adapter or entrypoint to one, or deciding between this flat layout and the layered domain/application/infrastructure one. For HTTP services with a database, use python-hexagonal-clean-archi instead. |
| Python | [python-uv-direnv](skills/python/python-uv-direnv/) | Python-specific conventions for managing a uv-managed venv with direnv auto-activation. Covers two layouts — single-package (`pyproject.toml` at the repo root) and polyglot monorepo (Python project in a subfolder, venv activated from a root `.envrc`). Trigger when initializing a Python project, writing/editing the venv-activation block in a `.envrc`, choosing between root-vs-subfolder venv locations, or wiring uv into a polyglot repo. For generic direnv conventions (env-file mechanics, gitignore, stdlib helpers, per-stack cheatsheets like GCP / Terraform / JVM / Node), see the `direnv-local-env` skill — this one composes on top of it. |
| Python | [unit-test-given-when-then](skills/python/unit-test-given-when-then/) | Generates Python unit tests following Given-When-Then convention with pytest and Pydantic validation patterns |
| Terraform | [terragrunt-modular-style](skills/terraform/terragrunt-modular-style/) | Conventions for structuring Terragrunt repos — file layout (live/ + modules/internal,shared), single foundation SA impersonation model, numbered stacks, dependency block patterns with mocks, generated backend/providers, per-stack state buckets, and tag-driven apply. Trigger when creating, editing, or reviewing terragrunt.hcl / root.hcl / org.hcl, or when designing a new Terragrunt foundation or stack structure. |
<!-- END skills-table -->

> This table is **generated** from the skills' `description` fields. Regenerate
> it with `scripts/skills-catalog.sh --readme`; CI fails if it is out of date.

## ✅ CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) calls the shared
[`skills-module`](https://github.com/groupbees/.github/blob/main/.github/workflows/skills-module.yml)
workflow of `groupbees/.github` (pinned, bumped by Dependabot) on every PR:

| Check | Command |
|-------|---------|
| Spec + quality | `skill-validator check --strict skills/` |
| Deployable | `pollen validate` on every skill, with a throwaway config |
| Generated table · unique names | `scripts/skills-catalog.sh --check-readme` · `--check-names` |
| Scripts | `shellcheck` on every `*.sh` |

We use [agent-ecosystem/skill-validator](https://github.com/agent-ecosystem/skill-validator)
rather than the official validator alone: same spec checks, plus token budgets,
link resolution, orphan-file and description-quality analysis, with native
GitHub Actions annotations.

## 🏷️ Versioning

Repo-wide via git tags (`vX.Y.Z`); the **GitHub Releases page is the
changelog** — no hand-maintained `CHANGELOG.md`.

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
