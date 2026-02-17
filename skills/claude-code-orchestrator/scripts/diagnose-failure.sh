#!/usr/bin/env bash
set -euo pipefail

# diagnose-failure.sh — Analyze a failed/stuck Claude Code task and output diagnosis.
#
# Data sources (by priority):
#   1. /tmp/cc-<label>-stream.jsonl         (headless stream-json, most precise)
#   2. /tmp/cc-<label>-execution-events.jsonl (interactive sampled events)
#   3. /tmp/cc-<label>-completion-report.json (completion report)
#   4. tmux pane capture                     (fallback)
#
# Output: /tmp/cc-<label>-diagnosis.json + stdout

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

STREAM_LOG="/tmp/cc-${LABEL}-stream.jsonl"
EVENTS_LOG="/tmp/${SESSION}-execution-events.jsonl"
REPORT_JSON="/tmp/${SESSION}-completion-report.json"
DIAG_OUT="/tmp/cc-${LABEL}-diagnosis.json"

# ── Determine data source ────────────────────────────────────────────
source_name=""
raw_text=""

if [[ -f "$STREAM_LOG" && -s "$STREAM_LOG" ]]; then
  source_name="stream.jsonl"
  raw_text="$(cat "$STREAM_LOG")"
elif [[ -f "$EVENTS_LOG" && -s "$EVENTS_LOG" ]]; then
  source_name="execution-events.jsonl"
  raw_text="$(cat "$EVENTS_LOG")"
elif [[ -f "$REPORT_JSON" && -s "$REPORT_JSON" ]]; then
  source_name="completion-report.json"
  raw_text="$(cat "$REPORT_JSON")"
else
  # Fallback: tmux pane capture
  source_name="pane-capture"
  raw_text="$(tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -500 2>/dev/null || echo "")"
  if [[ -z "$raw_text" ]]; then
    echo '{"error":"No data source available for diagnosis"}' | tee "$DIAG_OUT"
    exit 1
  fi
fi

# ── Collect stats from stream.jsonl (if available) ───────────────────
total_tool_calls=0
total_errors=0
edit_count=0
unique_files_edited=0
duration_seconds=0

if [[ "$source_name" == "stream.jsonl" ]]; then
  # Use grep instead of jq -s (avoids OOM on large stream files)
  total_tool_calls=$(grep -c '"type":"tool_use"' "$STREAM_LOG" 2>/dev/null) || total_tool_calls=0
  total_errors=$(grep -c '"is_error":true' "$STREAM_LOG" 2>/dev/null) || total_errors=0
  edit_count=$(grep -c '"name":"Edit"' "$STREAM_LOG" 2>/dev/null) || edit_count=0
  unique_files_edited=$(grep -o '"file_path"\s*:\s*"[^"]*"' "$STREAM_LOG" 2>/dev/null | sort -u | wc -l | tr -d ' ') || unique_files_edited=0

  # Extract duration from the final result line (has duration_ms field)
  result_duration=$(grep '"subtype":"success"\|"subtype":"error"' "$STREAM_LOG" 2>/dev/null | tail -1 | jq -r '.duration_ms // 0' 2>/dev/null || echo 0)
  if [[ "$result_duration" -gt 0 ]]; then
    duration_seconds=$(( result_duration / 1000 ))
  fi
elif [[ "$source_name" == "execution-events.jsonl" ]]; then
  total_tool_calls=$(grep -c '"executing"' "$EVENTS_LOG" 2>/dev/null) || total_tool_calls=0
  total_errors=$(grep -c '"tool_error"' "$EVENTS_LOG" 2>/dev/null) || total_errors=0

  first_ts=$(head -1 "$EVENTS_LOG" | jq -r '.timestamp // empty' 2>/dev/null || echo "")
  last_ts=$(tail -1 "$EVENTS_LOG" | jq -r '.timestamp // empty' 2>/dev/null || echo "")
  if [[ -n "$first_ts" && -n "$last_ts" ]]; then
    first_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$first_ts" "+%s" 2>/dev/null || date -d "$first_ts" "+%s" 2>/dev/null || echo 0)
    last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_ts" "+%s" 2>/dev/null || date -d "$last_ts" "+%s" 2>/dev/null || echo 0)
    duration_seconds=$(( last_epoch - first_epoch ))
    [[ $duration_seconds -lt 0 ]] && duration_seconds=0
  fi
fi

# ── Failure pattern matching ─────────────────────────────────────────
failure_category="unknown"
confidence="low"
evidence=()
suggestion="无法确定失败原因，建议人工检查任务日志。"
retryable=false

# For stream.jsonl, only search error-bearing lines to avoid false positives
# from prompt text or assistant plans that mention error keywords.
# Strategy: search lines with is_error, subtype:error, or tool_result content
# that contains actual error output (stderr, exit code != 0, etc.)
if [[ "$source_name" == "stream.jsonl" ]]; then
  match_text=$(grep -E '"is_error":true|"subtype":"error"|"error"|Exit code [1-9]' "$STREAM_LOG" 2>/dev/null | grep -v '"type":"assistant"' || true)
else
  match_text="$raw_text"
fi

match_pattern() {
  local pattern="$1"
  local lines
  lines=$(echo "$match_text" | grep -iE "$pattern" | head -5) || true
  echo "$lines"
}

