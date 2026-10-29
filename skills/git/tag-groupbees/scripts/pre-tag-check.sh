#!/usr/bin/env bash
#
# pre-tag-check.sh — The pre-tag checklist, automated. Read-only: it never
# tags, pushes or edits anything.
#
# Usage:
#   scripts/pre-tag-check.sh vX.Y.Z[-rcN]
#
# Fails when: the tag is malformed or already exists, HEAD is not main, the
# tree is dirty, main is not origin/main, or CI is not green on HEAD. Then it
# prints the commits and the unlabeled PRs since the previous tag.

set -euo pipefail

die() { echo "❌ $*" >&2; exit 1; }

TAG="${1:-}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(rc|alpha|beta)[0-9]+)?$ ]] \
  || die "usage: $0 vX.Y.Z[-rcN|-alphaN|-betaN]"

GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" \
  git fetch --quiet --tags origin || die "git fetch origin failed"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "$TAG already exists"
[[ "$(git branch --show-current)" == main ]] || die "not on main"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "uncommitted changes"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || die "main differs from origin/main: git pull --ff-only"

HEAD_SHA="$(git rev-parse HEAD)"
runs="$(gh run list --commit "$HEAD_SHA" --json name,status,conclusion \
  --jq '.[] | "\(.name)|\(.status)|\(.conclusion)"')"
[[ -n "$runs" ]] || die "no CI run on ${HEAD_SHA:0:7}"
while IFS='|' read -r name status conclusion; do
  [[ "$status" == completed ]] || die "CI '$name' still $status on ${HEAD_SHA:0:7}"
  [[ "$conclusion" == success || "$conclusion" == skipped ]] \
    || die "CI '$name' is $conclusion on ${HEAD_SHA:0:7}"
done <<< "$runs"
echo "✅ main is clean, in sync and green at ${HEAD_SHA:0:7}"

if prev="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null)"; then
  echo
  echo "Commits since $prev:"
  git log --oneline "$prev..HEAD"
  since="$(git log -1 --format=%cI "$prev")"
  unlabeled="$(gh pr list --state merged --base main --search "merged:>$since" \
    --json number,title,labels --jq '.[] | select(.labels | length == 0) | "#\(.number) \(.title)"')"
  if [[ -n "$unlabeled" ]]; then
    echo
    echo "⚠️  Merged PRs without a label (they land in \"Other changes\"):"
    echo "$unlabeled"
  fi
else
  echo "First tag of the repo."
fi
