#!/usr/bin/env bash
set -euo pipefail

# watchdog.sh — Periodic health check for cc-* tmux task sessions.
# Designed to run as an OpenClaw cron job every 10 minutes.
#
# Actions:
#   - dead tasks (session gone, no report): notify Edward
#   - stuck tasks (running >2h with error signals): notify Edward
#   - likely_done tasks (report exists, session still alive): notify + cleanup hint
#   - running tasks >3h: warn Edward about long-running task
#
# Output: JSON summary for cron delivery, or "HEARTBEAT_OK" if nothing to report.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_SCRIPT="$SCRIPT_DIR/list-tasks.sh"
WAKE_SCRIPT="$SCRIPT_DIR/wake.sh"

SOCKET="${TMPDIR:-/tmp}/clawdbot-tmux-sockets/clawdbot.sock"
STALE_FILE="/tmp/cc-watchdog-state.json"

# Thresholds (seconds)
STUCK_THRESHOLD=7200    # 2 hours
LONG_THRESHOLD=10800    # 3 hours

# ── Get task list ────────────────────────────────────────────────────
tasks_json="$(bash "$LIST_SCRIPT" --json --socket "$SOCKET" 2>/dev/null || echo "[]")"
task_count="$(echo "$tasks_json" | jq 'length')"

if [[ "$task_count" -eq 0 ]]; then
  echo "HEARTBEAT_OK"
  exit 0
fi

# ── Load previous state for age tracking ─────────────────────────────
# We track when we first saw each session to estimate runtime
if [[ -f "$STALE_FILE" ]]; then
  prev_state="$(cat "$STALE_FILE")"
else
  prev_state="{}"
fi

now_epoch="$(date +%s)"
alerts=()
new_state="{}"

for i in $(seq 0 $((task_count - 1))); do
  task="$(echo "$tasks_json" | jq ".[$i]")"
  label="$(echo "$task" | jq -r '.label')"
  session="$(echo "$task" | jq -r '.session')"
  status="$(echo "$task" | jq -r '.status')"
  session_alive="$(echo "$task" | jq -r '.sessionAlive')"
  report_exists="$(echo "$task" | jq -r '.reportExists')"

  # Track first-seen time for this session
  first_seen="$(echo "$prev_state" | jq -r --arg s "$session" '.[$s] // 0')"
  if [[ "$first_seen" == "0" || "$first_seen" == "null" ]]; then
    first_seen="$now_epoch"
  fi
  new_state="$(echo "$new_state" | jq --arg s "$session" --argjson t "$first_seen" '. + {($s): $t}')"

  age=$((now_epoch - first_seen))

  case "$status" in
    dead)
      alerts+=("$(jq -n -c --arg l "$label" --arg s "$status" --argjson a "$age" \
        '{label:$l, status:$s, age_min:($a/60|floor), action:"Session crashed without report. May need manual investigation."}')")
      ;;
    stuck)
      alerts+=("$(jq -n -c --arg l "$label" --arg s "$status" --argjson a "$age" \
        '{label:$l, status:$s, age_min:($a/60|floor), action:"Task appears stuck (error signals detected). Consider checking or killing session."}')")
      ;;
    likely_done|done_session_ended)
      alerts+=("$(jq -n -c --arg l "$label" --arg s "$status" --argjson a "$age" \
        '{label:$l, status:$s, age_min:($a/60|floor), action:"Task completed. Report available. Session can be cleaned up."}')")
      ;;
    running|idle)
      if [[ "$age" -ge "$LONG_THRESHOLD" ]]; then
        alerts+=("$(jq -n -c --arg l "$label" --arg s "$status" --argjson a "$age" \
          '{label:$l, status:$s, age_min:($a/60|floor), action:"Long-running task (>3h). Check if still making progress."}')")
      elif [[ "$age" -ge "$STUCK_THRESHOLD" && "$status" == "idle" ]]; then
        alerts+=("$(jq -n -c --arg l "$label" --arg s "$status" --argjson a "$age" \
          '{label:$l, status:$s, age_min:($a/60|floor), action:"Task idle for >2h. May need attention."}')")
      fi
      # Normal running tasks within threshold: no alert
      ;;
  esac
done

# Save state for next run
echo "$new_state" | jq '.' > "$STALE_FILE"

# ── Report ───────────────────────────────────────────────────────────
if [[ ${#alerts[@]} -eq 0 ]]; then
  echo "HEARTBEAT_OK"
  exit 0
fi

# Build alert summary
alert_json="$(printf '%s\n' "${alerts[@]}" | jq -s '.')"

summary="Task Watchdog Alert ($task_count active sessions):\n"
for alert in "${alerts[@]}"; do
  _label="$(echo "$alert" | jq -r '.label')"
  _status="$(echo "$alert" | jq -r '.status')"
  _age="$(echo "$alert" | jq -r '.age_min')"
  _action="$(echo "$alert" | jq -r '.action')"
  summary+="- [$_status] $_label (${_age}min): $_action\n"
done

# Send notification via wake.sh
bash "$WAKE_SCRIPT" "$(echo -e "$summary")" now 2>/dev/null || true

# Output for cron delivery
echo "$alert_json" | jq '.'
