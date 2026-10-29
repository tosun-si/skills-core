---
name: skills-module-generator
description: Creates a new skills module end to end, in the groupbees org or under a personal account — a repo scaffolded from skills-core (catalog script, CI through the shared groupbees/.github workflow, Dependabot, README/AGENTS/CONTRIBUTING from assets), its first skill, the checks, publication on GitHub (private or public) and the first release. Use when creating a new skills catalog module such as skills-data, a client-specific module, a public open-source one or a personal one.
---

# Skill: Skills Module Generator

## Context

A **skills module** is a git repo of Agent Skills that consumers import with
[pollen](https://github.com/groupbees/pollen) (`pollen.yaml` → `pollen update`).
Every module is born **identical to `skills-core`**: same CI, same catalog
script, same docs layout. A new module is justified when a family of skills has
**a different audience or visibility** than the existing ones — a client
engagement, a domain only some projects need, or conventions that can be public.

> **`skills-core` is the reference implementation.** The invariant files are
> copied verbatim from it; only the per-module files are rendered from
> [`assets/`](assets/). Nothing is re-authored by hand, so modules cannot
> drift.

## Anatomy of a module

| File | Source |
|------|--------|
| `scripts/skills-catalog.sh` (skill list, README table, unique names) | copied verbatim from skills-core |
| `.github/workflows/ci.yml` (one call to the shared `groupbees/.github` workflow), `.github/dependabot.yml`, `.gitignore`, `.gitattributes`, `CLAUDE.md` | copied verbatim |
| `README.md` (with the generated skills table) | [`README.md.template`](assets/README.md.template) |
| `AGENTS.md` (how the repo works — single source of truth) | [`AGENTS.md.template`](assets/AGENTS.md.template) |
| `CONTRIBUTING.md` | [`CONTRIBUTING.md.template`](assets/CONTRIBUTING.md.template) |
| `skills/<domain>/<name>/SKILL.md` — the first skill | [`SKILL.md.template`](assets/SKILL.md.template), then written for real |

[`scripts/new-module.sh`](scripts/new-module.sh) does all of the above in
one run.

## Inputs

| Input | Description | Example |
|-------|-------------|---------|
| `MODULE_NAME` | repo name, `skills-` prefix | `skills-data` |
| `MODULE_DESCRIPTION` | one line for the README | `Data engineering conventions for GroupBees projects` |
| `MODULE_PURPOSE` | 1–2 sentences, AGENTS.md *What this repo is* | `The source of truth for GroupBees' data engineering conventions — dbt, BigQuery, Airflow.` |
| `FIRST_SKILL` | `<domain>/<name>` of the first skill | `data/dbt-conventions` |
| `VISIBILITY` | `private` (default) or `public` — **ask the user** | `private` |
| `GITHUB_OWNER` | `groupbees` (default), or a personal account for a module only its author maintains | `tosun-si` |
| `SKILLS_ROOT` | where the repo is created; set it outside `groupbees/` for a personal module | `~/my-projects/skills` |
| `DOMAINS` | optional, Markdown list for CONTRIBUTING | `` `data`, `gcp` `` |

In the groupbees org, `VISIBILITY` sets the release skill: **private →
`tag-groupbees`** (internal, tags deploy), **public → `tag-opensource`** (tags
publish); commits and PRs follow `commit-groupbees` / `pr-groupbees`. Under
another owner, commits follow `commit-open-source` and releases
`tag-opensource`. The shared CI workflow is public, so any owner can call it.

## Workflow

### Step 1 — Check the name and the first skill against what exists

Skills deploy flat and map to a single `/<name>`, so names must be unique
**across modules**. List the skills of every sibling module and compare
semantically, not only by name:

```bash
for m in ~/my-projects/groupbees/skills/skills-*/; do
  [[ -x "$m/scripts/skills-catalog.sh" ]] && "$m/scripts/skills-catalog.sh" --list
done
```

If an existing skill covers the need, extend it instead of creating a module.

### Step 2 — Scaffold

```bash
G=~/my-projects/groupbees/skills/skills-core/skills/meta/skills-module-generator/scripts
MODULE_NAME=skills-data \
MODULE_DESCRIPTION="Data engineering conventions for GroupBees projects" \
MODULE_PURPOSE="The source of truth for GroupBees' data engineering conventions — dbt, BigQuery, Airflow." \
FIRST_SKILL=data/dbt-conventions VISIBILITY=private \
"$G/new-module.sh"
```

The script refuses an existing directory, a name without the `skills-` prefix,
or a first-skill name already present in a sibling module, and fails if any
`{{PLACEHOLDER}}` is left unrendered.

### Step 3 — Write the first skill

Replace the stub in `skills/<domain>/<name>/SKILL.md`: frontmatter is **only**
`name` (= folder name) + `description` (what it does AND when to trigger it —
this drives auto-use). No per-skill README. Bundle files with the Agent Skills
folders only, each linked from `SKILL.md`:

| Folder | For |
|--------|-----|
| `references/` | Detail needed only in some cases, one topic per file — say *when* to read it |
| `assets/` | Complete files the output starts from (`Dockerfile`, workflow, config) |
| `scripts/` | Deterministic checks or actions, run rather than described |

Rules and gotchas stay in `SKILL.md`. The full table is in the module's
`AGENTS.md`, *Anatomy of a skill*.

### Step 4 — Verify (the same checks as CI)

```bash
scripts/skills-catalog.sh --readme        # refresh the table after writing the skill
scripts/skills-catalog.sh --check-readme
scripts/skills-catalog.sh --check-names
for s in $(find skills -name SKILL.md -exec dirname {} \;); do
  skill-validator check --strict "$s"
done
printf 'repos:\n  - repo: local\n    paths:\n      - path: skills\n        recurse: true\n' > .pollen-preview.yaml
pollen validate --config .pollen-preview.yaml && rm .pollen-preview.yaml
find scripts skills -name '*.sh' -print0 | xargs -0 shellcheck
```

Tools: `brew install groupbees/tap/pollen agent-ecosystem/tap/skill-validator shellcheck`.

### Step 5 — Public only: pre-flight scan

A public module must not leak internal topology. Before the first push:

```bash
git grep -n -i -E '/Users/|my-projects|10\.[0-9]+\.[0-9]+\.|@groupbees\.|client'
```

Replace real project ids, CIDRs, bucket or service-account names, client names
and personal paths with placeholders (`<org>-<app>-dev`, `10.x.y.0/20`).

### Step 6 — Commit and publish

```bash
git add -A && git commit   # one commit, commit-groupbees conventions
gh repo create <GITHUB_OWNER>/<MODULE_NAME> --<private|public> \
  --description "<MODULE_DESCRIPTION>" --source . --remote origin --push
gh run watch --exit-status   # the first CI run must be green
```

Confirm the visibility with the user before `gh repo create` — a public repo is
indexed as soon as it is pushed.

### Step 7 — Release and wire consumers

- Cut `v0.1.0` with the release skill matching the visibility
  (`tag-groupbees` or `tag-opensource`).
- Consumers add the module as a source in their `pollen.yaml` (the README
  shows the block); how to pin and update it is the `pollen` skill's job —
  never restate pollen's usage in a module.

## Mandatory conventions

- `MODULE_NAME` keeps the `skills-` prefix. A team module lives in
  `~/my-projects/groupbees/skills/` under the groupbees org; a module only one
  person maintains (personal links, private notes) lives under that person's
  account.
- Skill names are unique **across all modules**.
- A module ships no `pollen.yaml`: it belongs to consumers (CI and previews
  use a throwaway one).
- Invariant files are copied verbatim from skills-core and never edited per
  module; improve them in skills-core, then copy them to the other modules.
- `AGENTS.md` is the single source of truth for the repo; `CLAUDE.md` only
  imports it. Tool knowledge (pollen) stays in that tool's skill: modules link
  to it instead of copying it.
- Versioning is git tags + GitHub Releases — no `CHANGELOG.md`, and no
  manifest repeats the version (no `skills-module.json`, no Agent Plugins
  `plugin.json` until a client needs one: its spec reads only
  `skills/<name>/`, not our `skills/<domain>/<name>/`).
- Everything in English.
