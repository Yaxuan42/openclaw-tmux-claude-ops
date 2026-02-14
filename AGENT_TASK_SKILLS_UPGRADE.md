# Agent 可执行任务文档：P0 Skills 升级

> 给主 Agent（OpenClaw / Claude Code）直接读取并逐步执行。
> 仅包含 P0 三项改造，完成后即可验收。

---

## 前置条件

```bash
# 确认工作目录
cd /Users/yaxuan/.openclaw/workspace/work/tmp/openclaw-tmux-claude-ops

# 确认工具可用
which tmux && which rg && which python3 && which git
```

---

## Task 1：质量门参数化（P0-1）

### 目标
让 `start-tmux-task.sh` 和 `complete-tmux-task.sh` 支持自定义质量门命令，不再硬编码 `npm run lint / build`。

### 步骤

#### 1.1 修改 `skills/claude-code-orchestrator/scripts/start-tmux-task.sh`

在参数解析区（约 line 4-12）新增两个变量：
```bash
LINT_CMD="npm run lint"
BUILD_CMD="npm run build"
```

在 `while` 循环里新增 case：
```bash
--lint-cmd) LINT_CMD="$2"; shift 2 ;;
--build-cmd) BUILD_CMD="$2"; shift 2 ;;
```

在 prompt 模板区（约 line 121-127），把硬编码的 `npm run lint` / `npm run build` 替换为变量：
```
# 原来
4) npm run lint
5) npm run build

# 改为（动态生成）
```

逻辑：
- 如果 `LINT_CMD` 为空字符串，prompt 中不包含 lint 步骤。
- 如果 `BUILD_CMD` 为空字符串，prompt 中不包含 build 步骤。
- 否则使用实际命令。

具体实现：在 `cat > "$PROMPT_TMP" <<EOF` 之前，动态构建质量门文本：

```bash
QUALITY_GATES="1) git status --short
2) git diff --name-only
3) git diff --stat"
GATE_NUM=4

if [[ -n "$LINT_CMD" ]]; then
  QUALITY_GATES="${QUALITY_GATES}
${GATE_NUM}) ${LINT_CMD}"
  GATE_NUM=$((GATE_NUM + 1))
fi

if [[ -n "$BUILD_CMD" ]]; then
  QUALITY_GATES="${QUALITY_GATES}
${GATE_NUM}) ${BUILD_CMD}"
fi
```

然后 prompt 模板中 `A. 完成开发后，立刻执行并收集结果：` 之后用 `$QUALITY_GATES` 替代硬编码。

JSON 模板中的 `lint` / `build` 部分也做相应调整：
- 如果 `LINT_CMD` 为空，JSON 中 `"lint": {"ok": true, "summary": "skipped"}`
- 如果 `BUILD_CMD` 为空，JSON 中 `"build": {"ok": true, "summary": "skipped"}`

#### 1.2 修改 `skills/claude-code-orchestrator/scripts/complete-tmux-task.sh`

同样新增 `--lint-cmd` / `--build-cmd` 参数。

在质量检查区（约 line 39-49），用变量替代硬编码：
```bash
LINT_CMD="${LINT_CMD:-npm run lint}"
BUILD_CMD="${BUILD_CMD:-npm run build}"

lint_ok=true
lint_out="skipped"
if [[ -n "$LINT_CMD" ]]; then
  if ! lint_out="$($LINT_CMD 2>&1)"; then
    lint_ok=false
  fi
fi

build_ok=true
build_out="skipped"
if [[ -n "$BUILD_CMD" ]]; then
  if ! build_out="$($BUILD_CMD 2>&1)"; then
    build_ok=false
  fi
fi
```

#### 1.3 验证

```bash
# 对本仓库（无 npm）测试：传入空字符串跳过 lint/build
bash skills/claude-code-orchestrator/scripts/complete-tmux-task.sh \
  --label test-no-npm \
  --workdir "$(pwd)" \
  --lint-cmd "" \
  --build-cmd "" \
  --no-wake

# 检查报告是否正确生成
cat /tmp/cc-test-no-npm-completion-report.json
# 期望：lint.ok=true, lint.summary="skipped", build.ok=true, build.summary="skipped"
```

---

## Task 2：轻量完成检测（P0-2）

### 目标
新建 `status-tmux-task.sh`，零 token 成本检测任务状态。

### 步骤

