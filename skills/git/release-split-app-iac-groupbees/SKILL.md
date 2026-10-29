---
name: release-split-app-iac-groupbees
description: Conventions for releasing a GroupBees repo that contains BOTH application code AND infrastructure-as-code with TWO distinct tag prefixes — `vX.Y.Z` for the app (release.yml) and `iac-vX.Y.Z` for IaC (iac.yml apply). Covers the tag-pattern split, iac.yml plan/apply gating, stack matrix, prd environment gate, GitHub Release allocation, and the IaC-first ordering for a new repo's first release. Trigger when designing/reviewing release.yml + iac.yml in a GroupBees app+IaC monorepo (github.com/groupbees/*), choosing tag prefixes, or deciding the order of the first prd tags. Do NOT trigger for non-GroupBees work. Composes on top of tag-groupbees (semver) and pr-groupbees (release notes).
---

# Splitting app + IaC releases in one GroupBees repo

When a GroupBees repo contains BOTH application code AND infrastructure-as-code,
release them with **two distinct tag prefixes** so they ship independently:

| Concern | Tag | Workflow | What it does |
|---|---|---|---|
| Application | `vX.Y.Z` | `.github/workflows/release.yml` | Build image → deploy prd → publish GitHub Release |
| IaC | `iac-vX.Y.Z` | `.github/workflows/iac.yml` (apply job) | `terragrunt apply` on prd, gated by the `prd` environment |

**Why split.** App and IaC have different lifecycles — app changes often, IaC
rarely. Coupling them under one tag (e.g. `v*.*.*` firing both) means each
service release re-applies Terragrunt (noise + risk), and each IaC release
forces an app rebuild. Different prefixes let you ship one without the other.

A first release of such a repo is two tags on one commit: `v0.1.0` + `iac-v0.1.0`.

## Tag patterns + workflow triggers

**`release.yml`** (app):

```yaml
on:
  push:
    tags: ['v*.*.*']
```

**`iac.yml`** (Terragrunt plan + apply):

```yaml
on:
  pull_request:
    paths: ['iac/**', '.github/workflows/iac.yml']
  push:
    branches: [main]                  # plan only on main pushes
    tags: ['iac-v*']                  # apply on iac-v* tags
    paths: ['iac/**', '.github/workflows/iac.yml']
  workflow_dispatch:
    inputs:
      action:
        type: choice
        options: [plan, apply]
        default: plan
```

The IaC pattern is **`iac-v*`** (broader than `v*.*.*`) — matches
`iac-v0.1.0`, `iac-v0.1.0-rc1`, etc. Don't tighten it to `iac-v*.*.*`: the
registry convention keeps it loose, and pre-releases like `iac-v0.1.0-rc1`
should also trigger apply.

## iac.yml shape (plan + apply, matrix per stack)

```yaml
jobs:
  plan:
    name: plan (${{ matrix.stack }})
    # Explicit filter: PR with iac changes, post-merge push to main, or
    # workflow_dispatch with action=plan. Plain pushes outside main don't plan.
    if: |
      github.event_name == 'pull_request'
      || (github.event_name == 'push' && github.ref == 'refs/heads/main')
      || (github.event_name == 'workflow_dispatch' && inputs.action == 'plan')
    strategy:
      matrix:
        stack: [dev/<stack>, prd/<stack>]
    # … terragrunt plan per stack

  apply:
    name: apply (${{ matrix.stack }})
    # Apply ONLY on iac-v* tag push or manual dispatch with action=apply.
    # Plain pushes to main never apply.
    if: |
      (github.event_name == 'push' && startsWith(github.ref, 'refs/tags/iac-v'))
      || (github.event_name == 'workflow_dispatch' && github.event.inputs.action == 'apply')
    needs: plan
    strategy:
      fail-fast: false
      max-parallel: 1                    # serialize applies for predictable state ordering
      matrix:
        stack: [dev/<stack>, prd/<stack>]
    environment: ${{ startsWith(matrix.stack, 'prd/') && 'prd' || 'dev' }}
    # … terragrunt apply --non-interactive
```

Key points:
- **Apply gate** by `if:` on tag-push matching `iac-v*` OR dispatch=apply.
- **Plan gate** by `if:` on PR + push-to-main + dispatch=plan. Without it, a
  push-to-main with `event_name == 'push'` could leak into the apply path.
- **Stack matrix** drives plan and apply by `iac/live/<env>/<stack>` directory.
- **`max-parallel: 1`** serializes applies so prd doesn't race dev.
- **`environment: prd`** scopes the apply to that env (visibility, IAM, branch
  restrictions) — but the *human approval gate* it provides depends on your
  GitHub plan. See the callout below.

> ⚠️ **`environment: prd` is NOT always a hard gate.** GitHub *deployment
> protection rules* (required reviewers, wait timer) are unavailable on
> **GitHub Free for private repos** — the common GroupBees case. On those
> plans, the `environment:` key is essentially a label; the apply job runs the
> moment the tag is pushed, with no approval prompt.
>
> When required reviewers aren't available, the human gate moves to **tagging
> itself**:
>
> 1. **RC tag → canonical** (recommended). Tag `iac-vX.Y.Z-rc1` first, inspect
>    the plan + apply, then tag the canonical `iac-vX.Y.Z` once healthy. The
>    human step *is* the push of the canonical tag.
> 2. **`workflow_dispatch` with `action=apply`** instead of tag-driven apply.
>    The tag just plans; an operator triggers apply manually after inspecting.
>
> Default to (1) — composes with `tag-groupbees`'s pre-release rules and works
> on every GitHub plan.

