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

# Check 1: DESIGN.md exists
DESIGN="$PROJECT_DIR/docs/DESIGN.md"
if [[ ! -f "$DESIGN" ]]; then
  add_check "design_exists" false "DESIGN.md not found"
else
  add_check "design_exists" true "DESIGN.md exists"
fi

# Check 2: DESIGN.md has Architecture section with content
if [[ -f "$DESIGN" ]]; then
  if rg -q "## Architecture" "$DESIGN" 2>/dev/null; then
    if rg -A5 "## Architecture" "$DESIGN" 2>/dev/null | rg -qv "^(#|$|<!--|-->)" 2>/dev/null; then
      add_check "design_architecture" true "DESIGN.md contains Architecture section"
    else
      add_check "design_architecture" false "Architecture section is empty"
    fi
  else
    add_check "design_architecture" false "DESIGN.md missing Architecture section"
  fi
else
  add_check "design_architecture" false "DESIGN.md not found"
fi

# Check 3: DESIGN.md has Data Model section
if [[ -f "$DESIGN" ]]; then
  if rg -q "## Data Model" "$DESIGN" 2>/dev/null; then
    add_check "design_data_model" true "DESIGN.md contains Data Model section"
  else
    add_check "design_data_model" false "DESIGN.md missing Data Model section"
  fi
else
  add_check "design_data_model" false "DESIGN.md not found"
fi

# Check 4: TEST_PLAN.md exists
TEST_PLAN="$PROJECT_DIR/docs/TEST_PLAN.md"
if [[ ! -f "$TEST_PLAN" ]]; then
  add_check "test_plan_exists" false "TEST_PLAN.md not found"
else
  add_check "test_plan_exists" true "TEST_PLAN.md exists"
fi

# Check 5: TEST_PLAN.md has Test Cases
if [[ -f "$TEST_PLAN" ]]; then
  if rg -q "## Test Cases" "$TEST_PLAN" 2>/dev/null && rg -q "TC-" "$TEST_PLAN" 2>/dev/null; then
    tc_count=$(rg -c "TC-[0-9]" "$TEST_PLAN" 2>/dev/null || echo "0")
    add_check "test_plan_cases" true "TEST_PLAN.md contains test cases ($tc_count entries)"
  else
    add_check "test_plan_cases" false "TEST_PLAN.md missing test cases (need TC-xxx entries)"
  fi
else
  add_check "test_plan_cases" false "TEST_PLAN.md not found"
fi

# Check 6: TEST_PLAN.md has Coverage Targets
if [[ -f "$TEST_PLAN" ]]; then
  if rg -q "Coverage Targets" "$TEST_PLAN" 2>/dev/null; then
    add_check "test_plan_coverage" true "TEST_PLAN.md contains Coverage Targets"
  else
    add_check "test_plan_coverage" false "TEST_PLAN.md missing Coverage Targets"
  fi
else
  add_check "test_plan_coverage" false "TEST_PLAN.md not found"
fi

# Check 7: API_CONTRACT.md (web projects only)
# Detect web project by checking if API_CONTRACT.md exists or STATUS.md says web
STATUS="$PROJECT_DIR/docs/STATUS.md"
is_web=false
if [[ -f "$STATUS" ]] && rg -q "web" "$STATUS" 2>/dev/null; then
  is_web=true
fi
if [[ -f "$PROJECT_DIR/docs/API_CONTRACT.md" ]]; then
  is_web=true
fi

if [[ "$is_web" == true ]]; then
  API_CONTRACT="$PROJECT_DIR/docs/API_CONTRACT.md"
  if [[ -f "$API_CONTRACT" ]]; then
    if rg -q "## Endpoints" "$API_CONTRACT" 2>/dev/null; then
      add_check "api_contract" true "API_CONTRACT.md contains Endpoints"
    else
      add_check "api_contract" false "API_CONTRACT.md missing Endpoints section"
    fi
  else
    add_check "api_contract" false "API_CONTRACT.md not found (web project)"
  fi
fi

# Build checks array
checks_json="["
for i in "${!checks[@]}"; do
  if [[ $i -gt 0 ]]; then checks_json+=","; fi
  checks_json+="${checks[$i]}"
done
checks_json+="]"

jq -n \
  --arg gate "phase2" \
  --argjson passed "$all_ok" \
  --argjson checks "$checks_json" \
  --argjson humanApprovalRequired true \
  '{gate: $gate, passed: $passed, checks: $checks, humanApprovalRequired: $humanApprovalRequired}'

if [[ "$all_ok" == true ]]; then
  exit 0
else
  exit 1
fi
