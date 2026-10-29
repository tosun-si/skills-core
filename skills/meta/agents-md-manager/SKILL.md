---
name: agents-md-manager
description: Creates and updates a thin, project-local AGENTS.md (the cross-agent context standard read by GitHub Copilot, Cursor and Codex) plus a one-line CLAUDE.md bridge so Claude Code picks it up; holds only durable, non-derivable project context and points to the catalog skills as source of truth. Trigger when creating a new project or service, documenting a project for the next developer or for coding agents, creating or editing AGENTS.md or CLAUDE.md, or when a durable project decision should be recorded for agents. Skip for the design rationale (architecture-conventions) and run commands (README.md).
---

# Skill: AGENTS.md Manager

## Context

This skill **creates or updates** a project-local `AGENTS.md` — the emerging
cross-tool context file that AI coding agents read at the root of a repo. Its job
is to keep that file **thin and correct over time**, never to duplicate what
already lives elsewhere.

It runs when a project is created or documented, so a new service ships its
`AGENTS.md` from the first change, and on demand afterwards ("update the
project AGENTS.md"). A generator skill may also call it at the end of a
scaffold to drop an initial file.

### Why AGENTS.md + a CLAUDE.md bridge

`AGENTS.md` is read **natively** by GitHub Copilot, Cursor, Codex and most of the
ecosystem. Claude Code reads it natively too **since v2.1.277** — but only when
there is **no `CLAUDE.md` or `CLAUDE.local.md`** in the working directory or
above it; when one exists, Claude reads the `CLAUDE.md` files *only*. It also
falls back to `CLAUDE.md`-only in sessions that cannot load `AGENTS.md`
(older versions, Amazon Bedrock or telemetry disabled, `instructionFiles:
claude-md`). So the skill keeps a **single source of truth** (`AGENTS.md`) and
drops a **one-line `CLAUDE.md`** that imports it:

```
@AGENTS.md
```

Result: one file to maintain, every agent covered (Copilot/Cursor/Codex read
`AGENTS.md`; Claude Code reads `CLAUDE.md` → imports `AGENTS.md`). Never duplicate
content between the two — `CLAUDE.md` stays a one-line pointer.

> **The golden rule** — a line belongs in the local `AGENTS.md` only if it passes
> **all three** tests:
> 1. It is **not already in a catalog skill** (those are referenced, never copied).
> 2. It is **not derivable from the code** (the agent reads the code directly).
> 3. It is **durable** — it would stay true after a large refactor.
>
> If a line would become false the moment a file changes, it describes the code →
> leave it out.

## Modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| `create` | No `AGENTS.md` at the target root | Generate from the template below + write the one-line `CLAUDE.md` bridge |
| `update` | An `AGENTS.md` already exists | Reconcile **only** the managed block; never touch hand-written content; ensure the `CLAUDE.md` bridge still exists |

The skill is **idempotent**: re-running `update` reconciles the managed block
without duplicating sections, and re-creates the `CLAUDE.md` bridge only if missing.

## Required inputs

Reuse the parameters already collected by the calling generator when possible
(`DOMAIN`, `PROJECT_NAME`, `DESCRIPTION`, `REPO_LAYOUT`). When invoked standalone,
infer them from the repo and ask the user only for what cannot be inferred.

| Input | Description | Source |
|-------|-------------|--------|
| `PROJECT_ROOT` | Where the `AGENTS.md` lives | the repo root (standalone), or the service folder in a monorepo |
| `DOMAIN` / `PROJECT_NAME` / `DESCRIPTION` | Project identity | Generator params or inferred |
| `APPLIED_SKILLS` | Catalog skills that govern this repo | Inferred from how the repo was generated |
| `PROJECT_SPECIFICS` | Jira key/epic, GCP projects per env, service accounts, non-obvious decisions | **Ask the user** — not derivable |

## Managed block

Everything the skill owns lives between two markers. Anything **outside** the
markers is the user's and is never modified:

```markdown
<!-- agents-md-manager:start — managed section, do not edit by hand -->
...generated content...
<!-- agents-md-manager:end -->
```

- `update` replaces only the text **between** the markers.
- If the markers are missing (e.g. a hand-written `AGENTS.md`), the skill inserts
  the managed block at the top and leaves the rest untouched — it never clobbers.

## `AGENTS.md` template

The generated file is intentionally short (~20–30 lines): render
[`assets/AGENTS.md.template`](assets/AGENTS.md.template) — read it when generating
or updating the file, and fill every `{{PLACEHOLDER}}` (`none yet` when unknown).
Its sections: *Identity*, *Conventions — source of truth* (referenced skills,
never copied), *Project specifics* (only what no skill holds and the code does
not show), then the free zone below the end marker.

The companion `CLAUDE.md` bridge is a **single line** (never more):

```
@AGENTS.md
```

## Workflow

### Step 1 — Locate the target

```bash
# Resolve PROJECT_ROOT from REPO_LAYOUT, then check for an existing file
ls "$PROJECT_ROOT/AGENTS.md" 2>/dev/null && echo "exists → update" || echo "missing → create"
```

### Step 2 — Gather only what passes the three tests

- Pull `DOMAIN` / `PROJECT_NAME` / `DESCRIPTION` / `REPO_LAYOUT` from the generator
  or infer them.
- Derive `APPLIED_SKILLS` from how the repo was built (e.g. an ELT repo →
  `ingestion-dag-generator` + `dag-code-structure`).
- **Ask the user** for `PROJECT_SPECIFICS` (Jira, GCP projects, SAs, decisions) —
  never invent them.

### Step 3 — Create or update

- **create**: render the template into `$PROJECT_ROOT/AGENTS.md`, then write the
  one-line `CLAUDE.md` bridge (`@AGENTS.md`) next to it.
- **update**: replace only the text between the markers; if markers are absent,
  prepend the managed block and keep the existing content below it. Ensure the
  `CLAUDE.md` bridge still exists (re-create it only if missing).

### Step 4 — Self-check against the golden rule

Before finishing, re-read each generated line and drop anything that is already in
a skill, derivable from the code, or volatile.

## Mandatory conventions

- **Never copy** convention bodies from skills — reference them by name only.
- **Never record** code-derivable facts (folder layout, dependencies, schedule).
- **Never edit** content outside the managed markers.
- Keep the managed block **short** — if it grows past ~30 lines, something
  code-derivable or skill-owned has crept in; remove it.
- **`CLAUDE.md` stays a one-line bridge** (`@AGENTS.md`) — never duplicate the
  project context into it.
- Write in **English**.
- Place `AGENTS.md` at the **project root** matching `REPO_LAYOUT` (monorepo:
  `<DOMAIN>/<PROJECT_NAME>/orchestration/`; standalone: repo root); the `CLAUDE.md`
  bridge sits next to it.
- This skill manages **project-local** files only — it never touches the
  user-level `~/.claude/CLAUDE.md` or `~/.agents/AGENTS.md`.

## Usage by generator skills

A generator can call this skill as its last scaffold step:

1. Pass the parameters it already collected (`DOMAIN`, `PROJECT_NAME`, …).
2. Let this skill render the initial managed block + the `CLAUDE.md` bridge.
3. Leave `PROJECT_SPECIFICS` as `<...>` placeholders for the user to fill, or ask.

## References

- `python-hexagonal-clean-archi`, `cloud-run-cicd-gha` — example callers: a generator
  runs this skill at the end so the new repo ships with its own `AGENTS.md`
- [Claude Code memory docs](https://code.claude.com/docs/en/memory) — Claude Code reads
  `AGENTS.md` natively since v2.1.277, but only when NO `CLAUDE.md` /
  `CLAUDE.local.md` sits in the working directory or above; the `@AGENTS.md`
  bridge covers the other cases (older versions, Bedrock / telemetry off,
  a dev's own `CLAUDE.local.md`, `instructionFiles: claude-md`)
- Claude Code `/init` — native codebase-derived context (this skill adds the GroupBees/project layer on top)
