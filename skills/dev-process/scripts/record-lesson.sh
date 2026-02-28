#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=""
CATEGORY=""
PROBLEM=""
SOLUTION=""
SEVERITY="medium"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --category) CATEGORY="$2"; shift 2 ;;
    --problem) PROBLEM="$2"; shift 2 ;;
    --solution) SOLUTION="$2"; shift 2 ;;
    --severity) SEVERITY="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$PROJECT_DIR" && -n "$CATEGORY" && -n "$PROBLEM" && -n "$SOLUTION" ]] || {
  echo "Usage: $0 --project-dir <dir> --category <Architecture|Code|Testing|Process> --problem <str> --solution <str> [--severity low|medium|high]"
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_BASE="$SCRIPT_DIR/../knowledge_base/cross_project_lessons.jsonl"
TODAY="$(date +%Y-%m-%d)"

# Append to project LESSONS_LEARNED.md
LESSONS="$PROJECT_DIR/docs/LESSONS_LEARNED.md"
if [[ -f "$LESSONS" ]]; then
  # Find the right category section and append a table row
  # We append at the end of the matching section's table
  TABLE_ROW="| $TODAY | $PROBLEM | - | $SOLUTION | $SEVERITY |"

  # Check if category section exists
  if rg -q "## $CATEGORY" "$LESSONS" 2>/dev/null; then
    # Append row after the last table row in the section (or after header row)
    # Simple approach: append before the next ## or at end of file
    # Use a temp file approach for reliability
    awk -v cat="## $CATEGORY" -v row="$TABLE_ROW" '
      BEGIN { found=0; inserted=0 }
      $0 == cat { found=1 }
      found && !inserted && /^$/ { print row; inserted=1 }
      { print }
      END { if (found && !inserted) print row }
    ' "$LESSONS" > "${LESSONS}.tmp"
    mv "${LESSONS}.tmp" "$LESSONS"
    echo "Appended lesson to $LESSONS under $CATEGORY"
  else
    echo "WARN: Category '$CATEGORY' not found in LESSONS_LEARNED.md — appending at end"
    echo "" >> "$LESSONS"
    echo "## $CATEGORY" >> "$LESSONS"
    echo "" >> "$LESSONS"
    echo "| Date | Problem | Root Cause | Solution | Severity |" >> "$LESSONS"
    echo "|------|---------|-----------|----------|----------|" >> "$LESSONS"
    echo "$TABLE_ROW" >> "$LESSONS"
  fi
else
  echo "WARN: $LESSONS not found — skipping project-level recording"
fi

# Append to cross-project knowledge base
PROJECT_NAME="$(basename "$PROJECT_DIR")"
jq -n \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg project "$PROJECT_NAME" \
  --arg category "$CATEGORY" \
  --arg problem "$PROBLEM" \
  --arg solution "$SOLUTION" \
  --arg severity "$SEVERITY" \
  '{timestamp: $timestamp, project: $project, category: $category, problem: $problem, solution: $solution, severity: $severity}' \
  >> "$KNOWLEDGE_BASE"

echo "Recorded to cross-project knowledge base: $KNOWLEDGE_BASE"