#### 2.1 新建 `skills/claude-code-orchestrator/scripts/status-tmux-task.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

LABEL=""
SESSION=""
SOCKET="${TMPDIR:-/tmp}/clawdbot-tmux-sockets/clawdbot.sock"
TARGET="local"
SSH_HOST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --socket) SOCKET="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --ssh-host) SSH_HOST="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

[[ -n "$LABEL" ]] || { echo "Usage: $0 --label <label> [--session cc-xxx] [--socket path]"; exit 1; }
SESSION="${SESSION:-cc-${LABEL}}"
REPORT_JSON="/tmp/${SESSION}-completion-report.json"

# 1. Check if session exists
session_alive=false
if [[ "$TARGET" == "ssh" ]]; then
  ssh -o BatchMode=yes "$SSH_HOST" "tmux -S '$SOCKET' has-session -t '$SESSION'" 2>/dev/null && session_alive=true
else
  tmux -S "$SOCKET" has-session -t "$SESSION" 2>/dev/null && session_alive=true
fi

# 2. Check if report exists
report_exists=false
if [[ -f "$REPORT_JSON" ]]; then
  report_exists=true
fi

# 3. If session dead and no report → dead
if [[ "$session_alive" != true ]]; then
  if [[ "$report_exists" == true ]]; then
    echo "STATUS=done_session_ended"
  else
    echo "STATUS=dead"
  fi
  echo "SESSION_ALIVE=false"
  echo "REPORT_EXISTS=$report_exists"
  exit 0
fi

# 4. If report exists and session alive → likely done (wake may have been sent)
if [[ "$report_exists" == true ]]; then
  echo "STATUS=likely_done"
  echo "SESSION_ALIVE=true"
  echo "REPORT_EXISTS=true"
  exit 0
fi

# 5. Session alive, no report → check pane output for signals
if [[ "$TARGET" == "ssh" ]]; then
  pane="$(ssh -o BatchMode=yes "$SSH_HOST" "tmux -S '$SOCKET' capture-pane -p -J -t '$SESSION':0.0 -S -50" 2>/dev/null || true)"
else
  pane="$(tmux -S "$SOCKET" capture-pane -p -J -t "$SESSION":0.0 -S -50 2>/dev/null || true)"
fi

# Detect completion signals in pane output
if echo "$pane" | rg -q "REPORT_JSON=|WAKE_SENT=|Co-Authored-By:|completion-report"; then
  echo "STATUS=likely_done"
elif echo "$pane" | rg -q "✗|Error:|FAILED|fatal:"; then
  echo "STATUS=stuck"
elif echo "$pane" | rg -q "Envisioning|Thinking|Running|✽|Mustering|Read [0-9]+ file|Bash\(|Edit\(|Write\("; then
  echo "STATUS=running"
elif echo "$pane" | rg -q "^❯"; then
  echo "STATUS=idle"
else
  echo "STATUS=running"
fi

echo "SESSION_ALIVE=true"
echo "REPORT_EXISTS=false"
```

#### 2.2 设置执行权限

```bash
chmod +x skills/claude-code-orchestrator/scripts/status-tmux-task.sh
```

#### 2.3 更新 SKILL.md

在 "Completion loop (mandatory)" 之前新增 "Pre-check" 步骤：

```markdown
## Status check (zero-token)

If wake not received within expected time, check task status before consuming tokens:

\`\`\`bash
bash {baseDir}/scripts/status-tmux-task.sh --label <label>
\`\`\`

Output: `STATUS=running|likely_done|stuck|idle|dead|done_session_ended`

- `likely_done` / `done_session_ended` → proceed to completion loop
- `running` → wait
- `stuck` → inspect (attach or capture-pane)
- `dead` → session lost, run complete-tmux-task.sh fallback
- `idle` → Claude may be waiting for input, inspect
```

#### 2.4 验证

```bash
# 启动一个虚拟 session 测试
tmux -S "${TMPDIR:-/tmp}/clawdbot-tmux-sockets/clawdbot.sock" new -d -s cc-status-test -n shell
bash skills/claude-code-orchestrator/scripts/status-tmux-task.sh --label status-test
# 期望：STATUS=idle 或 STATUS=running

# 清理
tmux -S "${TMPDIR:-/tmp}/clawdbot-tmux-sockets/clawdbot.sock" kill-session -t cc-status-test
```

---

