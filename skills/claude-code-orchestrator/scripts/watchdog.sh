#!/usr/bin/env bash
set -euo pipefail

# watchdog.sh — Periodic health check for cc-* tmux task sessions.
# Designed to run as an OpenClaw cron job every 10 minutes.
#
# Actions:
#   - dead tasks (session gone, no report): notify Edward
#   - stuck tasks (running >2h with error signals): notify Edward
#   - likely_done / done_session_ended tasks with report: one-time delivery push via wake.sh
#   - running tasks >3h: warn Edward about long-running task
#
# Delivery gap fix: for completed tasks with a report, watchdog now triggers
# a full delivery push through wake.sh (with report path) exactly once.
# Subsequent runs stay silent for already-delivered labels.
#
# Output: JSON summary for cron delivery, or "HEARTBEAT_OK" if nothing to report.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_SCRIPT="$SCRIPT_DIR/list-tasks.sh"
WAKE_SCRIPT="$SCRIPT_DIR/wake.sh"
RUNS_DIR="$SCRIPT_DIR/../runs"

SOCKET="${TMPDIR:-/tmp}/clawdbot-tmux-sockets/clawdbot.sock"
STALE_FILE="/tmp/cc-watchdog-state.json"
DELIVERED_FILE="/tmp/cc-watchdog-delivered.json"

# Thresholds (seconds)
STUCK_THRESHOLD=7200    # 2 hours
LONG_THRESHOLD=10800    # 3 hours

# ── Load delivered-labels tracker ──────────────────────────────────
if [[ -f "$DELIVERED_FILE" ]]; then
  delivered_state="$(cat "$DELIVERED_FILE")"
else
  delivered_state="{}"
fi

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
      # ── One-time delivery push for completed tasks with reports ──
      report_path="$RUNS_DIR/$label/completion-report.json"
      already_delivered="$(echo "$delivered_state" | jq -r --arg l "$label" '.[$l] // ""')"

      if [[ -f "$report_path" && -z "$already_delivered" ]]; then
        # Extract delivery summary fields (with fallbacks for missing fields)
        _risk="$(jq -r '.risk // "unknown"' "$report_path" 2>/dev/null || echo "unknown")"
        _rec="$(jq -r '.recommendation // "unknown"' "$report_path" 2>/dev/null || echo "unknown")"
        _notes="$(jq -r '.notes // "No notes available"' "$report_path" 2>/dev/null || echo "No notes available")"
        # Truncate notes to 240 chars
        if [[ ${#_notes} -gt 240 ]]; then
          _notes="${_notes:0:237}..."
        fi

        # Trigger full delivery via wake.sh (with report path for history + rich notification)
        bash "$WAKE_SCRIPT" \
          "Claude Code done ($label) report=$report_path" now 2>/dev/null || true

        # Mark as delivered
        delivered_state="$(echo "$delivered_state" | jq --arg l "$label" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '. + {($l): $t}')"

        alerts+=("$(jq -n -c --arg l "$label" --arg s "$status" --argjson a "$age" \
          --arg risk "$_risk" --arg rec "$_rec" --arg notes "$_notes" \
          '{label:$l, status:$s, age_min:($a/60|floor), risk:$risk, recommendation:$rec, notes:$notes, action:"Delivery push sent. Report available."}')")
      fi
      # Already delivered: stay silent — no alert added
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

# Save delivered-labels tracker
echo "$delivered_state" | jq '.' > "$DELIVERED_FILE"

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
