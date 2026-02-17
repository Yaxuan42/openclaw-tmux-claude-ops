#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=""
PHASE=""
ITERATION=""
MODE="interactive"
LINT_CMD=""
BUILD_CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --iteration) ITERATION="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --lint-cmd) LINT_CMD="$2"; shift 2 ;;
    --build-cmd) BUILD_CMD="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$PROJECT_DIR" && -n "$PHASE" ]] || {
  echo "Usage: $0 --project-dir <dir> --phase <1|2|3|4> [--iteration <N>] [--mode interactive|headless] [--lint-cmd '...'] [--build-cmd '...']"
  exit 1
}

[[ "$PHASE" =~ ^[1234]$ ]] || {
  echo "ERROR: --phase must be 1, 2, 3, or 4"
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_DIR="$SCRIPT_DIR/../../claude-code-orchestrator/scripts"
START_TASK="$ORCH_DIR/start-tmux-task.sh"

if [[ ! -f "$START_TASK" ]]; then
  echo "ERROR: start-tmux-task.sh not found at $START_TASK"
  echo "The claude-code-orchestrator skill must be installed."
  exit 1
fi

STATUS="$PROJECT_DIR/docs/STATUS.md"
LESSONS="$PROJECT_DIR/docs/LESSONS_LEARNED.md"
PROCESS_GUIDE="$SCRIPT_DIR/../references/PROCESS_GUIDE.md"
WEB_GUIDE="$SCRIPT_DIR/../references/WEB_PROJECT_GUIDE.md"

# Validate STATUS.md exists
if [[ ! -f "$STATUS" ]]; then
  echo "ERROR: $STATUS not found. Run init-project.sh first."
  exit 1
fi

# Extract project name from STATUS.md (first heading)
PROJECT_NAME=$(head -1 "$STATUS" | sed 's/^# //' | sed 's/ —.*//')

# Validate current phase matches requested phase
current_phase=$(rg "^\\*\\*Phase [0-9]" "$STATUS" 2>/dev/null | head -1 | sed 's/.*Phase \([0-9]\).*/\1/' || echo "")
if [[ -n "$current_phase" && "$current_phase" != "$PHASE" ]]; then
  echo "WARN: STATUS.md shows Phase $current_phase but requesting Phase $PHASE"
  echo "Continue anyway? (STATUS.md will not be auto-updated until advance-phase.sh)"
fi

# Build label
case "$PHASE" in
  1) LABEL="${PROJECT_NAME}-req" ; PHASE_NAME="需求分析" ;;
  2) LABEL="${PROJECT_NAME}-design" ; PHASE_NAME="技术设计" ;;
  3)
    ITERATION="${ITERATION:-1}"
    LABEL="${PROJECT_NAME}-dev-iter-${ITERATION}"
    PHASE_NAME="开发迭代 #${ITERATION}"
    ;;
  4) LABEL="${PROJECT_NAME}-deliver" ; PHASE_NAME="交付验收" ;;
esac

# Sanitize label
LABEL="$(echo "$LABEL" | sed 's/[^a-zA-Z0-9_-]/-/g' | tr '[:upper:]' '[:lower:]')"

# Prompt file goes into orchestrator runs/ directory
ORCH_RUNS_DIR="$SCRIPT_DIR/../../claude-code-orchestrator/runs/$LABEL"
mkdir -p "$ORCH_RUNS_DIR"
PROMPT_FILE="$ORCH_RUNS_DIR/prompt.txt"

# Read recent lessons (last 5)
recent_lessons=""
if [[ -f "$LESSONS" ]]; then
  recent_lessons=$(rg "^\| [0-9]{4}-" "$LESSONS" 2>/dev/null | tail -5 || true)
fi

# Detect project type
is_web=false
if rg -q "web" "$STATUS" 2>/dev/null || [[ -f "$PROJECT_DIR/docs/API_CONTRACT.md" ]]; then
  is_web=true
fi

# Build prompt based on phase
case "$PHASE" in
  1)
    cat > "$PROMPT_FILE" <<PROMPT
# Phase 1: 需求分析 — ${PROJECT_NAME}

## 任务目标
完善项目的需求文档，产出高质量的 MRD.md 和 PRD.md。

## 方法论参考
请先阅读 $PROCESS_GUIDE 的 "Phase 1: 需求分析" 部分，理解好 PRD 的标准。

## 当前状态
$(cat "$STATUS")

## 交付物
1. 编辑 docs/MRD.md — 明确市场问题、目标用户、业务目标、成功指标、约束
2. 编辑 docs/PRD.md — 编写 User Stories (US-xxx)、功能/非功能需求、Scope、Success Criteria
3. 更新 docs/STATUS.md 的 Iteration Log

## 质量标准
- 每个需求可测试（能对应测试用例）
- 无歧义（用"必须"/"当...则..."替代"应该"/"可能"）
- 有边界（In Scope / Out of Scope 明确）
- 可度量（指标有具体数字）

$(if [[ -n "$recent_lessons" ]]; then
echo "## 历史经验（参考）"
echo "$recent_lessons"
fi)
PROMPT
    TASK="Phase 1 需求分析：完善 MRD.md 和 PRD.md"
    ;;

  2)
    cat > "$PROMPT_FILE" <<PROMPT
# Phase 2: 技术设计 — ${PROJECT_NAME}

## 任务目标
基于 PRD.md 编写技术设计文档、测试计划$(if [[ "$is_web" == true ]]; then echo "、API 契约"; fi)。

