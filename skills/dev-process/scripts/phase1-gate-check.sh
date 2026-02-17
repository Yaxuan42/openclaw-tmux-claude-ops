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

# Helper: add check result
add_check() {
  local name="$1" ok="$2" detail="$3"
  checks+=("$(jq -n --arg name "$name" --argjson ok "$ok" --arg detail "$detail" \
    '{name: $name, ok: $ok, detail: $detail}')")
  if [[ "$ok" == "false" ]]; then
    all_ok=false
  fi
}

# Check 1: MRD.md exists and has content
MRD="$PROJECT_DIR/docs/MRD.md"
if [[ ! -f "$MRD" ]]; then
  add_check "mrd_exists" false "MRD.md not found"
else
  # Check if it has content beyond template placeholders
  line_count=$(wc -l < "$MRD" | tr -d ' ')
  if rg -q "Market Problem" "$MRD" 2>/dev/null && [[ "$line_count" -gt 10 ]]; then
    # Check if Market Problem section has actual content (not just comment)
    if rg -A2 "## Market Problem" "$MRD" 2>/dev/null | rg -qv "^(#|$|<!--)" 2>/dev/null; then
      add_check "mrd_exists" true "MRD.md exists with content ($line_count lines)"
    else
      add_check "mrd_exists" false "MRD.md exists but Market Problem section is empty"
    fi
  else
    add_check "mrd_exists" false "MRD.md exists but appears to be unfilled template"
  fi
fi

# Check 2: PRD.md exists
PRD="$PROJECT_DIR/docs/PRD.md"
if [[ ! -f "$PRD" ]]; then
  add_check "prd_exists" false "PRD.md not found"
else
  add_check "prd_exists" true "PRD.md exists"
fi

# Check 3: PRD has User Stories
if [[ -f "$PRD" ]]; then
  if rg -q "User Stories" "$PRD" 2>/dev/null && rg -q "US-" "$PRD" 2>/dev/null; then
    story_count=$(rg -c "US-[0-9]" "$PRD" 2>/dev/null || echo "0")
    add_check "prd_user_stories" true "PRD contains User Stories ($story_count entries)"
  else
    add_check "prd_user_stories" false "PRD missing User Stories (need US-xxx entries)"
  fi
else
  add_check "prd_user_stories" false "PRD.md not found"
fi

# Check 4: PRD has Scope
if [[ -f "$PRD" ]]; then
  if rg -q "## Scope" "$PRD" 2>/dev/null && rg -q "In Scope" "$PRD" 2>/dev/null; then
    if rg -A2 "### In Scope" "$PRD" 2>/dev/null | rg -qv "^(#|$|-$)" 2>/dev/null; then
      add_check "prd_scope" true "PRD contains Scope section with content"
    else
      add_check "prd_scope" false "PRD Scope section is empty"
    fi
  else
    add_check "prd_scope" false "PRD missing Scope section"
  fi
else
  add_check "prd_scope" false "PRD.md not found"
fi

# Check 5: PRD has Success Criteria
if [[ -f "$PRD" ]]; then
  if rg -q "Success Criteria" "$PRD" 2>/dev/null; then
    if rg -A3 "## Success Criteria" "$PRD" 2>/dev/null | rg -q "\[.\]" 2>/dev/null; then
      add_check "prd_success_criteria" true "PRD contains Success Criteria"
    else
      add_check "prd_success_criteria" false "PRD Success Criteria section has no checkable items"
    fi
  else
    add_check "prd_success_criteria" false "PRD missing Success Criteria section"
  fi
else
  add_check "prd_success_criteria" false "PRD.md not found"
fi

# Build checks array
checks_json="["
for i in "${!checks[@]}"; do
  if [[ $i -gt 0 ]]; then checks_json+=","; fi
  checks_json+="${checks[$i]}"
done
checks_json+="]"

# Output JSON
jq -n \
  --arg gate "phase1" \
  --argjson passed "$all_ok" \
  --argjson checks "$checks_json" \
  --argjson humanApprovalRequired true \
  '{gate: $gate, passed: $passed, checks: $checks, humanApprovalRequired: $humanApprovalRequired}'

if [[ "$all_ok" == true ]]; then
  exit 0
else
  exit 1
fi