# Edit loop detection (stream.jsonl only)
if [[ "$source_name" == "stream.jsonl" ]]; then
  # Count edits per file, flag if any file edited >5 times
  loop_files=$(grep -o '"file_path"\s*:\s*"[^"]*"' "$STREAM_LOG" 2>/dev/null | sort | uniq -c | sort -rn | head -5)
  max_edits=$(echo "$loop_files" | head -1 | awk '{print $1}')
  if [[ -n "$max_edits" && "$max_edits" -gt 5 ]]; then
    failure_category="edit_loop"
    confidence="high"
    while IFS= read -r line; do
      [[ -n "$line" ]] && evidence+=("$line")
    done <<< "$loop_files"
    suggestion="Claude 在同一文件上反复编辑超过 5 次，可能陷入修复循环。建议简化需求或拆分任务。"
    retryable=false
  fi
fi

# Only match other patterns if not already identified as edit_loop
if [[ "$failure_category" == "unknown" ]]; then
  # Rate limit (check early — often the root cause)
  hits=$(match_pattern "rate.limit|429|too many requests")
  if [[ -n "$hits" ]]; then
    failure_category="rate_limit"
    confidence="high"
    while IFS= read -r line; do [[ -n "$line" ]] && evidence+=("$line"); done <<< "$hits"
    suggestion="API 限流，建议等待几分钟后重试，或减少并发任务数。"
    retryable=true
  fi
fi

if [[ "$failure_category" == "unknown" ]]; then
  hits=$(match_pattern "context.window|too long|token.limit|max.tokens|context_window_exceeded")
  if [[ -n "$hits" ]]; then
    failure_category="context_overflow"
    confidence="high"
    while IFS= read -r line; do [[ -n "$line" ]] && evidence+=("$line"); done <<< "$hits"
    suggestion="上下文窗口溢出，建议拆分任务为更小的子任务，或减少输入文件数量。"
    retryable=false
  fi
fi

if [[ "$failure_category" == "unknown" ]]; then
  hits=$(match_pattern "ETIMEOUT|timed.out|timeout|deadline.exceeded")
  if [[ -n "$hits" ]]; then
    failure_category="timeout"
    confidence="high"
    while IFS= read -r line; do [[ -n "$line" ]] && evidence+=("$line"); done <<< "$hits"
    suggestion="任务超时，建议检查网络连接或增加超时限制。"
    retryable=true
  fi
fi

if [[ "$failure_category" == "unknown" ]]; then
  hits=$(match_pattern "permission.denied|EACCES|forbidden")
  if [[ -n "$hits" ]]; then
    failure_category="permission"
    confidence="high"
    while IFS= read -r line; do [[ -n "$line" ]] && evidence+=("$line"); done <<< "$hits"
    suggestion="权限不足，检查文件/目录权限或当前用户的访问权限。"
    retryable=false
  fi
fi

if [[ "$failure_category" == "unknown" ]]; then
  hits=$(match_pattern "merge.conflict|CONFLICT|resolve.conflicts")
  if [[ -n "$hits" ]]; then
    failure_category="git_conflict"
    confidence="high"
    while IFS= read -r line; do [[ -n "$line" ]] && evidence+=("$line"); done <<< "$hits"
    suggestion="Git 合并冲突，需手动解决冲突后重试。"
    retryable=false
  fi
fi

if [[ "$failure_category" == "unknown" ]]; then
  hits=$(match_pattern "ENOENT|not found|No such file|module not found|ModuleNotFoundError|Cannot find module")
  if [[ -n "$hits" ]]; then
    failure_category="dependency_missing"
    confidence="medium"
    while IFS= read -r line; do [[ -n "$line" ]] && evidence+=("$line"); done <<< "$hits"
    suggestion="依赖或文件缺失，建议检查依赖安装状态或文件路径是否正确。"
    retryable=true
  fi
fi

if [[ "$failure_category" == "unknown" ]]; then
  hits=$(match_pattern "SyntaxError|TypeError|ReferenceError|compile.error|CompileError")
  if [[ -n "$hits" ]]; then
    failure_category="code_error"
    confidence="medium"
    while IFS= read -r line; do [[ -n "$line" ]] && evidence+=("$line"); done <<< "$hits"
    suggestion="代码错误，建议检查错误信息并修复代码。"
    retryable=false
  fi
fi

# Truncate evidence to max 5 items, each max 200 chars
evidence_json="[]"
count=0
for e in "${evidence[@]+"${evidence[@]}"}"; do
  [[ $count -ge 5 ]] && break
  truncated="${e:0:200}"
  evidence_json=$(echo "$evidence_json" | jq --arg e "$truncated" '. + [$e]')
  ((count++)) || true
done

# ── Build output ─────────────────────────────────────────────────────
diagnosed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq -n \
  --arg label "$LABEL" \
  --arg diagnosedAt "$diagnosed_at" \
  --arg source "$source_name" \
  --arg failureCategory "$failure_category" \
  --arg confidence "$confidence" \
  --argjson evidence "$evidence_json" \
  --arg suggestion "$suggestion" \
  --argjson retryable "$retryable" \
  --argjson totalToolCalls "$total_tool_calls" \
  --argjson totalErrors "$total_errors" \
  --argjson editCount "$edit_count" \
  --argjson uniqueFilesEdited "$unique_files_edited" \
  --argjson durationSeconds "$duration_seconds" \
  '{
    label: $label,
    diagnosedAt: $diagnosedAt,
    source: $source,
    failureCategory: $failureCategory,
    confidence: $confidence,
    evidence: $evidence,
    suggestion: $suggestion,
    retryable: $retryable,
    stats: {
      totalToolCalls: $totalToolCalls,
      totalErrors: $totalErrors,
      editCount: $editCount,
      uniqueFilesEdited: $uniqueFilesEdited,
      durationSeconds: $durationSeconds
    }
  }' | tee "$DIAG_OUT"
