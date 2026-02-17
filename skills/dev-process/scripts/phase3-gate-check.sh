#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=""
ITERATION=""
LINT_CMD=""
BUILD_CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --iteration) ITERATION="$2"; shift 2 ;;
    --lint-cmd) LINT_CMD="$2"; shift 2 ;;
    --build-cmd) BUILD_CMD="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$PROJECT_DIR" ]] || {
  echo "Usage: $0 --project-dir <dir> [--iteration <N>] [--lint-cmd '...'] [--build-cmd '...']"
  exit 1
}

ITERATION="${ITERATION:-0}"

checks=()
all_ok=true
spec_change_detected=false

add_check() {
  local name="$1" ok="$2" detail="$3"
  checks+=("$(jq -n --arg name "$name" --argjson ok "$ok" --arg detail "$detail" \
    '{name: $name, ok: $ok, detail: $detail}')")
  if [[ "$ok" == "false" ]]; then all_ok=false; fi
}

# Check 1: Tests pass
if [[ -f "$PROJECT_DIR/package.json" ]]; then
  # Node.js project
  if cd "$PROJECT_DIR" && npm test 2>&1 | tail -5 > /tmp/dp-test-output.txt 2>&1; then
    test_summary=$(cat /tmp/dp-test-output.txt | tail -1)
    add_check "tests_pass" true "Tests passed: $test_summary"
  else
    test_summary=$(cat /tmp/dp-test-output.txt | tail -3 | tr '\n' ' ')
    add_check "tests_pass" false "Tests failed: $test_summary"
  fi
elif [[ -f "$PROJECT_DIR/pytest.ini" || -f "$PROJECT_DIR/setup.py" || -f "$PROJECT_DIR/pyproject.toml" ]]; then
  # Python project
  if cd "$PROJECT_DIR" && python3 -m pytest --tb=short 2>&1 | tail -5 > /tmp/dp-test-output.txt 2>&1; then
    test_summary=$(cat /tmp/dp-test-output.txt | tail -1)
    add_check "tests_pass" true "Tests passed: $test_summary"
  else
    test_summary=$(cat /tmp/dp-test-output.txt | tail -3 | tr '\n' ' ')
    add_check "tests_pass" false "Tests failed: $test_summary"
  fi
elif [[ -d "$PROJECT_DIR/tests" ]]; then
  # Has tests dir but unknown runner
  add_check "tests_pass" false "Tests directory exists but no known test runner found (add --lint-cmd/--build-cmd)"
else
  add_check "tests_pass" true "No test directory found — skipped"
fi

# Check 2: Lint
if [[ -n "$LINT_CMD" ]]; then
  if cd "$PROJECT_DIR" && eval "$LINT_CMD" > /tmp/dp-lint-output.txt 2>&1; then
    add_check "lint" true "Lint passed"
  else
    lint_err=$(head -5 /tmp/dp-lint-output.txt | tr '\n' ' ')
    add_check "lint" false "Lint failed: $lint_err"
  fi
else
  add_check "lint" true "No lint command configured — skipped"
fi

# Check 3: Build
if [[ -n "$BUILD_CMD" ]]; then
  if cd "$PROJECT_DIR" && eval "$BUILD_CMD" > /tmp/dp-build-output.txt 2>&1; then
    add_check "build" true "Build passed"
  else
    build_err=$(head -5 /tmp/dp-build-output.txt | tr '\n' ' ')
    add_check "build" false "Build failed: $build_err"
  fi
else
  add_check "build" true "No build command configured — skipped"
fi

# Check 4: STATUS.md iteration log updated
STATUS="$PROJECT_DIR/docs/STATUS.md"
if [[ -f "$STATUS" ]]; then
  if rg -q "## Iteration Log" "$STATUS" 2>/dev/null; then
    # Check if there's at least one non-placeholder row
    log_rows=$(rg -c "^\| [0-9]" "$STATUS" 2>/dev/null || echo "0")
    if [[ "$log_rows" -gt 0 ]]; then
      add_check "status_updated" true "STATUS.md iteration log has $log_rows entries"
    else
      add_check "status_updated" false "STATUS.md iteration log has no entries"
    fi
  else
    add_check "status_updated" false "STATUS.md missing Iteration Log section"
  fi
else
  add_check "status_updated" false "STATUS.md not found"
fi

# Check 5: Git clean
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

# Check 6: Detect spec changes in CHANGELOG
CHANGELOG="$PROJECT_DIR/docs/CHANGELOG.md"
if [[ -f "$CHANGELOG" ]]; then
  spec_changes=$(rg -c "\[spec-change\]" "$CHANGELOG" 2>/dev/null || echo "0")
  if [[ "$spec_changes" -gt 0 ]]; then
    spec_change_detected=true
    add_check "spec_change" true "Detected $spec_changes spec change(s) in CHANGELOG — notification will be triggered"
  fi
fi

# Build checks array
checks_json="["
for i in "${!checks[@]}"; do
  if [[ $i -gt 0 ]]; then checks_json+=","; fi
  checks_json+="${checks[$i]}"
done
checks_json+="]"

gate_name="phase3"
if [[ -n "$ITERATION" && "$ITERATION" != "0" ]]; then
  gate_name="phase3-iter-${ITERATION}"
fi

jq -n \
  --arg gate "$gate_name" \
  --argjson passed "$all_ok" \
  --argjson checks "$checks_json" \
  --argjson specChangeDetected "$spec_change_detected" \
  --argjson humanApprovalRequired false \
  '{gate: $gate, passed: $passed, checks: $checks, specChangeDetected: $specChangeDetected, humanApprovalRequired: $humanApprovalRequired}'

if [[ "$all_ok" == true ]]; then
  exit 0
else
  exit 1
fi
