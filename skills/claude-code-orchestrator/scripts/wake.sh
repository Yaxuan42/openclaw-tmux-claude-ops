#!/usr/bin/env bash
set -euo pipefail

TEXT="${1:-}"
MODE="${2:-now}"

if [[ -z "$TEXT" ]]; then
  echo "Usage: $0 <text> [mode: now|next-heartbeat]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY_FILE="$SCRIPT_DIR/../TASK_HISTORY.jsonl"

# ── Record task history from completion report (if available) ──
# Parse report path from TEXT: "... report=/tmp/cc-xxx-completion-report.json"
REPORT_PATH=""
if [[ "$TEXT" =~ report=([^ ]+\.json) ]]; then
  REPORT_PATH="${BASH_REMATCH[1]}"
fi

if [[ -n "$REPORT_PATH" && -f "$REPORT_PATH" ]]; then
  # Extract fields from the completion report
  _label=$(jq -r '.label // "unknown"' "$REPORT_PATH" 2>/dev/null || echo "unknown")
  _workdir=$(jq -r '.workdir // "unknown"' "$REPORT_PATH" 2>/dev/null || echo "unknown")
  _risk=$(jq -r '.risk // "unknown"' "$REPORT_PATH" 2>/dev/null || echo "unknown")
  _recommendation=$(jq -r '.recommendation // "unknown"' "$REPORT_PATH" 2>/dev/null || echo "unknown")
  _files_changed=$(jq -r '.changedFiles | length' "$REPORT_PATH" 2>/dev/null || echo "0")
  _lint_ok=$(jq -r '.lint.ok // true' "$REPORT_PATH" 2>/dev/null || echo "true")
  _build_ok=$(jq -r '.build.ok // true' "$REPORT_PATH" 2>/dev/null || echo "true")

  # Determine success and failure reason
  _success=true
  _failure_reason=""
  if [[ "$_lint_ok" != "true" ]]; then
    _success=false
    _failure_reason="lint_failed"
  elif [[ "$_build_ok" != "true" ]]; then
    _success=false
    _failure_reason="build_failed"
  elif [[ "$_risk" == "high" ]]; then
    _success=false
    _failure_reason="high_risk"
  fi

  # Read execution summary if available
  _session="cc-${_label}"
  _exec_summary="/tmp/${_session}-execution-summary.json"
  _duration=0
  _exec_errors=0
  if [[ -f "$_exec_summary" ]]; then
    _duration=$(jq -r '.durationSeconds // 0' "$_exec_summary" 2>/dev/null || echo "0")
    _exec_errors=$(jq -r '.eventCounts.errors // 0' "$_exec_summary" 2>/dev/null || echo "0")
  fi

  # Append to history
  jq -n -c \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg label "$_label" \
    --arg workdir "$_workdir" \
    --argjson success "$_success" \
    --arg failureReason "$_failure_reason" \
    --arg risk "$_risk" \
    --arg recommendation "$_recommendation" \
    --argjson durationSeconds "$_duration" \
    --argjson executionErrors "$_exec_errors" \
    --argjson filesChanged "$_files_changed" \
    '{
      timestamp: $timestamp,
      label: $label,
      workdir: $workdir,
      success: $success,
      failureReason: $failureReason,
      risk: $risk,
      recommendation: $recommendation,
      durationSeconds: $durationSeconds,
      executionErrors: $executionErrors,
      filesChanged: $filesChanged
    }' >> "$HISTORY_FILE" 2>/dev/null || true
fi

# ── Send notifications ──

# Edward's Feishu user ID for direct notification
EDWARD_USER_ID="ou_e5eb026fddb0fe05895df71a56f65e2f"

# Send notification to Edward's private chat via OpenClaw message tool
# This ensures he always gets notified regardless of which session triggered the task
openclaw gateway call agent --params "{
  \"message\": \"$TEXT\",
  \"channel\": \"feishu\",
  \"to\": \"user:$EDWARD_USER_ID\",
  \"deliver\": true
}" --timeout 30000 >/dev/null 2>&1 || true

# Also trigger wake for session continuity
PARAMS="{\"text\":\"${TEXT//\"/\\\"}\",\"mode\":\"$MODE\"}"
if openclaw gateway call wake --params "$PARAMS" >/dev/null 2>&1; then
  echo "ok"
  exit 0
fi

# Last resort fallback for older CLIs
openclaw gateway wake "$TEXT" --mode "$MODE" >/dev/null 2>&1 || true

echo "ok"
