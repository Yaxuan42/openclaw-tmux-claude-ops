---
name: claude-code
description: Trigger Claude Code development tasks in observable tmux sessions with stable startup, progress visibility, and completion callback to OpenClaw. Use when user asks to run coding work via Claude Code and wants to SSH in, monitor progress, and get auto-notified for review after completion.
---

# Claude Code Orchestrator (tmux-first)

Use tmux-based orchestration for long coding tasks to avoid silent hangs and make progress observable.

## Default Project Directory

**新项目默认创建在：**
```
/Users/yingze/Library/Mobile Documents/iCloud~md~obsidian/Documents/Ed_Brain/AI/
```

除非用户明确指定其他目录，否则所有新项目都放在这里。

## Standard workflow

1. Create prompt file (avoid long shell quote issues).
2. Start a dedicated tmux session.
3. Launch `claude --dangerously-skip-permissions` in interactive mode.
4. Paste prompt into Claude.
5. Require callback command in prompt (via wrapper):
   `bash {baseDir}/scripts/wake.sh "..." now`
6. Share socket/session attach command with user.
7. On completion, review diff + lint/build + risk summary.

## Start command

```bash
bash {baseDir}/scripts/start-tmux-task.sh \
  --label "gallery-detail-polish" \
  --workdir "/Users/yaxuan/.openclaw/workspace/work/active/02-gallery-ops" \
  --prompt-file "/Users/yaxuan/Downloads/gallery-website-design-system.md" \
  --task "参考这个修改我当前的画廊官网，注意优先打磨细节和质感，对整体结构展示先不用大改。"
```

## Headless mode (non-interactive)

For well-defined tasks that don't need human intervention, use headless mode for faster execution and structured output:

```bash
bash {baseDir}/scripts/start-tmux-task.sh \
  --label "diagnose-failure" \
  --workdir "/path/to/project" \
  --prompt-file "/tmp/task-prompt.txt" \
  --mode headless
```

Headless mode uses `claude -p --output-format stream-json --verbose`, producing:
- `runs/<label>/stream.jsonl` — complete structured event log (every tool call, result, error)
- Same completion artifacts as interactive mode (report, wake, history)

**When to use headless vs interactive:**
- **Headless**: clear requirements, single-pass implementation, code generation, file edits
- **Interactive**: exploratory work, debugging, tasks needing human approval mid-stream

## Monitor commands

```bash
# attach
bash {baseDir}/scripts/monitor-tmux-task.sh --attach --session <session>

# capture last 200 lines
bash {baseDir}/scripts/monitor-tmux-task.sh --session <session> --lines 200
```

## Task overview

List all running `cc-*` tasks at a glance - useful for "butler-style" summaries.

```bash
# Human-readable one-liner per task
bash {baseDir}/scripts/list-tasks.sh

# Structured JSON array (pipe to jq, feed to OpenClaw, etc.)
bash {baseDir}/scripts/list-tasks.sh --json | jq .
```

Options:
- `--lines <n>` - number of trailing pane lines to capture per task (default 20).
- `--socket <path>` - tmux socket path (default `$TMPDIR/clawdbot-tmux-sockets/clawdbot.sock`).
- `--json` - emit JSON array instead of human table.
- `--target ssh --ssh-host <alias>` - list sessions on a remote host.

Each entry contains: **label**, **session**, **status**, **sessionAlive**, **reportExists**, **reportJsonPath**, **lastLines**, **updatedAt**.

Combine with OpenClaw to generate a periodic butler summary:
```
# In an OpenClaw prompt / cron:
bash {baseDir}/scripts/list-tasks.sh --json | \
  openclaw gateway call summarize-tasks --stdin
```

## Rules

- Prefer interactive Claude in tmux for visibility (not long `claude -p` one-shot for large tasks).
- Always include callback via wrapper `bash {baseDir}/scripts/wake.sh "..." now` in prompt.
- Startup script now uses robust submit (ready-check + multi-Enter retry + execution-state detection) to avoid "prompt pasted but not submitted".
- If no pane output for >2-3 min, inspect and restart session.
- Kill stale Claude processes before restart.
- Always return: session name + attach command + current status.
- For failed tasks, run `diagnose-failure.sh --label <label>` before deciding whether to retry or escalate.

## Event-driven monitoring (automatic)

