#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=""
FORCE=false
LINT_CMD=""
BUILD_CMD=""
ITERATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    --lint-cmd) LINT_CMD="$2"; shift 2 ;;
    --build-cmd) BUILD_CMD="$2"; shift 2 ;;
    --iteration) ITERATION="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$PROJECT_DIR" ]] || {
  echo "Usage: $0 --project-dir <dir> [--force] [--lint-cmd '...'] [--build-cmd '...'] [--iteration <N>]"
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS="$PROJECT_DIR/docs/STATUS.md"

if [[ ! -f "$STATUS" ]]; then
  echo "ERROR: $STATUS not found"
  exit 1
fi

# Determine current phase from STATUS.md
current_phase=$(rg "^\\*\\*Phase [0-9]" "$STATUS" 2>/dev/null | head -1 | sed 's/.*Phase \([0-9]\).*/\1/' || echo "")

if [[ -z "$current_phase" ]]; then
  echo "ERROR: Cannot determine current phase from STATUS.md"
  echo "Expected a line like: **Phase 1: 需求分析** ⬅️ 当前阶段"
  exit 1
fi

echo "Current phase: $current_phase"

# Run the gate check for the current phase
GATE_ARGS=(--project-dir "$PROJECT_DIR")

case "$current_phase" in
  1) GATE_SCRIPT="$SCRIPT_DIR/phase1-gate-check.sh" ;;
  2) GATE_SCRIPT="$SCRIPT_DIR/phase2-gate-check.sh" ;;
  3)
    GATE_SCRIPT="$SCRIPT_DIR/phase3-gate-check.sh"
    if [[ -n "$LINT_CMD" ]]; then GATE_ARGS+=(--lint-cmd "$LINT_CMD"); fi
    if [[ -n "$BUILD_CMD" ]]; then GATE_ARGS+=(--build-cmd "$BUILD_CMD"); fi
    if [[ -n "$ITERATION" ]]; then GATE_ARGS+=(--iteration "$ITERATION"); fi
    ;;
  4) GATE_SCRIPT="$SCRIPT_DIR/phase4-gate-check.sh" ;;
  *)
    echo "ERROR: Unknown phase: $current_phase"
    exit 1
    ;;
esac

echo "Running gate check: $(basename "$GATE_SCRIPT")"
echo ""

gate_output=""
gate_passed=false

if gate_output=$(bash "$GATE_SCRIPT" "${GATE_ARGS[@]}" 2>&1); then
  gate_passed=true
fi

echo "$gate_output"
echo ""

if [[ "$gate_passed" != true ]]; then
  echo "GATE FAILED — cannot advance phase"
  echo "Fix the issues above and try again."
  exit 1
fi

# Check if human approval is required
requires_human=$(echo "$gate_output" | jq -r '.humanApprovalRequired // false' 2>/dev/null || echo "false")

if [[ "$requires_human" == "true" && "$FORCE" != true ]]; then
  echo "GATE PASSED but requires human approval."
  echo "Review the results above, then run with --force to advance:"
  echo "  bash $0 --project-dir $PROJECT_DIR --force"
  exit 0
fi

# Phase 3 special: check if there are remaining tasks before advancing
if [[ "$current_phase" == "3" ]]; then
  # Check if STATUS.md has remaining tasks / unchecked items
  remaining=$(rg -c "^- \[ \]" "$STATUS" 2>/dev/null || echo "0")
  if [[ "$remaining" -gt 0 && "$FORCE" != true ]]; then
    echo "Phase 3 gate passed but STATUS.md still has $remaining unchecked items."
    echo "Continue with more iterations or use --force to advance to Phase 4."
    exit 0
  fi

  # Trigger spec change notification if detected
  spec_detected=$(echo "$gate_output" | jq -r '.specChangeDetected // false' 2>/dev/null || echo "false")
  if [[ "$spec_detected" == "true" ]]; then
    echo "Spec changes detected — triggering notification..."
    bash "$SCRIPT_DIR/notify-spec-change.sh" \
      --project-dir "$PROJECT_DIR" \
      --label "$(basename "$PROJECT_DIR")" \
      --iteration "${ITERATION:-0}" \
      2>/dev/null || echo "WARN: spec change notification failed"
  fi
fi

# Advance phase
next_phase=$((current_phase + 1))

if [[ "$current_phase" == "4" ]]; then
  # Phase 4 complete → mark project as COMPLETED
  echo "Phase 4 gate passed — marking project as COMPLETED"

  # Update STATUS.md
  if sed --version >/dev/null 2>&1; then
    sed -i "s/^\*\*Phase 4.*$/\*\*COMPLETED\*\* ✅/" "$STATUS"
    sed -i "s/- \[ \] Phase 4/- [x] Phase 4/" "$STATUS"
  else
    sed -i '' "s/^\*\*Phase 4.*$/\*\*COMPLETED\*\* ✅/" "$STATUS"
    sed -i '' "s/- \[ \] Phase 4/- [x] Phase 4/" "$STATUS"
  fi

  echo ""
  echo "Project COMPLETED!"
  exit 0
fi

# Update STATUS.md: advance to next phase
phase_names=("" "需求分析" "技术设计" "开发迭代" "交付验收")
current_name="${phase_names[$current_phase]}"
next_name="${phase_names[$next_phase]}"

echo "Advancing: Phase $current_phase ($current_name) → Phase $next_phase ($next_name)"

# Update Current Phase line
if sed --version >/dev/null 2>&1; then
  sed -i "s/^\*\*Phase ${current_phase}:.*⬅️ 当前阶段$/\*\*Phase ${next_phase}: ${next_name}\*\* ⬅️ 当前阶段/" "$STATUS"
  sed -i "s/- \[ \] Phase ${current_phase}/- [x] Phase ${current_phase}/" "$STATUS"
else
  sed -i '' "s/^\*\*Phase ${current_phase}:.*⬅️ 当前阶段$/\*\*Phase ${next_phase}: ${next_name}\*\* ⬅️ 当前阶段/" "$STATUS"
  sed -i '' "s/- \[ \] Phase ${current_phase}/- [x] Phase ${current_phase}/" "$STATUS"
fi

echo ""
echo "STATUS.md updated. Now in Phase $next_phase ($next_name)."
echo ""
echo "Next: dispatch Phase $next_phase"
echo "  bash $SCRIPT_DIR/dispatch-phase.sh --project-dir $PROJECT_DIR --phase $next_phase"
