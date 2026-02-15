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
- Skill scripts: `skills/claude-code-orchestrator/` (recommended) / `skills/claude-code/` (deprecated alias)

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

## Security Notes

- **Before first use**, run `bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run` to verify dependencies and test the tmux session lifecycle.
- This skill launches `claude --dangerously-skip-permissions` inside a tmux session — Claude Code will **execute commands automatically** in the specified workdir without interactive confirmation. Make sure `--workdir` points to a trusted git repository.
- **Proxy**: No proxy is configured by default. Existing `https_proxy`/`http_proxy`/`all_proxy` environment variables are forwarded only if already set in your shell.
- **Lint/Build**: Not run by default. Pass `--lint-cmd` / `--build-cmd` explicitly to enable.
- Remote mode (`--target ssh`) is essentially remote code execution. Use least-privilege SSH keys and optionally restrict callback commands via `authorized_keys` `command=` restrictions.
- Keep all work inside git repos for rollback.

---

## Current Status & Next Steps (real-world)

### What’s already solid
- Task startup is stable (OpenClaw → tmux → Claude Code).
- Engineering-style deliverables are improving (completion reports as evidence).
- Better observability with:
  - `bash skills/claude-code-orchestrator/scripts/list-tasks.sh`
  - `bash skills/claude-code-orchestrator/scripts/list-tasks.sh --json | jq .`

### Still being refined
- “Auto push back when finished” can still be flaky (wake delivery, visibility).
  - Mitigation: proactively probe with `status-tmux-task.sh` / `list-tasks.sh`.

### Next to build
- A callback reliability loop (wake confirmation, failure markers, re-send when report exists but wake didn’t land).
- Multi-device execution as an advanced capability (mini always-on vs macbook with VPN/codebase).