Both interactive and headless modes automatically set up event-driven monitoring — no manual configuration needed:

### tmux pane-died hook → `on-session-exit.sh`

When a Claude Code session's pane exits (normal or abnormal), `on-session-exit.sh` fires automatically:
- **Normal exit** (report exists): cleans up tmux session, lets wake.sh handle notification.
- **Abnormal exit** (no report): runs `diagnose-failure.sh`, sends Feishu DM alert with diagnosis, records failure in TASK_HISTORY.jsonl, cleans up session.

Pure shell — zero LLM token consumption.

### Background timeout → `timeout-guard.sh`

A background process sleeps for the configured timeout (default 2 hours), then:
- If session is gone → task already ended, do nothing.
- If report exists but session alive → send cleanup reminder via Feishu DM.
- If no report and session still running → run diagnosis, send timeout alert via Feishu DM, record to TASK_HISTORY.

The timeout guard PID is tracked in `runs/<label>/timeout.pid` and auto-killed by `on-session-exit.sh` when the session ends.

### Notification flow

```
Task exits normally:
  → wake.sh → Feishu DM (rich summary) + gateway wake + TASK_HISTORY
  → on-session-exit.sh → sees report exists → cleans up session

Task crashes (no report):
  → on-session-exit.sh → diagnose-failure.sh → Feishu DM alert + TASK_HISTORY → cleanup

Task times out (2h+):
  → timeout-guard.sh → diagnose-failure.sh → Feishu DM alert + TASK_HISTORY
```

## Status check (zero-token)

If wake not received within expected time, check task status before consuming tokens:

```bash
bash {baseDir}/scripts/status-tmux-task.sh --label <label>
```

Output: `STATUS=running|likely_done|stuck|idle|dead|done_session_ended`

- `likely_done` / `done_session_ended` → proceed to completion loop
- `running` → wait
- `stuck` → inspect (attach or capture-pane)
- `dead` → session lost, run complete-tmux-task.sh fallback
- `idle` → Claude may be waiting for input, inspect

## Completion loop (mandatory)

When wake event "Claude Code done (...)" arrives, complete this loop immediately:

1. Acknowledge user within 60s: "已收到完成信号，正在评估改动".
2. Preferred path: read completion report generated by Claude Code task:
   - `runs/<label>/completion-report.json`
3. If report missing, run local fallback immediately:
   - `bash {baseDir}/scripts/complete-tmux-task.sh --label <label> --workdir <workdir>`
4. **Mandatory deep-read**: read full JSON/MD report before replying.
5. Read context before replying:
   - Read completion report file(s) (`runs/<label>/completion-report.json/.md`)
   - Read recent tmux transcript (monitor script) to capture what Claude actually did/failed/tried
   - Incorporate the latest user constraints from current chat
6. Then provide assistant analysis (not a fixed template):
   - what was actually completed
   - what is reliable vs uncertain
   - key risks/tradeoffs in the user's context
   - concrete next-step options
7. Ask explicit decision from user if scope drift exists.

Do not stop at wake-only notification. Wake is trigger, not final delivery.

### Anti-pattern to avoid
- Forbidden: one-line fixed reply after wake without reading transcript + report.
- Forbidden: only relaying "done + report path" without analysis in user context.
- Forbidden: rigid templated output that ignores current conversation context.

## Hard guardrails added

- Prompt now enforces "no wake without report":
  - task must write `runs/<label>/completion-report.json` + `.md`
  - final wake must include `report=<json_path>`
- Recovery command exists for deterministic fallback:
  - `scripts/complete-tmux-task.sh` reproduces evidence and emits structured report
- Delivery SLA remains mandatory:
  - wake received -> ack <= 60s -> report

---

## 闭环反馈系统（新增）

任务执行现在会自动记录历史和执行日志，用于持续优化派活策略。

### 执行日志捕获

启动任务时会自动在后台运行 `capture-execution.sh`，捕获：
- 执行状态变化（thinking → executing → success/error）
- 工具调用成功/失败事件
- 执行时长和错误统计

日志文件：
- `runs/<label>/execution-events.jsonl` — 事件流
- `runs/<label>/execution-summary.json` — 执行摘要

### 任务历史记录

每次任务完成后，`wake.sh` 会自动从 completion report 中解析字段并记录到：
- `{baseDir}/TASK_HISTORY.jsonl`

