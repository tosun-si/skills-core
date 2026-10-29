#!/usr/bin/env bash
#
# skills-catalog.sh — Catalog tooling for a GroupBees skills module.
#
# Installing skills is pollen's job, in the consumer's pollen.yaml; this
# script only reads the catalog: it lists the skills, keeps the README table in
# sync with the SKILL.md descriptions, and guards leaf-name uniqueness (skills
# deploy flat, so skills/<domain>/<name> must be unique on <name> alone).
#
# Usage:
#   scripts/skills-catalog.sh --list          # every skill: name + description
#   scripts/skills-catalog.sh --readme        # regenerate the README skills table
#   scripts/skills-catalog.sh --check-readme  # CI: fail if the README table is stale
#   scripts/skills-catalog.sh --check-names   # CI: fail on a duplicate leaf name

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="${SKILLS_CATALOG_DIR:-$(dirname "$SCRIPT_DIR")}"
SKILLS_SRC="$CATALOG_DIR/skills"

MODE="${1:-}"
case "$MODE" in
  -l|--list|--readme|--check-readme|--check-names) ;;
  *) echo "Usage: $0 --list | --readme | --check-readme | --check-names" >&2; exit 2 ;;
esac

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "❌ Catalog skills dir not found: $SKILLS_SRC" >&2
  exit 1
fi

# Print the `description:` value of a SKILL.md (single line, quotes stripped).
skill_desc() {
  awk '/^description:/{sub(/^description:[[:space:]]*/,"");print;exit}' "$1" \
    | sed -e 's/^"//' -e 's/"$//'
}

# Map a domain folder name to its display label for the README table.
display_domain() {
  case "$1" in
    gcp)  echo "GCP" ;;
    cicd) echo "CI/CD" ;;
    dbt)  echo "dbt" ;;
    *)    echo "$(tr '[:lower:]' '[:upper:]' <<< "${1:0:1}")${1:1}" ;;
  esac
}

# Generate the Markdown skills table (grouped by domain, straight from SKILL.md).
gen_table() {
  echo "| Domain | Skill | Description |"
  echo "|--------|-------|-------------|"
  local domain_dir domain disp sm sdir name desc rel found
  for domain_dir in "$SKILLS_SRC"/*/; do
    [[ -d "$domain_dir" ]] || continue
    domain="$(basename "$domain_dir")"
    disp="$(display_domain "$domain")"
    found=0
    while IFS= read -r -d '' sm; do
      found=1
      sdir="$(dirname "$sm")"; name="$(basename "$sdir")"
      desc="$(skill_desc "$sm")"; desc="${desc//|/\\|}"   # escape pipes for the table
      rel="skills/$domain/$name/"
      printf '| %s | [%s](%s) | %s |\n' "$disp" "$name" "$rel" "$desc"
    done < <(find "$domain_dir" -mindepth 2 -maxdepth 2 -name SKILL.md -print0 | sort -z)
    [[ $found -eq 0 ]] && printf '| %s | _coming soon_ | — |\n' "$disp"
  done
}

# Print the full README with the skills table (between markers) regenerated.
# CR is stripped from every line so the check below is line-ending-agnostic.
render_readme() {
  local tf; tf="$(mktemp)"; gen_table > "$tf"
  awk -v tf="$tf" '
    { sub(/\r$/, "") }
    /<!-- BEGIN skills-table/ { print; while ((getline l < tf) > 0) { sub(/\r$/,"",l); print l } close(tf); skip=1; next }
    /<!-- END skills-table/   { skip=0; print; next }
    !skip { print }
  ' "$CATALOG_DIR/README.md"
  rm -f "$tf"
}

case "$MODE" in
  -l|--list)
    while IFS= read -r -d '' sm; do
      printf '  %-30s %s\n' "$(basename "$(dirname "$sm")")" "$(skill_desc "$sm")"
    done < <(find "$SKILLS_SRC" -type f -name SKILL.md -print0 | sort -z)
    ;;
  --readme)
    render_readme > "$CATALOG_DIR/README.md.tmp" && mv "$CATALOG_DIR/README.md.tmp" "$CATALOG_DIR/README.md"
    echo "✅ README skills table regenerated."
    ;;
  --check-readme)
    if diff -q <(render_readme) <(tr -d '\r' < "$CATALOG_DIR/README.md") >/dev/null; then
      echo "✅ README skills table is up to date."
      exit 0
    fi
    echo "❌ README skills table is STALE. Run: scripts/skills-catalog.sh --readme" >&2
    diff -u <(tr -d '\r' < "$CATALOG_DIR/README.md") <(render_readme) >&2 || true
    exit 1
    ;;
  --check-names)
    # skills/<domain>/<name>/SKILL.md → <name> is the second-to-last field.
    dups="$(find "$SKILLS_SRC" -type f -name SKILL.md \
      | awk -F/ '{ print $(NF-1) }' | sort | uniq -d)"
    if [[ -n "$dups" ]]; then
      echo "❌ Leaf skill names must be unique across domains (they deploy flat):" >&2
      while IFS= read -r d; do echo "   $d" >&2; done <<< "$dups"
      exit 1
    fi
    echo "✅ Every skill name is unique."
    ;;
esac
