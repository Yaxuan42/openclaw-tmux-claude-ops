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
# Parse report path from TEXT: "... report=/path/to/completion-report.json"
# Support paths with spaces (match from "report=" to ".json")
REPORT_PATH=""
if [[ "$TEXT" =~ report=(.+\.json) ]]; then
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

  # Read execution metrics
  _runs_dir="$(dirname "$REPORT_PATH")"
  _exec_summary="$_runs_dir/execution-summary.json"
  _stream_log="$_runs_dir/stream.jsonl"
  _duration=0
  _exec_errors=0
  _cost="0"

  # Source 1: execution-summary.json (interactive mode)
  if [[ -f "$_exec_summary" ]]; then
    _duration=$(jq -r '.durationSeconds // 0' "$_exec_summary" 2>/dev/null || echo "0")
    _exec_errors=$(jq -r '.eventCounts.errors // 0' "$_exec_summary" 2>/dev/null || echo "0")
  fi

  # Source 2: stream.jsonl result line (headless mode fallback)
  if [[ -f "$_stream_log" ]]; then
    _result_line=$(grep '"subtype":"result"' "$_stream_log" 2>/dev/null | tail -1 || true)
    if [[ -n "$_result_line" ]]; then
      if [[ "$_duration" -eq 0 ]]; then
        _duration=$(echo "$_result_line" | jq -r '.duration_ms // 0' 2>/dev/null | awk '{printf "%.0f", $1/1000}' || echo "0")
      fi
      _cost=$(echo "$_result_line" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo "0")
    fi
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
    --argjson costUSD "$_cost" \
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
      filesChanged: $filesChanged,
      costUSD: $costUSD
    }' >> "$HISTORY_FILE" 2>/dev/null || true
fi

# ── Build rich notification message ──
# Priority: stream.jsonl result (Claude's own summary) > report notes > raw TEXT
NOTIFY_MSG="$TEXT"

if [[ -n "$REPORT_PATH" && -f "$REPORT_PATH" ]]; then
  _summary=""

  # Try stream.jsonl first — contains Claude Code's own completion summary
  _stream_log="$_runs_dir/stream.jsonl"
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

# Notification target: set OPENCLAW_CC_ALERT_TARGET env var (e.g. Feishu user ID).
# If unset, Feishu DM is skipped (gateway wake still fires).
ALERT_TARGET="${OPENCLAW_CC_ALERT_TARGET:-}"

# Channel 1: Direct Feishu DM via openclaw message send (most reliable)
# Note: must use --account main (feishu account name in openclaw.json)
if [[ -n "$ALERT_TARGET" ]]; then
  openclaw message send \
    --channel feishu \
    --account main \
    --target "$ALERT_TARGET" \
    -m "$NOTIFY_MSG" \
    >/dev/null 2>&1 || true
fi

# Channel 2: Trigger gateway wake for session continuity (use raw TEXT, not rich msg)
PARAMS="{\"text\":\"${TEXT//\"/\\\"}\",\"mode\":\"$MODE\"}"
if openclaw gateway call wake --params "$PARAMS" >/dev/null 2>&1; then
  echo "ok"
  exit 0
fi

# Channel 3: Fallback for older CLIs
openclaw gateway wake "$TEXT" --mode "$MODE" >/dev/null 2>&1 || true

echo "ok"
