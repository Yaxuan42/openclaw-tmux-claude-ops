#!/usr/bin/env bash
set -euo pipefail

# timeout-guard.sh — Background timeout watchdog for Claude Code tasks.
# Launched by start-tmux-task.sh; sleeps for the configured timeout,
# then checks if the task is still running without completion.
# Pure shell — no LLM token consumption.

LABEL=""
SESSION=""
SOCKET="${TMPDIR:-/tmp}/clawdbot-tmux-sockets/clawdbot.sock"
TIMEOUT=7200  # default: 2 hours

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --socket) SOCKET="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$LABEL" ]] || { echo "Usage: $0 --label <label> [--session cc-xxx] [--socket path] [--timeout seconds]"; exit 1; }

SESSION="${SESSION:-cc-${LABEL}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNS_DIR="$SCRIPT_DIR/../runs/$LABEL"
mkdir -p "$RUNS_DIR"

REPORT_JSON="$RUNS_DIR/completion-report.json"
PID_FILE="$RUNS_DIR/timeout.pid"
DIAGNOSE_SCRIPT="$SCRIPT_DIR/diagnose-failure.sh"
HISTORY_FILE="$SCRIPT_DIR/../TASK_HISTORY.jsonl"

EDWARD_USER_ID="ou_e5eb026fddb0fe05895df71a56f65e2f"

# Write PID file so other scripts (on-session-exit.sh) can kill us
echo $$ > "$PID_FILE"

# Clean up PID file on exit
cleanup() { rm -f "$PID_FILE"; }
trap cleanup EXIT

echo "timeout-guard: started for $LABEL (timeout=${TIMEOUT}s, PID=$$)"

# Sleep for the configured timeout
sleep "$TIMEOUT"

echo "timeout-guard: woke up after ${TIMEOUT}s"

# Check if the tmux session still exists
if ! tmux -S "$SOCKET" has-session -t "$SESSION" 2>/dev/null; then
  echo "timeout-guard: session $SESSION no longer exists — task already ended."
  exit 0
fi

# Session still exists — check if report was generated
if [[ -f "$REPORT_JSON" ]]; then
  # Report exists but session still alive — likely done, just needs cleanup
  notify_msg="[Claude Code 清理提醒] 任务 ${LABEL} 已生成报告但 tmux session 仍在运行。
建议手动清理: tmux -S \"$SOCKET\" kill-session -t \"$SESSION\""

  echo "timeout-guard: report exists, session still alive — sending cleanup reminder"
  openclaw message send \
    --channel feishu \
    --account main \
    --target "$EDWARD_USER_ID" \
    -m "$notify_msg" \
    >/dev/null 2>&1 || echo "WARN: Failed to send Feishu notification"
  exit 0
fi

# ── Timeout: no report, session still running ──────────────────────
echo "timeout-guard: TIMEOUT — no report, session still running"

# Run diagnosis
diag_json=""
if [[ -f "$DIAGNOSE_SCRIPT" ]]; then
  echo "timeout-guard: running diagnose-failure.sh..."
  diag_json="$(bash "$DIAGNOSE_SCRIPT" --label "$LABEL" --session "$SESSION" --socket "$SOCKET" 2>/dev/null || echo "")"
fi

suggestion="任务运行超过 $((TIMEOUT / 60)) 分钟仍未完成，可能已挂住。"
failure_cat="timeout"
if [[ -n "$diag_json" ]]; then
  parsed_suggestion="$(echo "$diag_json" | jq -r '.suggestion // empty' 2>/dev/null || echo "")"
  if [[ -n "$parsed_suggestion" ]]; then
    suggestion="$parsed_suggestion"
  fi
  failure_cat="$(echo "$diag_json" | jq -r '.failureCategory // "timeout"' 2>/dev/null || echo "timeout")"
fi

# Send Feishu DM notification
timeout_min=$((TIMEOUT / 60))
notify_msg="[Claude Code 超时] 任务 ${LABEL} 运行超过 ${timeout_min} 分钟仍未完成。
分类: ${failure_cat}
建议: ${suggestion}
查看: tmux -S \"$SOCKET\" attach -t \"$SESSION\""

openclaw message send \
  --channel feishu \
  --account main \
  --target "$EDWARD_USER_ID" \
  -m "$notify_msg" \
  >/dev/null 2>&1 || echo "WARN: Failed to send Feishu notification"

# Record to TASK_HISTORY
jq -n -c \
  --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg label "$LABEL" \
  --argjson success false \
  --arg failureReason "timeout:${failure_cat}" \
  --arg risk "high" \
  --arg recommendation "investigate" \
  --argjson durationSeconds "$TIMEOUT" \
  '{
    timestamp: $timestamp,
    label: $label,
    workdir: "unknown",
    success: $success,
    failureReason: $failureReason,
    risk: $risk,
    recommendation: $recommendation,
    durationSeconds: $durationSeconds,
    executionErrors: 0,
    filesChanged: 0
  }' >> "$HISTORY_FILE" 2>/dev/null || echo "WARN: Failed to write task history"

echo "timeout-guard: completed"
