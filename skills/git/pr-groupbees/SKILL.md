---
name: pr-groupbees
description: Pull Request title, description, and labeling conventions for GroupBees repos (github.com/groupbees/*). Trigger when creating or updating a PR in a GroupBees repository — any repo whose path or remote URL contains "groupbees". Includes the structured body template, label-driven release-notes categorization, the prerequisite that labels must be created in the repo before they can be applied (with the GroupBees color convention), and the merge strategy (squash by default, rebase-merge for PRs whose commits each stand on their own). Do NOT trigger for non-GroupBees work.
---

# GroupBees PR conventions

PRs in this org use a structured body and label-driven release-note categorization. The PR title becomes a changelog bullet (via `softprops/action-gh-release` + `.github/release.yml`), so write titles that read well as standalone release entries.

## Title

- **Descriptive, declarative**, similar to commit titles. Not Conventional Commits.
- **≤ 80 chars** preferred; up to 100 if scope genuinely needs it.
- **Plural themes allowed**: `Enable Cloud SQL (PSA + APIs), add per-app TF state, automate releases`.
- The title is what shows up in GitHub release notes — write for that audience.

## Body — standard structure

```markdown
## Summary

<3–5 bullet themes, each one clause. Highlight the WHY when not obvious.>

## What changed (optional)

<Only for large PRs. Break into sections by concern (e.g. ### Networking, ### State).>
<Each section: bullet list of files / behaviors.>

## Test plan

- [x] <validation step you ran locally or in CI>
- [x] <another>
- [ ] <follow-up validation expected after merge, if any>
```

Skip "What changed" entirely for small PRs — go straight from Summary to Test plan.

## Labels for release-notes categorization

Apply ONE primary type label per PR. The release-notes generator uses the first matching label to place the PR in a section. From `.github/release.yml`:

| Label | Section |
|---|---|
| `foundation`, `bootstrap`, `infra` | 🚀 Foundation changes |
| `network`, `vpc`, `psa` | 🌐 Networking |
| `iam`, `security`, `wif` | 🔐 IAM & identity |
| `factory`, one label per app (`<app-name>`) | 🏭 Factory apps |
| `modules`, `shared-module` | 📦 Modules |
| `fix`, `bug` | 🐛 Fixes |
| `docs`, `documentation` | 📝 Documentation |
| (no label) | Other changes |
| `skip-changelog`, `dependencies` | ❌ excluded from release notes |

Cross-cutting labels (`breaking-change`, `good-first-issue`, etc.) are fine in addition — they don't affect grouping, just searchability.

### Prerequisite: labels must pre-exist in the repo

`gh pr edit <n> --add-label "foo"` fails with `'foo' not found` if the label hasn't been created yet: new repos only ship GitHub's defaults. Once per repo, before the first labeled PR:

1. Copy [`assets/release.yml`](assets/release.yml) to `.github/release.yml` and drop the categories the repo doesn't use.
2. Run [`scripts/setup-labels.sh`](scripts/setup-labels.sh) `[--repo groupbees/<repo>] [<app-label> ...]` — it creates every label with the GroupBees colors and is idempotent.

GroupBees color convention (consistent across repos, encoded in the script):

| Hue | Hex | Used for |
|---|---|---|
| Green | `0E8A16` | `foundation`, `bootstrap`, `infra` |
| Blue | `1D76DB` | `network`, `vpc`, `psa` |
| Red | `B60205` | `iam`, `security`, `wif`, `breaking-change` |
| Yellow | `FBCA04` | `factory`, app labels (`<app-name>`) |
| Purple | `5319E7` | `modules`, `shared-module` |
| Orange | `D93F0B` | `fix` |
| Light blue | `C5DEF5` | `docs` |
| Grey | `EEEEEE` | `skip-changelog`, `dependencies` (excluded from notes) |

## `gh pr create` invocation

```bash
gh pr create --title "<descriptive title>" --body "$(cat <<'EOF'
## Summary

- <theme 1>
- <theme 2>

## Test plan

- [x] <test done>
- [ ] <test to do post-merge>
EOF
)"
```

Use HEREDOC to preserve markdown formatting. Don't escape special characters in the body — HEREDOC handles them.

## Merge strategy

Both keep `main` linear; the author picks one per PR from the merge button.

- **Squash-merge — the default.** One PR → one commit on `main`, titled after the PR. Use it whenever the branch holds work-in-progress commits (`fix typo`, `address review`), or when one commit says it all.
- **Rebase-merge — when the commits are worth keeping.** Each commit lands on `main` as is, so use it only when every commit is one logical step with a descriptive title (`commit-groupbees`) and leaves the build green — `git bisect` and `git revert` then work per step. Clean the branch up (`git rebase -i` locally) before merging, never after.
- **Merge commits — never.** They break the linear history.
- Release notes are generated from the merged **PRs** (title + labels), so both strategies produce the same changelog entry.
- Repo settings this assumes: *Allow squash merging* and *Allow rebase merging* on, *Allow merge commits* off.
- When unsure which to suggest, suggest squash; leave the final call to the author.

## What to avoid

- ❌ Conventional Commits prefixes in PR titles.
- ❌ PR descriptions with no Summary section — release notes will lack context.
- ❌ Multiple primary type labels (creates ambiguity in the changelog category).
- ❌ Force-push to a PR branch with reviewers attached (without warning them).
- ❌ Rebase-merging a branch that still has WIP or review-fix commits — squash it, or tidy it first.
- ❌ Merging without the auto-generated CI plan being green (or explicitly acknowledged as expected to fail, with reason in the PR comments).

## Example PR bodies

**Small PR**:
```markdown
## Summary

- Drop a stale personal binding (`<user>@`) from `sa-tf-foundation` once the `gcp-foundation-admins@` group membership was confirmed.

## Test plan

- [x] Verified group binding works via local `terragrunt plan` after removal
```

**Larger PR** (multiple themes):
```markdown
## Summary

Four changes that unblock the app IaC (Cloud Run + Cloud SQL on the Shared VPC):

1. **PSA on both VPCs** — Cloud SQL / Memorystore can allocate private IPs in `<org>-net-{dev,prd}`.
2. **Per-app TF state buckets** — `gs://<org>-<app>-{dev,prd}-tfstate`.
3. **Cloud SQL APIs** (`sqladmin`, `servicenetworking`) pre-enabled on every app project.
4. **Auto GitHub Releases** on tag push via `softprops/action-gh-release@v2`.

## Test plan

- [x] Applied locally — PSA peering on both VPCs, 4 state buckets, 8 APIs enabled
- [x] YAML validated for `iac.yml` and `.github/release.yml`
- [ ] First tagged release (`v0.1.0`) post-merge to validate the release job
```
