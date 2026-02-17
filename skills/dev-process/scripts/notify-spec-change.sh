#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=""
LABEL=""
ITERATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --iteration) ITERATION="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$PROJECT_DIR" && -n "$LABEL" ]] || {
  echo "Usage: $0 --project-dir <dir> --label <label> [--iteration <N>]"
  exit 1
}

ITERATION="${ITERATION:-0}"
CHANGELOG="$PROJECT_DIR/docs/CHANGELOG.md"
FEISHU_USER_ID="ou_e5eb026fddb0fe05895df71a56f65e2f"

if [[ ! -f "$CHANGELOG" ]]; then
  echo "No CHANGELOG.md found — nothing to notify"
  exit 0
fi

# Extract [spec-change] entries
spec_entries=$(rg "\[spec-change\]" "$CHANGELOG" 2>/dev/null || true)

if [[ -z "$spec_entries" ]]; then
  echo "No [spec-change] entries found"
  exit 0
fi

spec_count=$(echo "$spec_entries" | wc -l | tr -d ' ')

# Build notification message
msg="[Dev Process] Spec 变更检测
任务: $LABEL (迭代 #$ITERATION)
项目: $PROJECT_DIR

检测到 $spec_count 处 spec 变更：
$spec_entries

请检查变更是否合理。"

echo "Sending spec change notification ($spec_count changes)..."

openclaw message send \
  --type feishu_dm \
  --receiver-id "$FEISHU_USER_ID" \
  --text "$msg" \
  2>/dev/null || echo "WARN: Feishu notification failed (openclaw not available)"

echo "Done."