异常退出和超时也会被 `on-session-exit.sh` 和 `timeout-guard.sh` 自动记录。

记录内容：
```json
{
  "timestamp": "2026-02-17T10:00:00Z",
  "label": "task-name",
  "workdir": "/path/to/project",
  "success": true,
  "failureReason": "",
  "risk": "low",
  "durationSeconds": 300,
  "executionErrors": 0,
  "filesChanged": 5
}
```

### 历史分析

派活前检查历史，获取优化建议：

```bash
# 文本格式（人类可读）
bash {baseDir}/scripts/analyze-history.sh

# JSON 格式（程序处理）
bash {baseDir}/scripts/analyze-history.sh --json

# Markdown 格式（文档输出）
bash {baseDir}/scripts/analyze-history.sh --markdown
```

输出包括：
- 总体成功率统计
- 最近 7 天趋势
- 常见失败模式
- 针对性优化建议

### 失败诊断

当任务失败或卡住时，自动分析原因：

```bash
bash {baseDir}/scripts/diagnose-failure.sh --label <label>
```

支持 4 种数据源（按优先级）：stream.jsonl → execution-events.jsonl → completion-report.json → tmux pane capture

检测 8 种失败模式：
- `edit_loop` — 同一文件反复编辑 >5 次
- `rate_limit` — API 限流 (429)
- `context_overflow` — 上下文窗口溢出
- `timeout` — 执行超时
- `permission` — 权限不足
- `git_conflict` — Git 合并冲突
- `dependency_missing` — 依赖/文件缺失
- `code_error` — 代码语法/类型错误

输出 `runs/<label>/diagnosis.json`，包含 failureCategory、confidence、evidence、suggestion、retryable 等字段。

### 任务巡检（三层防护）

**第一层：事件驱动（实时，零延迟）**
- `on-session-exit.sh`：tmux pane-died hook，session 退出时立即触发。检测异常退出、运行诊断、发送告警。
- `timeout-guard.sh`：后台进程，任务启动时自动创建，超时（默认 2h）后自动诊断并通知。

**第二层：定期巡检（兜底，每 10 分钟）**

```bash
bash {baseDir}/scripts/watchdog.sh
```

检测异常状态：
- `dead` — 会话已不存在
- `stuck` — 超过 30 分钟无输出变化
- `likely_done` — 任务可能已完成但未收到通知
- `long_running` — 运行超过 2 小时

异常任务会自动触发 `diagnose-failure.sh` 分析原因，并通过飞书 DM 通知 Edward。

已配置为 OpenClaw cron job（每 10 分钟），无需手动运行。

**第三层：手动检查**
- `status-tmux-task.sh`：零 token 成本检测单个任务状态
- `list-tasks.sh`：一键列出所有 cc-* 会话状态

### 派活前检查（推荐流程）

在启动新任务前，先检查历史：

```bash
bash {baseDir}/scripts/analyze-history.sh
```

根据分析结果调整任务描述：
- 如果 lint 失败频繁 → 在任务中增加 `npm install` 步骤
- 如果超时频繁 → 拆分为更小的子任务
- 如果成功率 < 80% → 增加任务描述的具体性

### 闭环优化原理

```
派活 → 执行 (interactive 或 headless，可并行多个)
        ↓ 完成                    ↓ 失败/卡住
  wake.sh                    事件驱动监控
  ├ 提取 Claude 完成摘要      ├ on-session-exit.sh (异常退出)
  ├ 飞书 DM 富通知            ├ timeout-guard.sh (超时)
  ├ 记录 TASK_HISTORY         ├ diagnose-failure.sh (自动诊断)
  └ gateway wake             └ 飞书 DM 告警 + TASK_HISTORY
        ↓                            ↓
  OpenClaw 读取 report → 回复飞书   Edward 介入
        ↓ 每周一 9:30
  analyze-history.sh → 周报 → 飞书 DM → 优化策略
```

核心思想（参考胡渊鸣的实践）：
- 给 Agent 提供闭环反馈环境
- 让系统能看到自己做的结果
- 让系统能分析哪里出了问题
- 让系统能据此改进

已验证效果：
- 通知可靠性：100%（飞书 DM 直推 + watchdog 兜底）
- 失败诊断速度：<30 秒（自动分析）
- 并行调度能力：3 个 headless 任务同时完成
