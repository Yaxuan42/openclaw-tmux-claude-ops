# OpenClaw × Claude Code × tmux: Turn Parallel AI Execution into a Schedulable Job System

[中文 README](./README.md)

This repo intentionally supports **two reading paths**:

- **For humans (why it matters / workflow shift / typical scenarios):** understand why *OpenClaw as the primary agent* matters, and why tmux is the structural piece for parallel AI work.
- **For agents (executable runbook):** hand the markdown directly to OpenClaw / Claude Code and let it execute step-by-step.

> Goal: not “users reading docs and tinkering”, but **humans decide; agents execute and deliver**.

---

## Quick Links

- Final article (main narrative): [`docs/FINAL.md`](./docs/FINAL.md)
- Agent runbook (main): [`AGENT_RUNBOOK.md`](./AGENT_RUNBOOK.md)
- Archived drafts: `docs/archive/`
- Skill scripts: `skills/claude-code-orchestrator/`

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/Yaxuan42/openclaw-tmux-claude-ops.git
cd openclaw-tmux-claude-ops

# 2. Environment check
bash skills/claude-code-orchestrator/scripts/bootstrap.sh

# 3. Verify tmux lifecycle (optional)
bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run
```

---

## Project Structure

- `docs/`
  - `FINAL.md`: final merged write-up (main)
  - `archive/`: historical drafts (not mainline)
- `skills/claude-code-orchestrator/`: tmux-first orchestration scripts (local/ssh supported)
  - `scripts/start-tmux-task.sh`: launch tasks (`--mode interactive|headless`)
  - `scripts/wake.sh`: notification + TASK_HISTORY recording (Feishu DM + gateway wake)
  - `scripts/on-session-exit.sh`: event-driven abnormal exit handler (tmux pane-died hook)
  - `scripts/timeout-guard.sh`: background timeout watchdog (default 2h)
  - `scripts/diagnose-failure.sh`: failure diagnosis (4 data sources, 8 failure patterns)
  - `scripts/watchdog.sh`: periodic patrol (cron every 10 min)
  - `scripts/capture-execution.sh`: interactive mode background sampling
  - `scripts/analyze-history.sh`: history analysis + weekly report
  - `scripts/list-tasks.sh`: list all cc-* sessions
  - `scripts/status-tmux-task.sh`: zero-token status detection
  - `scripts/monitor-tmux-task.sh`: live session viewer
  - `scripts/complete-tmux-task.sh`: fallback completion script
  - `scripts/bootstrap.sh`: environment setup
  - `TASK_HISTORY.jsonl`: task history log
- `AGENT_RUNBOOK.md`: executable steps for agents
- `MANIFEST.sha256`: file integrity checks

---

# OpenClaw as the Primary Agent (Steward + CTO): Orchestrating Claude Code Workers

This is not a tutorial. It explains three things:
1) why you want a **primary agent** (OpenClaw)
2) why **tmux** is the structural component for parallel AI work
3) what the “step change” actually is

## 1. The bottleneck is not the model — it’s human attention under parallelism
When you run 5–10 things in parallel (UI tweaks, bug fixes, scripts, build debugging), the default workflow degenerates into:
- many IDE windows + many terminal tabs + many AI chat sessions
- a mental map of “which window corresponds to which task”

The pain is structural:
- **not schedulable**: tasks only start when you sit at the keyboard
- **not observable**: you can’t quickly see what’s stuck and where
- **not takeover-friendly**: recovery requires finding the right window and restoring context
- **not auditable**: “done” without an evidence trail

## 2. OpenClaw’s role: steward + CTO (primary agent / scheduling layer)
OpenClaw is not “another coding agent” here. It’s the system that:
- receives tasks (even from mobile), shapes them into structured jobs
- enforces engineering constraints (quality gates, reports, callbacks)
- dispatches execution (tmux sessions) and collects deliverables

In one sentence:
> **The primary agent turns intent into a job; worker agents finish the job.**

## 3. Claude Code’s role: the execution engine (worker agent)
Claude Code is great at working inside a repo: reading code, editing, running commands, producing reports.
But “parallel management” needs structure — that’s where tmux comes in.

## 4. tmux’s role: from windows → sessions/jobs (observable + takeoverable)
- one task = one tmux session (`cc-<label>`)
- attach anytime to see live output
- takeover instantly when something is stuck

## 5. The step change: manage jobs, not windows
- windows → jobs
- “done” → completion reports (diff/quality gates/risk)
- manual supervision → observable sessions + selective intervention

> **You stop managing windows; you start managing jobs.**

---

## Notes & Boundaries

- Mainline is **single-machine orchestration**. If you add remote/multi-device execution, treat it as remote code execution: least-privilege SSH keys and optional `authorized_keys` command restrictions.
- Keep all work inside git repos for rollback.

---

## Current Status & Next Steps (updated 2026-02-17)

Full closed-loop feedback system verified (Phase 0-3 complete). Core pipeline is stable.

### What's solid and verified

- **Dual-mode execution**: `--mode interactive` (default, takeover-friendly) and `--mode headless` (`claude -p` + stream-json, native structured logs).
- **100% notification reliability**: Feishu DM direct push (`openclaw message send`) + gateway wake dual-channel. wake.sh extracts Claude Code's own completion summary for rich notifications.
- **Event-driven monitoring**:
  - `on-session-exit.sh`: tmux pane-died hook auto-triggers on abnormal exit — runs diagnosis, sends alert, records history. Pure shell, zero LLM tokens.
  - `timeout-guard.sh`: background timeout watchdog (default 2h), auto-diagnoses and notifies on timeout.
  - `watchdog.sh`: cron patrol every 10 minutes as fallback.
- **Automatic failure diagnosis**: `diagnose-failure.sh` supports 4 data sources, 8 failure patterns.
- **History + weekly report**: wake.sh auto-records to TASK_HISTORY.jsonl; weekly report sent Monday 9:30.
- **Parallel task execution verified**: 3 headless tasks launched simultaneously, completed independently in ~40s total.
- **Task observability**:
  - `bash skills/claude-code-orchestrator/scripts/list-tasks.sh`
  - `bash skills/claude-code-orchestrator/scripts/list-tasks.sh --json | jq .`

### Next to build
- **Auto-retry**: decide retry based on diagnose-failure.sh results.
- **Multi-device scheduling**: MacBook ↔ mini bidirectional SSH for execution node selection.
- **Sub-agent capability**: leverage OpenClaw sub-agents for complex task orchestration.
