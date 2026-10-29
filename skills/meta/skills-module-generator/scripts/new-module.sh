#!/usr/bin/env bash
#
# new-module.sh — Scaffold a skills module from skills-core.
#
# Copies the invariant files verbatim from skills-core, renders the templates
# in ../assets, creates the first skill stub, and fills the README
# table. Publishing (gh repo create) stays a separate, deliberate step.
#
# Inputs (environment variables):
#   MODULE_NAME          required  skills-<name>, e.g. skills-data
#   MODULE_DESCRIPTION   required  one line for the README
#   MODULE_PURPOSE       required  1–2 sentences for AGENTS.md "What this repo is"
#   FIRST_SKILL          required  <domain>/<name>, e.g. data/dbt-conventions
#   VISIBILITY           optional  private (default) | public
#   GITHUB_OWNER         optional  groupbees (default), or a personal account / other org
#   DOMAINS              optional  Markdown list of domains, default: `<domain>`
#   SKILLS_CORE_DIR      optional  default ~/my-projects/groupbees/skills/skills-core
#   SKILLS_ROOT          optional  where the module is created, default: next to skills-core
#
# Example:
#   MODULE_NAME=skills-data MODULE_DESCRIPTION="Data engineering conventions" \
#   MODULE_PURPOSE="The source of truth for GroupBees' data engineering conventions." \
#   FIRST_SKILL=data/dbt-conventions ./new-module.sh

set -euo pipefail

die() { echo "❌ $*" >&2; exit 1; }

: "${MODULE_NAME:?MODULE_NAME is required}"
: "${MODULE_DESCRIPTION:?MODULE_DESCRIPTION is required}"
: "${MODULE_PURPOSE:?MODULE_PURPOSE is required}"
: "${FIRST_SKILL:?FIRST_SKILL (<domain>/<name>) is required}"

ASSETS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd)"
CORE="${SKILLS_CORE_DIR:-$HOME/my-projects/groupbees/skills/skills-core}"
ROOT="${SKILLS_ROOT:-$(dirname "$CORE")}"
DEST="$ROOT/$MODULE_NAME"

[[ "$MODULE_NAME" == skills-* ]] || die "MODULE_NAME must start with skills- (got $MODULE_NAME)"
[[ "$FIRST_SKILL" =~ ^[a-z0-9-]+/[a-z0-9-]+$ ]] || die "FIRST_SKILL must be <domain>/<name> in kebab-case"
[[ -d "$CORE/skills" ]] || die "skills-core not found at $CORE (set SKILLS_CORE_DIR)"
[[ -e "$DEST" ]] && die "$DEST already exists"

VISIBILITY="${VISIBILITY:-private}"
[[ "$VISIBILITY" == private || "$VISIBILITY" == public ]] || die "VISIBILITY must be private or public"
GITHUB_OWNER="${GITHUB_OWNER:-groupbees}"

# Commits and PRs follow the owning org; tags follow what the project is.
if [[ "$GITHUB_OWNER" == groupbees ]]; then
  CATALOG="GroupBees skills catalog"
  COMMIT_SKILL="commit-groupbees"
  PR_RULE="the \`pr-groupbees\` conventions"
  if [[ "$VISIBILITY" == private ]]; then
    RELEASE_SKILL="tag-groupbees"    # internal: tags deploy
  else
    RELEASE_SKILL="tag-opensource"   # open source: tags publish
  fi
else
  CATALOG="$GITHUB_OWNER skills catalog"
  COMMIT_SKILL="commit-open-source"
  PR_RULE="a descriptive title and body"
  RELEASE_SKILL="tag-opensource"
fi

FIRST_DOMAIN="${FIRST_SKILL%%/*}"
FIRST_SKILL_NAME="${FIRST_SKILL#*/}"
DOMAINS="${DOMAINS:-\`$FIRST_DOMAIN\`}"
FIRST_SKILL_TITLE="${FIRST_SKILL_TITLE:-$FIRST_SKILL_NAME}"
FIRST_SKILL_DESCRIPTION="${FIRST_SKILL_DESCRIPTION:-TODO — what the skill does AND when to trigger it.}"
export MODULE_NAME MODULE_DESCRIPTION MODULE_PURPOSE VISIBILITY RELEASE_SKILL DOMAINS \
  GITHUB_OWNER CATALOG COMMIT_SKILL PR_RULE \
  FIRST_SKILL_NAME FIRST_SKILL_TITLE FIRST_SKILL_DESCRIPTION

# Skills deploy flat: the first skill's name must not exist in any sibling
# module, here or next to skills-core (a personal module composes with those).
# <module>/skills/<domain>/<name>/SKILL.md sits five levels below the root.
clash="$(find "$ROOT" "$(dirname "$CORE")" -mindepth 5 -maxdepth 5 \
  -path "*/skills/*/$FIRST_SKILL_NAME/SKILL.md" 2>/dev/null | head -1)"
[[ -z "$clash" ]] || die "skill name '$FIRST_SKILL_NAME' already exists: $clash"

# {{VAR}} → $VAR, taken from the environment (perl: safe with / & | in values).
render() { perl -pe 's/\{\{(\w+)\}\}/exists $ENV{$1} ? $ENV{$1} : $&/ge' "$1" > "$2"; }

mkdir -p "$DEST/scripts" "$DEST/.github/workflows" "$DEST/skills/$FIRST_SKILL"
cd "$DEST"
git init --quiet -b main

# Invariant files: byte-identical in every module, never edited per module.
cp "$CORE/.gitignore" "$CORE/.gitattributes" "$CORE/CLAUDE.md" .
cp "$CORE/scripts/skills-catalog.sh" scripts/
cp "$CORE/.github/workflows/ci.yml" .github/workflows/
cp "$CORE/.github/dependabot.yml" .github/

# Per-module files.
render "$ASSETS/README.md.template" README.md
render "$ASSETS/AGENTS.md.template" AGENTS.md
render "$ASSETS/CONTRIBUTING.md.template" CONTRIBUTING.md
render "$ASSETS/SKILL.md.template" "skills/$FIRST_SKILL/SKILL.md"

left="$(grep -rl '{{[A-Z_]*}}' . --exclude-dir=.git || true)"
[[ -z "$left" ]] || die "unrendered placeholders in: $left"

chmod +x scripts/skills-catalog.sh
scripts/skills-catalog.sh --readme >/dev/null

echo "✅ $MODULE_NAME scaffolded in $DEST ($GITHUB_OWNER, $VISIBILITY, released with $RELEASE_SKILL)"
echo "   Next: write skills/$FIRST_SKILL/SKILL.md, then run the checks."
