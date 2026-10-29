---
name: commit-groupbees
description: Commit message conventions for GroupBees repos (github.com/groupbees/*). Trigger when creating a git commit in a GroupBees repository — any repo whose path or remote URL contains "groupbees". Covers descriptive titles, HEREDOC for multi-line bodies, and the rule that NO Co-Authored-By trailer is added even on AI-assisted commits. Do NOT trigger for non-GroupBees personal or other-org work.
---

# GroupBees commit conventions

Descriptive, declarative commits — not Conventional Commits. Multi-clause titles are fine when they help readers understand the scope at a glance.

## Title

- **Style**: descriptive sentence in present tense or imperative mood. Free-form, not `feat:` / `fix:` prefixed.
- **Length**: ≤ 80 chars when possible. Up to 100 if the scope genuinely needs it; truncate to body otherwise.
- **Multi-clause OK** when the change touches multiple related concerns. Example: `Add PSA to factory VPCs + per-app TF state buckets + Cloud SQL APIs`.
- **Spell-check**: avoid common typos (`bootstrap` not `boostrap`, etc.).

## Body (optional)

- Use when the change merits explanation beyond the title — bullet list of what changed, with brief rationale where non-obvious.
- Wrap at ~72 chars.
- Reference issue/PR numbers if relevant.

## No Co-Authored-By trailer

Do NOT append a `Co-Authored-By: Claude ...` line to commits, even when AI-assisted.
Attribution lives in the PR description / review history, not in commit metadata.

## HEREDOC for multi-line messages

To preserve formatting in shell, always use HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
Add PSA to the shared VPCs + per-app TF state buckets

- Private Services Access on <org>-net-{dev,prd} (one /20 range per env)
- Per-app state buckets: <org>-<app>-{dev,prd}-tfstate
- Cloud SQL APIs (sqladmin, servicenetworking) pre-enabled on the app projects
EOF
)"
```

## What to avoid

- ❌ Conventional Commits prefixes (`feat:`, `fix:`, `chore:`) — not used in this org.
- ❌ Generic titles like `Update config` or `Fix bug` — be specific.
- ❌ Titles over 100 chars — move detail to the body.
- ❌ `--amend` of pushed commits without explicit user request — always prefer new commits.
- ❌ Bypassing hooks (`--no-verify`) or signing (`--no-gpg-sign`) unless explicitly requested.
