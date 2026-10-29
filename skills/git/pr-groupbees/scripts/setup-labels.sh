#!/usr/bin/env bash
#
# setup-labels.sh — Create the release-note labels with the GroupBees colors.
#
# Idempotent (gh label create --force updates color and description), so it is
# safe to re-run. Run it from the repo, or pass --repo OWNER/NAME through.
#
# Usage:
#   scripts/setup-labels.sh [--repo groupbees/<repo>] [app-label ...]
#
# Each extra argument is an app label (yellow, "Factory apps" section).

set -euo pipefail

REPO_ARGS=()
if [[ "${1:-}" == --repo ]]; then
  REPO_ARGS=(--repo "$2")
  shift 2
fi

# label|color|description
LABELS=(
  "foundation|0E8A16|Foundation changes"
  "bootstrap|0E8A16|Bootstrap changes"
  "infra|0E8A16|Infrastructure changes"
  "network|1D76DB|Networking changes"
  "vpc|1D76DB|VPC changes"
  "psa|1D76DB|Private service access changes"
  "iam|B60205|IAM changes"
  "security|B60205|Security changes"
  "wif|B60205|Workload Identity Federation changes"
  "breaking-change|B60205|Breaking change"
  "factory|FBCA04|Factory apps"
  "modules|5319E7|Terraform modules"
  "shared-module|5319E7|Shared Terraform module"
  "fix|D93F0B|Bug fix"
  "docs|C5DEF5|Documentation"
  "skip-changelog|EEEEEE|Excluded from release notes"
  "dependencies|EEEEEE|Dependency updates (excluded from release notes)"
)
for app in "$@"; do
  LABELS+=("$app|FBCA04|Factory app: $app")
done

for entry in "${LABELS[@]}"; do
  IFS='|' read -r name color desc <<< "$entry"
  gh label create "$name" --color "$color" --description "$desc" --force "${REPO_ARGS[@]}"
done
echo "✅ ${#LABELS[@]} labels in place"