## Task 3：Bootstrap 脚本（P0-3）

### 目标
新建 `scripts/bootstrap.sh`，clone 后一键检查环境。

### 步骤

#### 3.1 新建 `skills/claude-code-orchestrator/scripts/bootstrap.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "=== OpenClaw Claude Code Orchestrator — Bootstrap ==="
echo ""

errors=0

# Check required tools
for tool in tmux claude rg python3 git; do
  if command -v "$tool" >/dev/null 2>&1; then
    version="$("$tool" --version 2>/dev/null | head -1 || echo "ok")"
    echo "  [OK] $tool → $version"
  else
    echo "  [MISSING] $tool — please install before using the orchestrator"
    errors=$((errors + 1))
  fi
done

echo ""

# Check socket directory
SOCKET_DIR="${TMPDIR:-/tmp}/clawdbot-tmux-sockets"
if mkdir -p "$SOCKET_DIR" 2>/dev/null; then
  echo "  [OK] Socket dir writable: $SOCKET_DIR"
else
  echo "  [FAIL] Cannot create socket dir: $SOCKET_DIR"
  errors=$((errors + 1))
fi

# Check scripts exist and are executable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for script in start-tmux-task.sh monitor-tmux-task.sh complete-tmux-task.sh wake.sh status-tmux-task.sh; do
  if [[ -x "$SCRIPT_DIR/$script" ]]; then
    echo "  [OK] $script executable"
  elif [[ -f "$SCRIPT_DIR/$script" ]]; then
    echo "  [WARN] $script exists but not executable — run: chmod +x $SCRIPT_DIR/$script"
  else
    echo "  [SKIP] $script not found (may not be created yet)"
  fi
done

echo ""

if [[ "$errors" -gt 0 ]]; then
  echo "RESULT: $errors issue(s) found. Fix them before running tasks."
  exit 1
fi

echo "RESULT: All checks passed."

# Dry-run: create and destroy a tmux session
if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "=== Dry-run: testing tmux session lifecycle ==="
  SOCKET="$SOCKET_DIR/clawdbot.sock"
  TEST_SESSION="cc-bootstrap-test"

  tmux -S "$SOCKET" new -d -s "$TEST_SESSION" -n shell
  echo "  [OK] Created session: $TEST_SESSION"

  if tmux -S "$SOCKET" has-session -t "$TEST_SESSION" 2>/dev/null; then
    echo "  [OK] Session exists"
  else
    echo "  [FAIL] Session not found after creation"
    exit 1
  fi

  tmux -S "$SOCKET" kill-session -t "$TEST_SESSION"
  echo "  [OK] Destroyed session: $TEST_SESSION"
  echo ""
  echo "DRY_RUN: PASSED — tmux session lifecycle works."
fi
```

#### 3.2 设置执行权限

```bash
chmod +x skills/claude-code-orchestrator/scripts/bootstrap.sh
```

#### 3.3 更新 README.md

在"快捷入口"区域之后新增：

```markdown
## Quick Start

```bash
# 1. Clone
git clone https://github.com/Yaxuan42/openclaw-tmux-claude-ops.git
cd openclaw-tmux-claude-ops

# 2. Check environment
bash skills/claude-code-orchestrator/scripts/bootstrap.sh

# 3. Verify tmux lifecycle (optional)
bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run
```
```

#### 3.4 验证

```bash
bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run
# 期望：All checks passed + DRY_RUN: PASSED
```

---

## 最终验收（三项全部完成后）

```bash
cd /Users/yaxuan/.openclaw/workspace/work/tmp/openclaw-tmux-claude-ops

# 1. 所有新脚本通过 shellcheck（如有）
which shellcheck && shellcheck skills/claude-code-orchestrator/scripts/*.sh

# 2. bootstrap 通过
bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run

# 3. Git 状态干净（无意外变更）
git status --short
git diff --name-only
git diff --stat

# 4. 文档同步
# 确认以下文件已更新：
# - SKILL.md（新增 status check 段落）
# - README.md（新增 Quick Start）
# - AGENT_RUNBOOK.md（如需要）
```

---

## 注意事项

- 所有修改都在 `skills/claude-code-orchestrator/` 范围内，不影响 OpenClaw 核心。
- 向后兼容：不传新参数时保持原有行为。
- 如果 `shellcheck` 报告问题，修复后再提交。
- 完成后按仓库惯例生成 completion report。
