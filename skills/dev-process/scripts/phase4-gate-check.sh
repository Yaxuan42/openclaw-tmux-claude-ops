#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$PROJECT_DIR" ]] || {
  echo "Usage: $0 --project-dir <dir>"
  exit 1
}

checks=()
all_ok=true

add_check() {
  local name="$1" ok="$2" detail="$3"
  checks+=("$(jq -n --arg name "$name" --argjson ok "$ok" --arg detail "$detail" \
    '{name: $name, ok: $ok, detail: $detail}')")
  if [[ "$ok" == "false" ]]; then all_ok=false; fi
}

# Check 1: CHANGELOG.md has substantive content
CHANGELOG="$PROJECT_DIR/docs/CHANGELOG.md"
if [[ -f "$CHANGELOG" ]]; then
  # Check for actual entries (lines starting with - followed by text, not just template)
  real_entries=$( (rg "^- .+" "$CHANGELOG" 2>/dev/null | rg -vc "^- $" 2>/dev/null) || echo "0")
  if [[ "$real_entries" -gt 0 ]]; then
    add_check "changelog_content" true "CHANGELOG.md has $real_entries entries"
  else
    add_check "changelog_content" false "CHANGELOG.md has no substantive entries"
  fi
else
  add_check "changelog_content" false "CHANGELOG.md not found"
fi

# Check 2: All required docs exist
required_docs=("STATUS.md" "MRD.md" "PRD.md" "DESIGN.md" "TEST_PLAN.md" "CHANGELOG.md" "LESSONS_LEARNED.md")
missing_docs=()
for doc in "${required_docs[@]}"; do
  if [[ ! -f "$PROJECT_DIR/docs/$doc" ]]; then
    missing_docs+=("$doc")
  fi
done

if [[ ${#missing_docs[@]} -eq 0 ]]; then
  add_check "docs_complete" true "All ${#required_docs[@]} required docs present"
else
  add_check "docs_complete" false "Missing docs: ${missing_docs[*]}"
fi

# Check 3: LESSONS_LEARNED.md has been updated
LESSONS="$PROJECT_DIR/docs/LESSONS_LEARNED.md"
if [[ -f "$LESSONS" ]]; then
  # Check for actual lesson entries (table rows with dates)
  lesson_entries=$(rg -c "^\| [0-9]{4}-" "$LESSONS" 2>/dev/null || echo "0")
  if [[ "$lesson_entries" -gt 0 ]]; then
    add_check "lessons_updated" true "LESSONS_LEARNED.md has $lesson_entries entries"
  else
    add_check "lessons_updated" false "LESSONS_LEARNED.md has no entries — reflect on what you learned"
  fi
else
  add_check "lessons_updated" false "LESSONS_LEARNED.md not found"
fi

# Check 4: Git clean
if cd "$PROJECT_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  dirty_files=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$dirty_files" -eq 0 ]]; then
    add_check "git_clean" true "Working directory is clean"
  else
    add_check "git_clean" false "Working directory has $dirty_files uncommitted changes"
  fi
else
  add_check "git_clean" true "Not a git repository — skipped"
fi

# Build checks array
checks_json="["
for i in "${!checks[@]}"; do
  if [[ $i -gt 0 ]]; then checks_json+=","; fi
  checks_json+="${checks[$i]}"
done
checks_json+="]"

jq -n \
  --arg gate "phase4" \
  --argjson passed "$all_ok" \
  --argjson checks "$checks_json" \
  --argjson humanApprovalRequired false \
  '{gate: $gate, passed: $passed, checks: $checks, humanApprovalRequired: $humanApprovalRequired}'

if [[ "$all_ok" == true ]]; then
  exit 0
else
  exit 1
fi
