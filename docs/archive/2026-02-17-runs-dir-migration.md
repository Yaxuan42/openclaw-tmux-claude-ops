# Orchestrator 临时文件迁移：/tmp → runs/ 目录

**日期**: 2026-02-17
**范围**: 10 个脚本 + 2 个文档
**状态**: 已完成

## 背景与问题

此前每个 orchestrator 任务在 `/tmp` 目录下产生约 10 个文件（prompt、report、stream、logs、pid 等），存在以下问题：

| 问题 | 影响 |
|------|------|
| `/tmp` 堆积 | 每个任务 ~10 个文件，无清理机制，长期运行后残留大量文件 |
| 重启后丢失 | macOS 会自动清理 `/tmp`，任务产物在重启后无法追溯 |
| 散落无序 | 所有任务的文件平铺在 `/tmp`，难以按任务归档查看 |
| 硬编码分散 | 12 个脚本各自独立硬编码 `/tmp/cc-<label>-*` 路径，无中心定义 |

## 方案

在项目内创建 `skills/claude-code-orchestrator/runs/<label>/` 存放每个任务的所有产物。

### 新目录结构

```
skills/claude-code-orchestrator/
├── runs/                          ← 新增
│   ├── .gitignore                 ← 忽略所有运行产物（* + !.gitignore）
│   └── <label>/                   ← 每个任务一个目录（自动创建）
│       ├── prompt.txt             ← 任务 prompt
│       ├── stream.jsonl           ← headless 模式的 stream-json 输出
│       ├── completion-report.json ← Claude 生成的完成报告（JSON）
│       ├── completion-report.md   ← Claude 生成的完成报告（Markdown）
│       ├── execution-events.jsonl ← 执行事件流（capture-execution.sh 采样）
│       ├── execution-summary.json ← 执行摘要统计
│       ├── diagnosis.json         ← 失败诊断结果
│       ├── on-exit.log            ← pane-died hook 日志
│       ├── timeout.log            ← timeout-guard 日志
│       ├── capture.log            ← capture-execution 日志
│       ├── timeout.pid            ← timeout-guard 进程 PID
│       └── capture.pid            ← capture-execution 进程 PID
```

### 保留在 /tmp 的文件

以下文件因其全局性质或 SSH 远程需求，仍保留在 `/tmp`：

| 文件 | 原因 |
|------|------|
| `clawdbot-tmux-sockets/` | tmux socket，全局共享 |
| `cc-watchdog-state.json` | watchdog 全局状态，跨任务 |
| `cc-<label>-reference-*` | SSH 远程机器上的临时文件，需在 `/tmp` 以便 scp |

## 核心改动

### 统一路径推导模式

