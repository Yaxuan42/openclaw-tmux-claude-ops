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

# ── Build rich notification message ──
# Priority: stream.jsonl result (Claude's own summary) > report notes > raw TEXT
NOTIFY_MSG="$TEXT"

if [[ -n "$REPORT_PATH" && -f "$REPORT_PATH" ]]; then
  _summary=""

  # Try stream.jsonl first — contains Claude Code's own completion summary
  _stream_log="/tmp/cc-${_label}-stream.jsonl"
  if [[ -f "$_stream_log" ]]; then
    _summary=$(grep '"subtype":"success"' "$_stream_log" 2>/dev/null | tail -1 | jq -r '.result // ""' 2>/dev/null || echo "")
  fi

  # Fallback: report notes field
  if [[ -z "$_summary" ]]; then
    _summary=$(jq -r '.notes // ""' "$REPORT_PATH" 2>/dev/null || echo "")
  fi

  if [[ -n "$_summary" ]]; then
    # Prefix with status + label header
    if [[ "$_success" == true ]]; then
      NOTIFY_MSG="[Done] $_label
$_summary"
    else
      NOTIFY_MSG="[Done - issues] $_label
$_summary
Issue: $_failure_reason"
    fi
  fi
fi

# ── Send notifications ──

# Edward's Feishu user ID for direct notification
EDWARD_USER_ID="ou_e5eb026fddb0fe05895df71a56f65e2f"

# Channel 1: Direct Feishu DM via openclaw message send (most reliable)
# Note: must use --account main (feishu account name in openclaw.json)
openclaw message send \
  --channel feishu \
  --account main \
  --target "$EDWARD_USER_ID" \
  -m "$NOTIFY_MSG" \
  >/dev/null 2>&1 || true

# Channel 2: Trigger gateway wake for session continuity (use raw TEXT, not rich msg)
PARAMS="{\"text\":\"${TEXT//\"/\\\"}\",\"mode\":\"$MODE\"}"
if openclaw gateway call wake --params "$PARAMS" >/dev/null 2>&1; then
  echo "ok"
  exit 0
fi

# Channel 3: Fallback for older CLIs
openclaw gateway wake "$TEXT" --mode "$MODE" >/dev/null 2>&1 || true

echo "ok"
