---
name: tag-groupbees
description: Conventions for creating release tags in GroupBees internal repos (github.com/groupbees/* — private apps, IaC, skills catalogs), where a tag triggers a deployment. Trigger when creating, pushing, or designing a git tag in such a repository — any repo whose path or remote URL contains "groupbees" and that is not a public open-source project. Covers the semver + `v`-prefix scheme, annotated tags with HEREDOC messages, pre-release suffixes (`-rc`, `-alpha`, `-beta`), the pre-tag checklist (CI green on main, PR labels in place), the post-tag CI flow (apply job + release job), and what to avoid (force-moving tags, tagging from feature branches, lightweight tags). Do NOT trigger for public open-source projects, even under the groupbees org (e.g. pollen, skills-opensource) — those use `tag-opensource`; nor for non-GroupBees work.
---

# GroupBees release tag conventions

Tags in GroupBees repos are **deployment triggers**, not history markers. Pushing a `v*` tag triggers the CI `apply` job (foundation IaC, app-IaC repos) and the GitHub Release generation downstream of it. Treat the tag push as the production deploy — be deliberate.

## Tag format

- **Format**: `vX.Y.Z` (semver, with `v` prefix). Always **annotated** (`git tag -a ...`), never lightweight.
- **Pre-release**: `vX.Y.Z-rc1`, `vX.Y.Z-rc2`, `vX.Y.Z-alpha1`, `vX.Y.Z-beta1`. The `release` job in `iac.yml` automatically flags these as GitHub prereleases via:
  ```
  contains(github.ref_name, '-rc') || contains(github.ref_name, '-alpha') || contains(github.ref_name, '-beta')
  ```
- **Bump rules** (semver):
  - **Patch** (`v1.2.0 → v1.2.1`): bugfix-only, no behavior change for consumers.
  - **Minor** (`v1.2.0 → v1.3.0`): additive non-breaking change (new resource, new module input with a default).
  - **Major** (`v1.2.0 → v2.0.0`): breaking change. For foundation repos, includes any change that forces app-IaC repos to update (module input rename, output removal, IAM-model shift).

For high-impact foundation changes, bias **toward bumping minor** even when technically a patch — it signals that an apply ran against prd, not just code reorg.

## Pre-tag checklist

Run [`scripts/pre-tag-check.sh vX.Y.Z`](scripts/pre-tag-check.sh) BEFORE `git tag`.
It is read-only and checks items 1–4: tag format and uniqueness, `main` clean
and in sync with origin, CI green on `HEAD`, then lists the commits and the
unlabeled PRs since the previous tag. Item 5 stays a judgment call.

What it checks, and why:

1. **Local `main` is up to date with origin**:
   ```bash
   git fetch && git checkout main && git pull --ff-only
   ```
2. **CI is green on the commit you're tagging**. Check the Actions tab for the latest commit on `main`. If the apply-plan run is red, fix that first — tagging a red commit means apply will fail and the Release won't be generated.
3. **PR titles since the last tag are descriptive** — they become the release-note bullets. The PR-titles-as-changelog convention is enforced by `pr-groupbees`; verify by:
   ```bash
   git log --oneline $(git describe --tags --abbrev=0)..HEAD
   ```
4. **PR labels are applied**. The release-notes generator groups by label per `.github/release.yml`. PRs without a primary category label land in "Other changes" — usually a smell. Backfill labels post-merge if missed:
   ```bash
   gh pr edit <n> --add-label "<label>"
   ```
5. **Pre-release first for risky changes**. Tag `vX.Y.Z-rc1` to exercise the apply in CI before the canonical `vX.Y.Z`. Especially for: new state-bucket layouts, new IAM models, breaking module-input changes.

## Creating the tag

Annotated tag with HEREDOC message (so the tag itself carries context even when read with `git show v1.2.0`):

```bash
git tag -a v1.2.0 -m "$(cat <<'EOF'
v1.2.0

Headline: <one-sentence summary of the release>

(Full release notes are auto-generated on GitHub from PRs merged
since the previous tag, grouped by label per .github/release.yml.)
EOF
)"
```

Push the tag — this is the apply trigger:

```bash
git push origin v1.2.0
```

`git push --tags` also works, but explicit single-tag pushes avoid accidentally pushing unrelated local tags.

## Post-tag verification

After pushing, watch CI:

1. **`apply` job**: runs against the env(s) in scope. If your GitHub plan supports *deployment protection rules* (Pro/Team/Enterprise on private repos, or any plan on public), the `prd` GitHub Environment gates apply behind required reviewers — approve only after the plan output looks right. On **GitHub Free for private repos** (the common case here), required reviewers are unavailable; the **RC tag is the gate** — see *Pre-release first* in the pre-tag checklist: push `vX.Y.Z-rc1`, watch it apply, then push the canonical `vX.Y.Z`.
2. **`release` job**: runs only after `apply` succeeds AND the trigger is a tag push (the workflow's `if:` condition). Creates the GitHub Release via `softprops/action-gh-release@v2` with notes auto-generated from PRs since the previous tag.

Check:
- **Actions tab** → both jobs green.
- **Releases page** (`https://github.com/groupbees/<repo>/releases`) → new Release object with notes categorized per `.github/release.yml` (Foundation / Networking / IAM / Factory / Modules / Fixes / Docs).

If `apply` fails partway: the tag remains in the repo, but the Release is not created. Fix the root cause, then tag a new patch version (`v1.2.1`). See "Rollback".

## Rollback / re-tagging

- **Caught before CI starts** (< 30s window): `git tag -d v1.2.0 && git push --delete origin v1.2.0`. Only safe if the `apply` job hasn't started.
- **Caught after `apply` began** (any partial state on GCP): **do not delete the tag**. Tag `v1.2.1` (or `vX.Y+1.0`) with the corrective change. The original tag stands as a record of what happened.
- **Never `git push --force` to a tag**. Breaks the release-notes diff (softprops compares against the previous tag's *commit*, and moving a tag desynchronizes that) and confuses GitHub's release UI.

## Listing prior tags

```bash
# Latest tags sorted by version (highest first)
git fetch --tags
git tag -l 'v*' --sort=-version:refname | head -10

# What's gone in since the last tag — useful to draft the headline
git log --oneline $(git describe --tags --abbrev=0)..HEAD

# Compare scope of two tags
git diff --stat v1.1.0..v1.2.0
```

## What to avoid

- ❌ **Lightweight tags** (`git tag v1.2.0` without `-a`). Lose the message + author metadata. Always annotated.
- ❌ **Missing `v` prefix** (`1.2.0` instead of `v1.2.0`). The workflow filter is `tags: ["v*"]` — non-`v` tags don't trigger apply.
- ❌ **Tagging from a feature branch**. Always tag from `main` after PR merge. The CI applies whatever the tagged commit is; tagging off `feature/...` deploys non-reviewed code.
- ❌ **Force-moving an existing tag** (`git push --force origin v1.2.0` after a `git tag -f`). Breaks the release-notes diff and confuses the Release object.
- ❌ **Tagging without checking CI status** of the commit being tagged. If `main` was red, `apply` will fail and the Release won't generate — but the tag remains, creating "did v1.2.0 actually ship?" confusion.
- ❌ **Skipping the pre-release** for risky changes. Tag `-rc1` first for new state-bucket layouts, IAM model shifts, breaking module inputs.
- ❌ **Bundling unrelated work into one tag** because "it's been a while since the last release". If `main` has two unrelated drift-fixes + a feature, the release notes will be incoherent. Tag more often, smaller.
