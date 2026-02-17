#!/usr/bin/env bash
# analyze-history.sh
# 分析任务历史，生成统计报告和优化建议
# 用于闭环反馈学习

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY_FILE="${1:-$SCRIPT_DIR/../TASK_HISTORY.jsonl}"
OUTPUT_FORMAT="text"  # text | json | markdown

while [[ $# -gt 0 ]]; do
  case "$1" in
    --history) HISTORY_FILE="$2"; shift 2 ;;
    --format) OUTPUT_FORMAT="$2"; shift 2 ;;
    --json) OUTPUT_FORMAT="json"; shift ;;
    --markdown) OUTPUT_FORMAT="markdown"; shift ;;
    *) 
      if [[ -f "$1" ]]; then
        HISTORY_FILE="$1"
        shift
      else
        echo "Unknown arg: $1"; exit 1
      fi
      ;;
  esac
done

# 如果历史文件不存在，创建空文件
if [[ ! -f "$HISTORY_FILE" ]]; then
  echo "[]" | jq -c '.[]' > "$HISTORY_FILE" 2>/dev/null || touch "$HISTORY_FILE"
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    echo '{"total":0,"success":0,"failed":0,"rate":0,"patterns":[],"recommendations":["No history yet"]}'
  else
    echo "No task history found. History will be recorded after first task completion."
  fi
  exit 0
fi

# 统计基础数据
total=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
if [[ "$total" -eq 0 ]]; then
  if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    echo '{"total":0,"success":0,"failed":0,"rate":0,"patterns":[],"recommendations":["No history yet"]}'
  else
    echo "No task history recorded yet."
  fi
  exit 0
fi

success=$(grep -c '"success":true' "$HISTORY_FILE" 2>/dev/null || echo "0")
failed=$((total - success))
rate=$(echo "scale=1; $success * 100 / $total" | bc 2>/dev/null || echo "0")

# 分析失败模式
failure_patterns=$(grep '"success":false' "$HISTORY_FILE" 2>/dev/null | \
  jq -r '.failureReason // "unknown"' 2>/dev/null | \
  sort | uniq -c | sort -rn | head -5 || echo "")

# 分析成功模式（按 workdir 分组）
success_by_project=$(grep '"success":true' "$HISTORY_FILE" 2>/dev/null | \
  jq -r '.workdir' 2>/dev/null | \
  xargs -I{} basename {} 2>/dev/null | \
  sort | uniq -c | sort -rn | head -5 || echo "")

# 最近 7 天趋势
week_ago=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d 2>/dev/null || echo "")
if [[ -n "$week_ago" ]]; then
  recent_total=$(jq -r --arg date "$week_ago" 'select(.timestamp > $date)' "$HISTORY_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  recent_success=$(jq -r --arg date "$week_ago" 'select(.timestamp > $date and .success == true)' "$HISTORY_FILE" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [[ "$recent_total" -gt 0 ]]; then
    recent_rate=$(echo "scale=1; $recent_success * 100 / $recent_total" | bc 2>/dev/null || echo "0")
  else
    recent_rate="N/A"
  fi
else
  recent_total=0
  recent_success=0
  recent_rate="N/A"
fi

# 生成建议
recommendations=()

if (( $(echo "$rate < 50" | bc -l 2>/dev/null || echo "0") )); then
  recommendations+=("🔴 成功率过低，建议：拆分任务为更小单元，增加任务描述的具体性")
elif (( $(echo "$rate < 80" | bc -l 2>/dev/null || echo "0") )); then
  recommendations+=("🟡 成功率有提升空间，建议：检查常见失败模式并针对性优化")
else
  recommendations+=("🟢 成功率良好，继续保持当前策略")
fi

if echo "$failure_patterns" | grep -qi "lint\|eslint\|tsc"; then
  recommendations+=("💡 Lint 失败频繁：在任务前增加 'npm install' 步骤")
fi

if echo "$failure_patterns" | grep -qi "timeout\|stuck\|无响应"; then
  recommendations+=("💡 超时问题：考虑拆分大任务，或增加中间检查点")
fi

if echo "$failure_patterns" | grep -qi "not found\|找不到\|missing"; then
  recommendations+=("💡 文件/依赖缺失：在任务描述中明确文件路径和依赖要求")
fi

# 输出结果
case "$OUTPUT_FORMAT" in
  json)
    jq -n \
      --argjson total "$total" \
      --argjson success "$success" \
      --argjson failed "$failed" \
      --arg rate "$rate" \
      --argjson recent_total "$recent_total" \
      --arg recent_rate "$recent_rate" \
      --arg failure_patterns "$failure_patterns" \
      --arg recommendations "$(printf '%s\n' "${recommendations[@]}")" \
      '{
        total: $total,
        success: $success,
        failed: $failed,
        successRate: $rate,
        recentWeek: {
          total: $recent_total,
          rate: $recent_rate
        },
        failurePatterns: ($failure_patterns | split("\n") | map(select(. != ""))),
        recommendations: ($recommendations | split("\n") | map(select(. != "")))
      }'
    ;;
    
  markdown)
    cat <<EOF
# Claude Code 任务历史分析

## 📊 总体统计
| 指标 | 数值 |
|------|------|
| 总任务数 | $total |
| 成功 | $success |
| 失败 | $failed |
| 成功率 | ${rate}% |

## 📈 最近 7 天
- 任务数: $recent_total
- 成功率: ${recent_rate}%

## ❌ 常见失败模式
\`\`\`
$failure_patterns
\`\`\`

## ✅ 成功项目分布
\`\`\`
$success_by_project
\`\`\`

## 💡 优化建议
$(printf '%s\n' "${recommendations[@]}" | sed 's/^/- /')

---
*生成时间: $(date '+%Y-%m-%d %H:%M:%S')*
EOF
    ;;
    
  *)  # text
    echo "═══════════════════════════════════════════"
    echo "       Claude Code 任务历史分析"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "📊 总体统计"
    echo "   总任务数: $total"
    echo "   成功: $success | 失败: $failed"
    echo "   成功率: ${rate}%"
    echo ""
    echo "📈 最近 7 天"
    echo "   任务数: $recent_total"
    echo "   成功率: ${recent_rate}%"
    echo ""
    if [[ -n "$failure_patterns" ]]; then
      echo "❌ 常见失败模式 (次数 | 原因)"
      echo "$failure_patterns" | while read -r line; do
        [[ -n "$line" ]] && echo "   $line"
      done
      echo ""
    fi
    echo "💡 优化建议"
    printf '%s\n' "${recommendations[@]}" | while read -r rec; do
      echo "   $rec"
    done
    echo ""
    echo "═══════════════════════════════════════════"
    ;;
esac
