#!/usr/bin/env bash
set -euo pipefail

# on-session-exit.sh — tmux pane-died hook handler.
# Called automatically when a Claude Code tmux session's pane dies.
# Pure shell — no LLM token consumption.

LABEL=""
SESSION=""
SOCKET="${TMPDIR:-/tmp}/clawdbot-tmux-sockets/clawdbot.sock"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --socket) SOCKET="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$LABEL" ]] || { echo "Usage: $0 --label <label> [--session cc-xxx] [--socket path]"; exit 1; }

SESSION="${SESSION:-cc-${LABEL}}"
REPORT_JSON="/tmp/${SESSION}-completion-report.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIAGNOSE_SCRIPT="$SCRIPT_DIR/diagnose-failure.sh"
HISTORY_FILE="$SCRIPT_DIR/../TASK_HISTORY.jsonl"

EDWARD_USER_ID="ou_e5eb026fddb0fe05895df71a56f65e2f"

LOG_FILE="/tmp/${SESSION}-on-exit.log"
exec >> "$LOG_FILE" 2>&1
echo "=== on-session-exit.sh triggered at $(date) ==="
echo "LABEL=$LABEL SESSION=$SESSION"

# Wait briefly for POST_CMD / wake.sh chain to complete
sleep 3

# Kill the timeout guard if it's still running
TIMEOUT_PID_FILE="/tmp/cc-${LABEL}-timeout.pid"
if [[ -f "$TIMEOUT_PID_FILE" ]]; then
  timeout_pid=$(cat "$TIMEOUT_PID_FILE" 2>/dev/null || echo "")
  if [[ -n "$timeout_pid" ]] && kill -0 "$timeout_pid" 2>/dev/null; then
    kill "$timeout_pid" 2>/dev/null || true
    echo "Killed timeout guard PID=$timeout_pid"
  fi
  rm -f "$TIMEOUT_PID_FILE"
fi

# Kill the capture process if it's still running
CAPTURE_PID_FILE="/tmp/${SESSION}-capture.pid"
if [[ -f "$CAPTURE_PID_FILE" ]]; then
  cap_pid=$(cat "$CAPTURE_PID_FILE" 2>/dev/null || echo "")
  if [[ -n "$cap_pid" ]] && kill -0 "$cap_pid" 2>/dev/null; then
    kill "$cap_pid" 2>/dev/null || true
    echo "Killed capture process PID=$cap_pid"
  fi
  rm -f "$CAPTURE_PID_FILE"
fi

# Check if completion report exists (normal exit path)
if [[ -f "$REPORT_JSON" ]]; then
  echo "Report exists at $REPORT_JSON — normal exit, wake.sh should have handled it."
  # Clean up the tmux session (remain-on-exit keeps it alive)
  tmux -S "$SOCKET" kill-session -t "$SESSION" 2>/dev/null || true
  exit 0
fi

# ── Abnormal exit: no report found ──────────────────────────────────
echo "No report found — abnormal exit detected."

# Run diagnosis (pure shell, no LLM)
diag_json=""
if [[ -x "$DIAGNOSE_SCRIPT" || -f "$DIAGNOSE_SCRIPT" ]]; then
  echo "Running diagnose-failure.sh..."
  diag_json="$(bash "$DIAGNOSE_SCRIPT" --label "$LABEL" --session "$SESSION" --socket "$SOCKET" 2>/dev/null || echo "")"
  echo "Diagnosis result: $diag_json"
fi

# Extract suggestion from diagnosis
suggestion="任务异常退出，未生成完成报告。建议检查任务日志。"
if [[ -n "$diag_json" ]]; then
  parsed_suggestion="$(echo "$diag_json" | jq -r '.suggestion // empty' 2>/dev/null || echo "")"
  if [[ -n "$parsed_suggestion" ]]; then
    suggestion="$parsed_suggestion"
  fi
  failure_cat="$(echo "$diag_json" | jq -r '.failureCategory // "unknown"' 2>/dev/null || echo "unknown")"
else
  failure_cat="unknown"
fi

# Send Feishu DM notification
notify_msg="[Claude Code 异常退出] 任务 ${LABEL} 的 tmux session 已终止，但未生成完成报告。
分类: ${failure_cat}
建议: ${suggestion}
日志: /tmp/${SESSION}-on-exit.log"

echo "Sending Feishu notification..."
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
  --arg failureReason "abnormal_exit:${failure_cat}" \
  --arg risk "high" \
  --arg recommendation "investigate" \
  '{
    timestamp: $timestamp,
    label: $label,
    workdir: "unknown",
    success: $success,
    failureReason: $failureReason,
    risk: $risk,
    recommendation: $recommendation,
    durationSeconds: 0,
    executionErrors: 0,
    filesChanged: 0
  }' >> "$HISTORY_FILE" 2>/dev/null || echo "WARN: Failed to write task history"

# Clean up the tmux session (remain-on-exit keeps it alive after pane dies)
tmux -S "$SOCKET" kill-session -t "$SESSION" 2>/dev/null || true

echo "=== on-session-exit.sh completed ==="