### Variant: `run --all` per env (no stack matrix)

When the iac layout drives a **single env per run** via `terragrunt run --all`
(rather than a stack matrix), env selection comes from the **tag ref**, not a
matrix value. Crucially, use `startsWith(github.ref, 'refs/tags/iac-v')`, NOT
`event_name == 'push'` — a plain push to main is *also* `event_name == 'push'`
but must route to dev/plan, never to prd/apply.

```yaml
apply:
  name: Apply (${{ startsWith(github.ref, 'refs/tags/iac-v') && 'prd' || inputs.environment }})
  if: |
    (github.event_name == 'push' && startsWith(github.ref, 'refs/tags/iac-v'))
    || (github.event_name == 'workflow_dispatch' && inputs.action == 'apply')
  environment: ${{ startsWith(github.ref, 'refs/tags/iac-v') && 'prd' || inputs.environment }}

concurrency:
  group: iac-${{ startsWith(github.ref, 'refs/tags/iac-v') && 'prd' || github.event.inputs.environment || 'dev' }}
```

## Path filters — the tag split alone isn't enough

The tag-prefix split prevents app releases from re-applying IaC. But on its
own, it does NOT prevent an IaC-only push to `main` from triggering
`ci-cd.yml`'s push handler — which re-runs the full app build + dev deploy for
nothing.

Pair the tag split with **`paths-ignore`** on `ci-cd.yml` and **`paths`** on
`iac.yml`:

```yaml
# ci-cd.yml — don't fire on iac-only changes
on:
  push:
    branches: [main, 'feature/**']
    paths-ignore: ['iac/**', '.github/workflows/iac.yml', '**/*.md']
  pull_request:
    branches: [main]
    paths-ignore: ['iac/**', '.github/workflows/iac.yml', '**/*.md']
```

Full pattern + rationale in `cloud-run-cicd-gha` § *Path filtering*. Without
it, the tag split avoids re-applying IaC on app releases — but app deploys
still fire on pure-IaC commits. Half the benefit.

## GitHub Release allocation

In the GroupBees convention, **only
`release.yml` publishes a GitHub Release** (via
`softprops/action-gh-release@v2`, after the prd deploy succeeds). `iac.yml`
does NOT publish a Release — the tag itself is the deploy record.

If your team wants Release traceability for IaC tags too, add a release job in
`iac.yml` gated on `if: success() && startsWith(github.ref, 'refs/tags/iac-v')`
with the same `softprops/action-gh-release@v2` pattern. That's a local choice;
the registry doesn't do it.

## First-release ordering (new repo)

For the **first prd tags** on a fresh repo:

1. **Tag IaC first** (`iac-v0.1.0-rc1` → `iac-v0.1.0`). Creates the Cloud Run
   service shells, runtime SAs, IAP bindings, IAM — the targets the app deploy
   needs to exist.
2. **Tag the app** (`v0.1.0-rc1` → `v0.1.0`) once IaC apply is green. The
   `deploy-cloudrun` step rolls the image onto the existing shell.

App tag before IaC tag on a fresh repo = `deploy-cloudrun` tries to create a
bare service without the Terraform-owned shell → drift, or worse, fail.

## Pre-release (`-rc1`) for risky firsts

Always pre-release the **first** apply of either side:
- `iac-v0.1.0-rc1` — first prd IaC apply (new SAs, new IAP, new state).
- `v0.1.0-rc1` — first prd image deploy.

Pre-releases are auto-marked as such by GitHub's tag-name heuristic
(`-rc/-alpha/-beta`). See `tag-groupbees` for the full pre-release rules.

## What to avoid

- ❌ **Single tag pattern firing both workflows.** App releases would force
  Terragrunt re-applies; IaC tags would force app rebuilds.
- ❌ **Tag-split without path filters on `ci-cd.yml`.** IaC-only pushes still
  redeploy the app — half the benefit of the split.
- ❌ **Applying IaC on push-to-main.** Apply is for tags only; pushes plan.
- ❌ **Tagging IaC after the app on a new repo.** Shells must exist first.
- ❌ **Same prefix for both** (e.g. `v0.1.0` for both kinds). Kills audit
  clarity and the Releases UI.
- ❌ **Tightening `iac-v*` to `iac-v*.*.*`** — would skip pre-release tags like
  `iac-v0.1.0-rc1`.
- ❌ **Tagging a red `main`.** The `plan` job runs on every PR and push; if it's
  red, the apply that the tag triggers will also be red. Check Actions first.

## Companion skills

- `tag-groupbees` — semver bump rules, annotated tags, pre-release suffixes,
  pre-tag checklist (CI green, PR labels). Use it for *both* prefixes.
- `pr-groupbees` — label-driven release-notes categorization (drives the app
  Release content).
- `commit-groupbees` — commit message conventions on `main`.
- `cloud-run-cicd-gha` — `ci-cd.yml` + `release.yml` shape for Cloud Run apps.
- `terragrunt-modular-style` — IaC repo layout and apply ordering.
