#!/usr/bin/env bash
# capture-execution.sh
# 定期捕获 Claude Code 执行状态，生成结构化事件日志
# 用于闭环反馈分析

set -euo pipefail

SESSION=""
SOCKET=""
INTERVAL=10
MAX_DURATION=7200  # 2小时超时

TARGET="local"
SSH_HOST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --socket) SOCKET="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --max-duration) MAX_DURATION="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --ssh-host) SSH_HOST="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$SESSION" ]]; then
  echo "Usage: $0 --session <session> [--socket <path>] [--interval <sec>] [--target local|ssh --ssh-host <alias>]"
  exit 1
fi

# 默认 socket 路径
if [[ -z "$SOCKET" ]]; then
  if [[ "$TARGET" == "ssh" ]]; then
    SOCKET="/tmp/clawdbot-tmux-sockets/clawdbot.sock"
  else
    SOCKET="${TMPDIR:-/tmp}/clawdbot-tmux-sockets/clawdbot.sock"
  fi
fi

LOG_FILE="/tmp/${SESSION}-execution-events.jsonl"
SUMMARY_FILE="/tmp/${SESSION}-execution-summary.json"

# 清理旧日志
rm -f "$LOG_FILE" "$SUMMARY_FILE"

# 统计变量
start_time=$(date +%s)
total_events=0
thinking_count=0
executing_count=0
success_count=0
error_count=0
last_event=""
last_content=""

capture_pane() {
  if [[ "$TARGET" == "ssh" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" \
      "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; tmux -S '$SOCKET' capture-pane -p -J -t '$SESSION':0.0 -S -150" 2>/dev/null || echo ""
  else
    tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -150 2>/dev/null || echo ""
  fi
}

check_session_alive() {
  if [[ "$TARGET" == "ssh" ]]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" \
      "export PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH; tmux -S '$SOCKET' has-session -t '$SESSION'" 2>/dev/null
  else
    tmux -S "$SOCKET" has-session -t "$SESSION" 2>/dev/null
  fi
}

parse_event() {
  local content="$1"
  local event="unknown"
  local detail=""
  
  # 检测各种状态（按优先级）
  if echo "$content" | grep -qE "✓.*completed|Successfully|Done\!"; then
    event="tool_success"
    detail=$(echo "$content" | grep -oE "✓[^✗]*" | tail -1 | head -c 200)
    ((success_count++)) || true
  elif echo "$content" | grep -qE "✗|Error:|error:|failed|FAILED|Cannot|cannot"; then
    event="tool_error"
    detail=$(echo "$content" | grep -oE "(✗|Error:|error:)[^\n]*" | tail -1 | head -c 200)
    ((error_count++)) || true
  elif echo "$content" | grep -qE "Thinking|Envisioning|Mustering|Planning"; then
    event="thinking"
    ((thinking_count++)) || true
  elif echo "$content" | grep -qE "Running|Bash\(|Read [0-9]+ file|Write\(|Edit\("; then
    event="executing"
    detail=$(echo "$content" | grep -oE "(Running|Bash\(|Read|Write\(|Edit\()[^\n]*" | tail -1 | head -c 200)
    ((executing_count++)) || true
  elif echo "$content" | grep -qE "waiting for|Waiting|idle|❯ $"; then
    event="idle"
  elif echo "$content" | grep -qE "completion-report|wake\.sh|Claude Code done"; then
    event="completing"
  fi
  
  echo "$event|$detail"
}

write_event() {
  local event="$1"
  local detail="$2"
  local snippet="$3"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  jq -n -c \
    --arg ts "$timestamp" \
    --arg event "$event" \
    --arg detail "$detail" \
    --arg snippet "${snippet: -300}" \
    '{timestamp: $ts, event: $event, detail: $detail, snippet: $snippet}' >> "$LOG_FILE"
  
  ((total_events++)) || true
}

write_summary() {
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local final_status="$1"
  
  jq -n \
    --arg session "$SESSION" \
    --argjson duration "$duration" \
    --argjson total_events "$total_events" \
    --argjson thinking "$thinking_count" \
    --argjson executing "$executing_count" \
    --argjson success "$success_count" \
    --argjson errors "$error_count" \
    --arg final_status "$final_status" \
    --arg log_file "$LOG_FILE" \
    '{
      session: $session,
      durationSeconds: $duration,
      totalEvents: $total_events,
      eventCounts: {
        thinking: $thinking,
        executing: $executing,
        success: $success,
        errors: $errors
      },
      finalStatus: $final_status,
      errorRate: (if $executing > 0 then ($errors / $executing * 100 | floor) else 0 end),
      logFile: $log_file
    }' > "$SUMMARY_FILE"
  
  echo "SUMMARY_FILE=$SUMMARY_FILE"
  cat "$SUMMARY_FILE"
}

cleanup() {
  write_summary "interrupted"
  exit 0
}

trap cleanup SIGINT SIGTERM

echo "Starting execution capture for session: $SESSION"
echo "Log file: $LOG_FILE"
echo "Interval: ${INTERVAL}s, Max duration: ${MAX_DURATION}s"

elapsed=0
consecutive_idle=0

while [[ $elapsed -lt $MAX_DURATION ]]; do
  # 检查会话是否存活
  if ! check_session_alive; then
    echo "Session $SESSION ended"
    write_summary "session_ended"
    exit 0
  fi
  
  # 捕获 pane 内容
  content=$(capture_pane)
  
  if [[ -z "$content" ]]; then
    ((consecutive_idle++)) || true
    if [[ $consecutive_idle -gt 30 ]]; then
      echo "No output for 5 minutes, session may be stuck"
      write_event "stuck" "No output for extended period" ""
    fi
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
    continue
  fi
  
  consecutive_idle=0
  
  # 解析事件
  result=$(parse_event "$content")
  event=$(echo "$result" | cut -d'|' -f1)
  detail=$(echo "$result" | cut -d'|' -f2-)
  
  # 只记录状态变化或重要事件
  if [[ "$event" != "$last_event" ]] || [[ "$event" == "tool_error" ]] || [[ "$event" == "tool_success" ]]; then
    write_event "$event" "$detail" "$content"
    last_event="$event"
    echo "[$(date +%H:%M:%S)] Event: $event"
  fi
  
  # 检测完成信号
  if [[ "$event" == "completing" ]]; then
    echo "Completion signal detected"
    sleep 5  # 等待报告写入
    write_summary "completed"
    exit 0
  fi
  
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done

echo "Max duration reached"
write_summary "timeout"