每个脚本统一使用 `RUNS_DIR` 推导路径：

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNS_DIR="$SCRIPT_DIR/../runs/$LABEL"
mkdir -p "$RUNS_DIR"
```

### 路径对照表（旧 → 新）

| 旧路径 | 新路径 |
|--------|--------|
| `/tmp/cc-<label>-prompt.txt` | `runs/<label>/prompt.txt` |
| `/tmp/cc-<label>-stream.jsonl` | `runs/<label>/stream.jsonl` |
| `/tmp/cc-<label>-completion-report.json` | `runs/<label>/completion-report.json` |
| `/tmp/cc-<label>-completion-report.md` | `runs/<label>/completion-report.md` |
| `/tmp/cc-<label>-execution-events.jsonl` | `runs/<label>/execution-events.jsonl` |
| `/tmp/cc-<label>-execution-summary.json` | `runs/<label>/execution-summary.json` |
| `/tmp/cc-<label>-diagnosis.json` | `runs/<label>/diagnosis.json` |
| `/tmp/cc-<label>-on-exit.log` | `runs/<label>/on-exit.log` |
| `/tmp/cc-<label>-timeout.log` | `runs/<label>/timeout.log` |
| `/tmp/cc-<label>-capture.log` | `runs/<label>/capture.log` |
| `/tmp/cc-<label>-timeout.pid` | `runs/<label>/timeout.pid` |
| `/tmp/cc-<label>-capture.pid` | `runs/<label>/capture.pid` |

## 修改文件清单

### 脚本（10 个，1 个不改）

| # | 脚本 | 改动说明 |
|---|------|----------|
| 1 | `scripts/start-tmux-task.sh` | 主入口。定义 `RUNS_DIR`；`PROMPT_TMP`/`REPORT_JSON`/`REPORT_MD`/`STREAM_LOG` + timeout.log/capture.log/capture.pid 全改到 `$RUNS_DIR/`；调用 `capture-execution.sh` 时传入 `--label` |
| 2 | `scripts/capture-execution.sh` | 新增 `--label` 参数（向后兼容：无 `--label` 时从 `SESSION` 推导）；`LOG_FILE`/`SUMMARY_FILE` 改用 `$RUNS_DIR/` |
| 3 | `scripts/on-session-exit.sh` | 新增 `RUNS_DIR` 推导；`REPORT_JSON`/`LOG_FILE`/`TIMEOUT_PID_FILE`/`CAPTURE_PID_FILE` + 通知消息中的日志路径全改 |
| 4 | `scripts/timeout-guard.sh` | 新增 `RUNS_DIR`；`REPORT_JSON`/`PID_FILE` 改 |
| 5 | `scripts/complete-tmux-task.sh` | 新增 `RUNS_DIR`；`REPORT_JSON`/`REPORT_MD`/`EXECUTION_LOG`/`EXECUTION_SUMMARY` 改 |
| 6 | `scripts/status-tmux-task.sh` | 新增 `RUNS_DIR`；`REPORT_JSON` 改 |
| 7 | `scripts/diagnose-failure.sh` | 新增 `RUNS_DIR`；`STREAM_LOG`/`EVENTS_LOG`/`REPORT_JSON`/`DIAG_OUT` 改；更新文件头注释 |
| 8 | `scripts/wake.sh` | 从 report 路径 dirname 推导 `_runs_dir`（`_runs_dir="$(dirname "$REPORT_PATH")"`）；`_exec_summary`/`_stream_log` 改用 `$_runs_dir/` |
| 9 | `scripts/list-tasks.sh` | `report_json_path` 改用 `$SCRIPT_DIR/../runs/${label}/completion-report.json` |
| 10 | `scripts/watchdog.sh` | **不改** — `cc-watchdog-state.json` 是全局状态，保留在 `/tmp` |

### 文档（2 个）

| 文件 | 改动说明 |
|------|----------|
| `CLAUDE.md` | 更新 File Conventions（描述新的 runs/ 结构）和 Shell Script Conventions（新增 `RUNS_DIR` 约定） |
| `SKILL.md` | 更新所有 `/tmp/cc-<label>-*` 路径引用为 `runs/<label>/` |

### 新增文件（1 个）

| 文件 | 说明 |
|------|------|
| `skills/claude-code-orchestrator/runs/.gitignore` | 内容：`*` + `!.gitignore`，确保运行产物不被 git 跟踪 |

## capture-execution.sh 特殊处理

此脚本此前不接收 `--label` 参数，无法独立推导 `RUNS_DIR`。改动：

1. 新增 `--label` 参数到 arg parser
2. 向后兼容：若未传 `--label`，从 `SESSION` 推导（`LABEL="${SESSION#cc-}"`）
3. `start-tmux-task.sh` 调用 capture 时新增 `--label "$LABEL"` 传参

## wake.sh 特殊处理

`wake.sh` 通过位置参数接收文本 `TEXT`，其中包含 `report=<path>` 片段。路径推导方式：

```bash
# 从 report 路径直接推导 runs dir（无需 LABEL）
_runs_dir="$(dirname "$REPORT_PATH")"
_exec_summary="$_runs_dir/execution-summary.json"
_stream_log="$_runs_dir/stream.jsonl"
```

这种方式使 `wake.sh` 自动适配新路径，无需硬编码 `RUNS_DIR` 推导逻辑。

## 验证结果

### 1. bootstrap dry-run

```
$ bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run
  [OK] tmux → ok
  [OK] claude → 2.1.44 (Claude Code)
  [OK] rg → ripgrep 14.1.1
  [OK] python3 → Python 3.9.6
  [OK] git → git version 2.50.1
  ...
DRY_RUN: PASSED
```

### 2. 语法检查（所有 9 个修改的脚本）

```
OK: start-tmux-task.sh
OK: wake.sh
OK: on-session-exit.sh
OK: timeout-guard.sh
OK: complete-tmux-task.sh
OK: status-tmux-task.sh
OK: diagnose-failure.sh
OK: capture-execution.sh
OK: list-tasks.sh
```

### 3. 残留 /tmp 引用检查

修改后仅保留 3 处合理的 `/tmp` 引用：

| 文件 | 引用 | 原因 |
|------|------|------|
| `watchdog.sh` | `/tmp/cc-watchdog-state.json` | 全局状态，不属于单个任务 |
| `start-tmux-task.sh` | `/tmp/${SESSION}-reference-*` | SSH 远程机器临时文件 |
| `wake.sh` | 注释中描述旧格式 | 仅为注释，实际 regex 是路径无关的 |

## 兼容性说明

- **新任务**: 自动在 `runs/<label>/` 下创建所有文件
- **旧任务残留**: `/tmp` 中的旧文件不会被自动清理，但不影响新任务运行。可手动清理：`rm /tmp/cc-*`
- **SSH 模式**: SSH 远程文件仍在 `/tmp`（远程机器），本地产物在 `runs/`
- **watchdog.sh**: 全局状态文件不受影响，继续使用 `/tmp`
- **TASK_HISTORY.jsonl**: 位置不变（`skills/claude-code-orchestrator/TASK_HISTORY.jsonl`）

## 未来可选优化

- 添加 `runs/` 清理脚本（按天数或任务数自动归档/删除旧 runs）
- 在 `list-tasks.sh` 中增加对已结束任务的 runs/ 目录扫描（当前只列出活跃 tmux session）
- 将 `AGENT_RUNBOOK.md` 中的旧路径引用同步更新