## 方法论参考
请先阅读 $PROCESS_GUIDE 的 "Phase 2: 技术设计" 部分。
$(if [[ "$is_web" == true ]]; then echo "Web 项目请同时参考 $WEB_GUIDE"; fi)

## 当前状态
$(cat "$STATUS")

## PRD 内容
$(cat "$PROJECT_DIR/docs/PRD.md" 2>/dev/null || echo "PRD.md not available")

## 交付物
1. 编辑 docs/DESIGN.md — Architecture、Data Model、API Design、Error Handling、Security、Tech Stack
2. 编辑 docs/TEST_PLAN.md — Test Strategy、Test Cases (TC-xxx)、Coverage Targets、TDD Workflow
$(if [[ "$is_web" == true ]]; then echo "3. 编辑 docs/API_CONTRACT.md — Base URL、Auth、Response Format、Endpoints、Error Codes、TS Interfaces
4. 更新 docs/STATUS.md 的 Iteration Log"; else echo "3. 更新 docs/STATUS.md 的 Iteration Log"; fi)

$(if [[ -n "$recent_lessons" ]]; then
echo "## 历史经验（参考）"
echo "$recent_lessons"
fi)
PROMPT
    TASK="Phase 2 技术设计：编写 DESIGN.md 和 TEST_PLAN.md"
    ;;

  3)
    cat > "$PROMPT_FILE" <<PROMPT
# Phase 3: 开发迭代 #${ITERATION} — ${PROJECT_NAME}

## 任务目标
按照 DESIGN.md 和 TEST_PLAN.md 进行 TDD 开发迭代。

## 方法论参考
请先阅读 $PROCESS_GUIDE 的 "Phase 3: 开发迭代" 部分，遵循 TDD 工作流。

## 当前状态
$(cat "$STATUS")

## 设计文档
$(cat "$PROJECT_DIR/docs/DESIGN.md" 2>/dev/null || echo "DESIGN.md not available")

## 测试计划
$(cat "$PROJECT_DIR/docs/TEST_PLAN.md" 2>/dev/null || echo "TEST_PLAN.md not available")

## TDD 工作流
1. Red: 从 TEST_PLAN.md 选取测试用例，写失败测试
2. Green: 写最少代码让测试通过
3. Refactor: 重构代码，保持测试绿色

## Spec 变更协议
如果开发中发现 spec 不合理：
1. 在 docs/CHANGELOG.md 中用 [spec-change] 标签记录
2. 在 docs/STATUS.md 的 Key Decisions 表格记录决策
3. 继续开发，不阻塞

## 交付物
1. src/ 下的实现代码
2. tests/ 下的测试代码
3. 更新 docs/CHANGELOG.md
4. 更新 docs/STATUS.md 的 Iteration Log
5. 所有测试通过、lint/build 通过
6. git commit

$(if [[ -n "$recent_lessons" ]]; then
echo "## 历史经验（参考）"
echo "$recent_lessons"
fi)
PROMPT
    TASK="Phase 3 开发迭代 #${ITERATION}：TDD 实现"
    ;;

  4)
    cat > "$PROMPT_FILE" <<PROMPT
# Phase 4: 交付验收 — ${PROJECT_NAME}

## 任务目标
确保所有产出物完整、文档更新、知识沉淀。

## 方法论参考
请先阅读 $PROCESS_GUIDE 的 "Phase 4: 交付验收" 部分。

## 当前状态
$(cat "$STATUS")

## 交付检查清单
1. 代码完整性
   - [ ] 所有功能已实现
   - [ ] 所有测试通过
   - [ ] lint/build 通过
   - [ ] 无未提交的变更

2. 文档更新
   - [ ] docs/CHANGELOG.md 有实质内容
   - [ ] docs/STATUS.md 标记为 Phase 4
   - [ ] docs/LESSONS_LEARNED.md 已更新
   - [ ] docs/DESIGN.md 反映最终实现

3. 知识沉淀
   - [ ] 重要经验写入 docs/LESSONS_LEARNED.md
   - [ ] 回顾整个开发过程，记录值得注意的经验

## 交付物
1. 更新 docs/CHANGELOG.md（完整变更日志）
2. 更新 docs/LESSONS_LEARNED.md（至少 1 条经验）
3. 更新 docs/STATUS.md（迭代日志、标记 Phase 4）
4. 确保所有文档反映最终实现
5. git commit

$(if [[ -n "$recent_lessons" ]]; then
echo "## 历史经验（参考）"
echo "$recent_lessons"
fi)
PROMPT
    TASK="Phase 4 交付验收：文档更新和知识沉淀"
    ;;
esac

# Build start-tmux-task.sh arguments
START_ARGS=(
  --label "$LABEL"
  --workdir "$PROJECT_DIR"
  --prompt-file "$PROMPT_FILE"
  --task "$TASK"
  --mode "$MODE"
)

if [[ -n "$LINT_CMD" ]]; then
  START_ARGS+=(--lint-cmd "$LINT_CMD")
fi

if [[ -n "$BUILD_CMD" ]]; then
  START_ARGS+=(--build-cmd "$BUILD_CMD")
fi

echo "Dispatching: Phase $PHASE ($PHASE_NAME)"
echo "  Project: $PROJECT_NAME"
echo "  Label: $LABEL"
echo "  Mode: $MODE"
echo "  Prompt: $PROMPT_FILE"
echo ""

# Launch via orchestrator
bash "$START_TASK" "${START_ARGS[@]}"
