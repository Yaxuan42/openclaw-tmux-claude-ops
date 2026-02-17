# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

OpenClaw tmux-Claude Code Orchestrator — a shell-script system for dispatching, monitoring, and completing Claude Code AI coding tasks in tmux sessions. It bridges an OpenClaw agent (Mac mini) with Claude Code CLI processes, supporting local and SSH-remote execution with Feishu (Lark) DM notifications.

## Commands

```bash
# Environment check
bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run

# Launch a task (the single entry point — never call claude directly)
bash skills/claude-code-orchestrator/scripts/start-tmux-task.sh \
  --label "<label>" --workdir "<dir>" --prompt-file "<file>" --task "<text>" \
  [--mode interactive|headless] [--lint-cmd "..." --build-cmd "..."]

# Check task status (zero-token, pure shell)
bash skills/claude-code-orchestrator/scripts/status-tmux-task.sh --label <label>

# List all tasks
bash skills/claude-code-orchestrator/scripts/list-tasks.sh [--json]

# Diagnose a failed task
bash skills/claude-code-orchestrator/scripts/diagnose-failure.sh --label <label>

# View task output / attach
bash skills/claude-code-orchestrator/scripts/monitor-tmux-task.sh --session cc-<label> --lines 200
bash skills/claude-code-orchestrator/scripts/monitor-tmux-task.sh --attach --session cc-<label>

# Analyze task history
bash skills/claude-code-orchestrator/scripts/analyze-history.sh [--json|--markdown]

# Verify file integrity
shasum -a 256 -c MANIFEST.sha256
```

Required tools: `tmux`, `claude` (Claude Code CLI), `rg` (ripgrep), `python3`, `git`, `jq`, `openclaw`.

## Architecture

### Execution Flow

```
start-tmux-task.sh (single entry point)
  → Creates tmux session cc-<label>
  → Mode: interactive (Claude TUI + capture sampling)
       or headless (claude -p --output-format stream-json)
  → Registers pane-died hook → on-session-exit.sh
  → Launches timeout-guard.sh (background, 2h default)
  → Launches capture-execution.sh (interactive mode only, 15s sampling)

Task completes → wake.sh
  → Extracts Claude's summary from stream.jsonl (headless) or report notes
  → Feishu DM direct push + gateway wake + TASK_HISTORY.jsonl

Task crashes (no report) → on-session-exit.sh (pane-died hook)
  → diagnose-failure.sh → Feishu DM alert + TASK_HISTORY.jsonl

Task times out → timeout-guard.sh
  → diagnose-failure.sh → Feishu DM alert + TASK_HISTORY.jsonl
```

### Three-Layer Monitoring

1. **Event-driven** (instant): tmux `pane-died` hook → `on-session-exit.sh`
2. **Background timeout** (2h): `timeout-guard.sh`
3. **Periodic cron** (10 min): `watchdog.sh`

### File Conventions

- Sessions: `cc-<label>`
- Task run artifacts: `skills/claude-code-orchestrator/runs/<label>/` — each task gets its own directory containing `prompt.txt`, `stream.jsonl`, `completion-report.json`, `completion-report.md`, `execution-events.jsonl`, `execution-summary.json`, `diagnosis.json`, `on-exit.log`, `timeout.log`, `capture.log`, `timeout.pid`, `capture.pid`
- Remaining in `/tmp`: tmux socket (`clawdbot-tmux-sockets/`), watchdog state (`cc-watchdog-state.json`), SSH remote temp files (`cc-<label>-reference-*`)
- Persistent history: `skills/claude-code-orchestrator/TASK_HISTORY.jsonl`
- Deployed production copy: `~/.openclaw/workspace/skills/claude-code-orchestrator/`

## Shell Script Conventions

All scripts follow these patterns:

- **Shebang**: `#!/usr/bin/env bash` with `set -euo pipefail`
- **Arg parsing**: `while [[ $# -gt 0 ]]; do case "$1" in` with `shift 2` for `--flag value`, `shift` for booleans
- **Validation**: `[[ -n "$VAR" ]] || { echo "Usage: ..."; exit 1; }`
- **SCRIPT_DIR**: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- **JSON generation**: Always `jq -n --arg/--argjson` — never string concatenation
- **RUNS_DIR**: `RUNS_DIR="$SCRIPT_DIR/../runs/$LABEL"` — all task artifacts go here, not `/tmp`
- **Background processes**: Track PID in `$RUNS_DIR/*.pid`, cleanup with `kill -0 ... && kill ... || true`
- **Non-critical failures**: `|| true` or `>/dev/null 2>&1 || true`
- **Pattern matching**: `rg -q "pattern"` (not grep) for pane content checks
- **SSH duality**: `--target ssh --ssh-host <alias>` with `-o BatchMode=yes` and explicit PATH
- **Notifications**: Always through `wake.sh` — never call `openclaw message send` directly from other scripts (except `on-session-exit.sh` and `timeout-guard.sh` which handle abnormal paths)

## Key Design Decisions

- **Prompts are in Chinese** (task instructions, delivery protocol). JSON field names and script output are in English.
- **Hardcoded Feishu user ID** (`ou_e5eb026fddb0fe05895df71a56f65e2f`) in `wake.sh`, `on-session-exit.sh`, `timeout-guard.sh` — this is Edward's DM target.
- **`complete-tmux-task.sh` is a fallback** — Claude Code is expected to write its own completion report. The script only runs if Claude didn't produce one.
- **`TASK_HISTORY.jsonl` is written by `wake.sh`** (on normal completion) and by `on-session-exit.sh`/`timeout-guard.sh` (on failure/timeout). Not by `complete-tmux-task.sh`.
- **`MANIFEST.sha256`** only covers the original files — newer scripts (`diagnose-failure.sh`, `on-session-exit.sh`, `timeout-guard.sh`, `watchdog.sh`, `analyze-history.sh`, `capture-execution.sh`) are not yet in the manifest.
