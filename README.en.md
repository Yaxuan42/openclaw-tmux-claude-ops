# OpenClaw × Claude Code × tmux: From "Schedulable Job System" to "Self-Iterating, Methodology-Constrained Job System"

[中文 README](./README.md)

> This is v2 of the final write-up. v1 explained the qualitative shift from "managing windows to managing jobs." This version adds two critical improvements:
> 1. **Feedback Loop** — the job system can now sense its own execution process; failures cannot go unnoticed
> 2. **Spec-Driven Dev Process** — AI writes requirements first, then designs, then codes, then delivers — just like a human engineer
>
> **One-liner: You no longer manage windows — you manage jobs. Jobs tell you what went wrong, and they follow proper engineering methodology from the start.**

---

## 0. v1 Recap (30 seconds)

v1 solved four structural deficiencies: not schedulable, not observable, not takeover-friendly, not auditable. The core architecture is three layers — primary agent (OpenClaw) schedules, worker agent (Claude Code) executes, tmux provides the observable + takeover layer. A mandatory delivery protocol turned "done" into an auditable evidence chain.

If you haven't read v1, read it first. This version only covers the delta.

---

## 1. Why v2: Two Problems on Different Dimensions

v1 solved "how to dispatch tasks and collect results." But real-world usage exposed two deeper problems:

**Problem 1: Task failure is a black box.**

Yuanming Hu (Taichi founder) ran 10 parallel Claude Code instances and found only ~20% task completion rate. Not because the model was weak, but because at scale, failures become probabilistic events — network glitches, missing files, dependency issues, infinite retries, context overflow. He added `--output-format stream-json --verbose` so the Manager could read structured execution logs and auto-detect error patterns — **success rate went from 20% to 95%**.

The core principle is dead simple: **closed-loop feedback**. Without process visibility, there's no diagnostic capability. Without diagnostic capability, you're relying on luck.

v1 was missing this loop. When tasks succeeded, everything was fine. When they failed, you faced a black box — the only option was to attach into tmux and manually sift through output.

**Problem 2: AI code "works" but has "no discipline."**

Claude Code has excellent single-task execution, but its working mode is "get prompt, start coding." Fine for simple tasks. For anything moderately complex — multi-iteration projects, requirement alignment, architectural consistency — you get:
- Requirement misunderstanding, discovered only after completion, expensive rework
- No design docs, future maintainers don't know why things were built this way
- Tests bolted on after implementation, becoming checkbox exercises
- Deliverables are just code — no changelog, no lessons learned

The root issue: **AI has execution capability but no methodological constraints.** It won't proactively write requirements docs, do technical design, or think through test strategy. If you don't give it a process, it won't have one.

This version addresses both.

---

## 2. Improvement 1: Feedback Loop — Making Failures Impossible to Miss

### 2.1 Process Observability: From "Sampled Snapshots" to "Complete Execution Stream"

v1 only had interactive mode. `capture-execution.sh` sampled the tmux pane every 15 seconds — like monitoring a process with timed screenshots. Everything between samples was lost.

New: `--mode headless`. In headless mode, Claude Code runs in pipe mode, natively outputting structured JSON log streams:

```bash
claude -p "$(cat prompt.txt)" \
  --dangerously-skip-permissions \
  --output-format stream-json \
  --verbose \
  2>&1 | tee "runs/<label>/stream.jsonl"
```

Every line is a JSON object:

```jsonl
{"type":"system","subtype":"init","session_id":"...","tools":["Bash","Read","Write",...]}
{"type":"assistant","subtype":"tool_use","tool":"Write","input":{"file_path":"...","content":"..."}}
{"type":"result","subtype":"cost","cost_usd":0.0124,"duration_ms":3200,"input_tokens":2100,"output_tokens":450}
```

Not sampled — complete. Every tool call, every output line, every token cost, all structured, queryable, auto-analyzable.

Two modes, choose by need:

| Dimension | Interactive (default) | Headless |
|-----------|----------------------|----------|
| Claude invocation | TUI (attach to take over keyboard) | Pipe (`claude -p --output-format stream-json`) |
| Process logs | Sampled snapshots (15s interval) | Native stream-json (complete record) |
| Use case | Complex, likely needs human intervention | Clear scope, high certainty |
| Parallelism | 2–3 | Can scale massively |

Rule of thumb: **if you can go headless, go headless.** Only use interactive when you expect to need mid-task takeover.

### 2.2 Three-Layer Event-Driven Monitoring

v1's failure path was a black hole: Claude Code stalls without calling wake — you don't know. Session crashes — you don't know. The wake notification itself silently fails (Feishu API error swallowed by `|| true`) — you also don't know.

Now every task launch auto-configures three defense layers:

**Layer 1: pane-died hook (instant, 0 latency)**
tmux `pane-died` event fires `on-session-exit.sh` the instant a session exits — checks for report, auto-diagnoses + Feishu alert on anomaly. Claude Code crash, OOM, network disconnect → notification in seconds.

**Layer 2: Timeout watchdog (background, default 2 hours)**
`timeout-guard.sh` catches "doesn't crash but doesn't finish" — infinite loops, endless retries, waiting for input that never comes.

**Layer 3: Periodic patrol (cron, every 10 minutes)**
`watchdog.sh` backstop scans all `cc-*` sessions, detecting dead/stuck/long-running/idle states. Even if layers 1 and 2 both fail, you'll know within 10 minutes.

**All pure shell, zero token cost.**

### 2.3 Automatic Failure Diagnosis

Detecting problems isn't enough — you need to explain why. `diagnose-failure.sh` analyzes 4 data sources (stream.jsonl / execution-events.jsonl / tmux pane capture / completion-report), matches against 8 common failure patterns (dependency_missing / timeout / code_error / loop / permission / rate_limit / context_overflow / unknown), and outputs structured diagnosis:

```json
{
  "label": "fix-login-bug",
  "failureCategory": "dependency_missing",
  "evidence": ["ENOENT: no such file or directory: '/path/to/config.json'"],
  "suggestion": "Check if dependency file exists, or specify explicit path in prompt",
  "retryable": true
}
```

You don't get "task failed." You get "task failed because config.json not found, suggest checking path, retryable."

### 2.4 Notification Loop Fix

v1's Feishu notifications were actually silently failing the entire time — three layers of bugs all swallowed by `|| true`. Fixed by switching to `openclaw message send --channel feishu --account main` for direct API calls.

Lesson: **Never let the notification pipeline have any silent failure path.** Notification is the last link in the loop — if it breaks, the entire loop breaks.

### 2.5 The Power of This Step

With complete process logs + three-layer auto-monitoring + auto-diagnosis, the system goes from "semi-closed loop" to "fully closed loop." Failures are no longer black boxes but events that are automatically discovered, automatically located, and presented in structured form. This is the infrastructure for moving task success rates from unpredictable to predictable.

---

## 3. Improvement 2: Dev Process — Spec-Driven 4-Phase Development Workflow

### 3.1 The Problem: AI Has Execution Capability but No Methodology

Give Claude Code "build me a user management system" and it immediately starts writing code. Fast, but the problems come later:

- **Misaligned requirements**: what you had in mind differs from what it understood. Discovered post-completion, rework cost is enormous
- **No design documentation**: code runs but there's no architecture design. Next time someone modifies it, they don't know why it was built this way
- **Tests bolted on after**: implementation first, tests second — tests become rubber stamps
- **No delivery artifacts**: project done, only code remains. No changelog, no lessons learned. Next project repeats the same mistakes

Human engineers have professional discipline and team norms to constrain these behaviors. AI doesn't — unless you encode the constraints into the process.

### 3.2 The Solution: Mandatory 4-Phase Process with Gates

Dev Process Skill breaks AI development tasks into 4 phases, each with explicit deliverables and quality gates:

```
Phase 1 (Requirements) → Phase 2 (Design) → Phase 3 (Development) → Phase 4 (Delivery)
  MRD + PRD               DESIGN + TEST       TDD iterations         CHANGELOG + lessons
  Human approval ✋         Human approval ✋     Auto gate ⚙️            Auto gate ⚙️
```

| Phase | AI is allowed to | AI is forbidden from | Approval |
|-------|-----------------|---------------------|----------|
| Phase 1 (Requirements) | Write MRD (market requirements), PRD (product requirements) | Write code, change architecture | Human ✋ |
| Phase 2 (Design) | Write DESIGN (technical design), TEST_PLAN (test plan) | Write business code | Human ✋ |
| Phase 3 (Development) | Write code, write tests, update CHANGELOG | Modify PRD scope | Auto ⚙️ |
| Phase 4 (Delivery) | Update docs, write LESSONS_LEARNED | Add new features | Auto ⚙️ |

Key design: **Phase 1/2 require human approval to proceed.** The review time you invest in requirements and design pays back tenfold during development as reduced rework. Phase 3/4 use auto gates (lint/build/test pass + git clean) — no babysitting needed.

### 3.3 Gate Checks: Not Suggestions — Hard Barriers

Each phase runs gate check scripts at completion. No pass, no progress:

- **Phase 1 gate**: MRD has substantive content? PRD has User Stories? Has Scope? Has testable Success Criteria?
- **Phase 2 gate**: DESIGN has architecture? Has data model? TEST_PLAN has TC entries? Has coverage targets?
- **Phase 3 gate**: Tests all pass? Lint passes? Build passes? Git working tree clean?
- **Phase 4 gate**: CHANGELOG has substantive entries? All 7 required docs exist? LESSONS_LEARNED has records?

Gate output is structured JSON for programmatic processing:

```json
{
  "gate": "phase3-iter-2",
  "passed": true,
  "checks": [
    {"name": "tests_pass", "ok": true, "detail": "Tests passed: 42 passing"},
    {"name": "lint", "ok": true, "detail": "Lint passed"}
  ],
  "humanApprovalRequired": false
}
```

### 3.4 Spec Change Detection: What If Design Doesn't Hold During Development?

During Phase 3, AI may discover the original design has issues. Dev Process doesn't block development — instead it requires:
1. Mark `[spec-change]` in CHANGELOG
2. Record the decision in STATUS.md Key Decisions table
3. Continue development, don't block

Phase 3 gate auto-detects `[spec-change]` tags and triggers Feishu notification. You can review these deviations after the fact.

This is pragmatic: don't require AI to stop and wait for confirmation (too slow), but ensure all deviations are recorded and notified.

### 3.5 Knowledge Accumulation: Cross-Project Experience Library

Each project's `docs/LESSONS_LEARNED.md` records lessons from that project. `record-lesson.sh` simultaneously writes to a cross-project knowledge base `cross_project_lessons.jsonl`.

When the next project launches, `dispatch-phase.sh` auto-reads the 5 most recent lessons and appends them to the prompt. Claude Code won't repeat the same mistakes — **provided you recorded them**.

Trigger conditions are practical: problems that took >30 minutes to solve, choosing between multiple approaches, behavior that contradicted expectations, third-party library/API gotchas.

### 3.6 Integration with the Orchestrator

Dev Process and the Orchestrator are **decoupled by design.** `dispatch-phase.sh` composes calls to the orchestrator's `start-tmux-task.sh`:

```bash
# Initialize project doc scaffold
bash scripts/init-project.sh --project-dir /path/to/project --project-name my-app --project-type web

# Progress phase by phase
bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 1 --mode headless
# → wait for completion → human review MRD/PRD
bash scripts/advance-phase.sh --project-dir /path/to/project --force

bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 2 --mode headless
# → wait for completion → human review DESIGN/TEST_PLAN
bash scripts/advance-phase.sh --project-dir /path/to/project --force

bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 3 --iteration 1 \
  --lint-cmd "npm run lint" --build-cmd "npm run build"
# → wait for completion → auto gate
bash scripts/advance-phase.sh --project-dir /path/to/project

bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 4 --mode headless
bash scripts/advance-phase.sh --project-dir /path/to/project
# → "Project COMPLETED!"
```

You can also skip the orchestrator entirely — manually edit docs + run gate checks. Dev Process works standalone.

### 3.7 The Power of This Step

Without Dev Process, AI coding is a "one-shot deal" — write it, if it runs, done. With Dev Process:

| Dimension | Without Dev Process | With Dev Process |
|-----------|-------------------|-----------------|
| Requirement alignment | Discovered wrong after completion | Phase 1 MRD/PRD first, human approval before coding |
| Technical design | No docs, everything in code | Phase 2 DESIGN/TEST_PLAN, architecture documented |
| Test strategy | Code first, tests later | Phase 3 TDD: tests first, implementation second |
| Change tracking | No records | CHANGELOG + spec-change auto-notification |
| Knowledge accumulation | Repeat same mistakes | LESSONS_LEARNED + cross-project knowledge base |
| Delivery quality | Just code | 7 documents + complete git history + gate audit records |

**You invest 2 phases of review time (requirements + design) and get dramatically reduced rework during development and dramatically reduced maintenance cost post-delivery.** This isn't overhead — it's the highest-ROI constraint you can impose.

---

## 4. "Using Itself to Improve Itself": A Concrete Case

`diagnose-failure.sh` was itself developed using headless Claude Code — **using this system to improve this system.**

Task data:
- Total time: 3.5 minutes
- Total tool calls: 41
- Cost: $0.88
- stream.jsonl: 104 lines, 239KB

Claude Code's execution was fully traceable:
1. Read prompt → launched sub-agent to explore project structure
2. Glob + Read multiple reference scripts to learn code style
3. Write 250-line diagnose-failure.sh
4. Create mock test data → run tests
5. Discover jq/grep edge case bug → auto-fix → retest pass
6. Clean up test files → git status/diff → write completion report

Human review still found 3 issues (`totalToolCalls` count inaccurate, prompt text misdiagnosed as error, duration extraction wrong) — proving human review remains essential. But the point: **Claude Code independently completed 90% of the work; humans only need to do the final 10% judgment.**

Three subsequent headless tasks (weekly report cron, SKILL.md update, AGENTS.md update) were dispatched simultaneously in parallel, each completing independently, total time ~40s. This validated the feasibility of scaled parallelism.

---

## 5. Before vs After: Complete Comparison

```
[v1: Semi-closed loop, no methodology]

Edward dispatches task → Claude Code gets prompt, starts coding immediately (interactive only)
                           ↓ success              ↓ failure
                     wake → notify (may silently fail)  → ? (nobody knows)
                     report → auditable                 → manually attach → sift tmux output

[v2: Complete closed loop + methodology constraints]

Edward dispatches task → Dev Process 4-phase workflow
  Phase 1 Requirements → Phase 2 Design → [Human approval ✋] → Phase 3 Development → Phase 4 Delivery
                                                                    ↓
                                Claude Code executes (interactive or headless, parallelizable)
                                    ↓ success                        ↓ failure/stuck
                              wake.sh                            Three-layer auto-detection
                              ├ Feishu DM direct push            ├ pane-died hook (seconds)
                              ├ Record TASK_HISTORY              ├ timeout-guard (2h backstop)
                              └ gateway wake                     └ watchdog cron (10min patrol)
                                    ↓                                ↓
                              OpenClaw reads report             diagnose-failure.sh
                              → Reply via Feishu                → Structured diagnosis → Feishu alert
                                    ↓ gate check                     ↓
                              advance-phase.sh               → Human decision: retry/fix prompt/abandon
                              → Auto quality gate → advance to next phase
                                    ↓ Every Monday 9:30
                              analyze-history.sh → weekly report → Feishu DM → optimization strategy
                                    ↓ Knowledge accumulation
                              LESSONS_LEARNED → cross-project KB → auto-injected into next project's prompt
```

Side-by-side comparison:

| Dimension | v1 | v2 |
|-----------|----|----|
| Execution modes | Interactive only | Interactive + headless dual mode |
| Process logs | 15s sampled snapshots | stream-json complete record (headless) |
| Failure detection | Relies on human noticing | Three-layer auto-detection (seconds → minutes → 10min patrol) |
| Failure diagnosis | Manually attach and guess | diagnose-failure.sh auto-analyzes 8 patterns |
| Notification reliability | Silent failures | Direct push + watchdog backstop |
| Parallelism | 2–3 | Headless scales massively |
| Diagnosis speed | 5–15 minutes | <30 seconds |
| Dev methodology | None (prompt → code immediately) | 4-phase spec-driven (requirements→design→development→delivery) |
| Requirement alignment | Depends on prompt quality | MRD/PRD + human approval |
| Technical design | None | DESIGN + TEST_PLAN + human approval |
| Test strategy | lint/build in delivery protocol | TDD workflow + gate checks |
| Change tracking | None | CHANGELOG + spec-change auto-notification |
| Knowledge accumulation | None | LESSONS_LEARNED + cross-project KB auto-reuse |
| Deliverables | Code + report | Code + 7 docs + report + gate audit |
| Iteration direction | By feel | By data (weekly report + KB + failure pattern analysis) |

---

## 6. Full Architecture (Updated)

### 6.1 Role Division

Three layers unchanged, but each layer is now thicker:

- **Primary Agent (OpenClaw)**: Scheduling + process control. No longer just "dispatch tasks" — now drives 4-phase Dev Process, waits for human approval at Phase 1/2, auto-advances at Phase 3/4
- **Worker Agent (Claude Code)**: Execution engine. Behavior constrained by Dev Process-injected CLAUDE.md rules — must read STATUS.md first, can only perform operations allowed in the current phase
- **Observable Layer (tmux + monitoring)**: Not just "can attach and see output" — complete logs + three-layer auto-monitoring + auto-diagnosis

### 6.2 Execution Flow

```
start-tmux-task.sh (single entry point)
  → Create tmux session cc-<label>
  → Mode selection:
      interactive → Claude TUI + capture-execution.sh (15s sampling)
      headless   → claude -p --output-format stream-json → runs/<label>/stream.jsonl
  → Auto-configure three defense layers:
      1. pane-died hook → on-session-exit.sh
      2. timeout-guard.sh (background, 2h)
      3. watchdog cron (deployed, every 10min)

Normal completion → wake.sh
  ├ Extract Claude's completion summary from stream.jsonl
  ├ Feishu DM direct push (openclaw message send)
  ├ Record TASK_HISTORY.jsonl
  └ gateway wake → OpenClaw reads report → replies via Feishu

Abnormal exit → on-session-exit.sh → diagnose-failure.sh → Feishu alert
Timeout      → timeout-guard.sh   → diagnose-failure.sh → Feishu alert
Backstop     → watchdog.sh cron   → scan all cc-* → notify
```

### 6.3 Dev Process Flow

```
init-project.sh → Create docs/ scaffold + inject CLAUDE.md rules

dispatch-phase.sh --phase 1 → Generate requirements prompt → start-tmux-task.sh
  → Claude Code writes MRD + PRD (forbidden from writing code)
  → advance-phase.sh → phase1-gate-check → human approval → advance

dispatch-phase.sh --phase 2 → Generate design prompt
  → Claude Code writes DESIGN + TEST_PLAN (forbidden from writing business code)
  → advance-phase.sh → phase2-gate-check → human approval → advance

dispatch-phase.sh --phase 3 --iteration N → Generate development prompt
  → Claude Code TDD iteration (tests first, implementation second)
  → advance-phase.sh → phase3-gate-check (lint/build/test/git clean) → auto-advance
  → [spec-change detection] → Feishu notification

dispatch-phase.sh --phase 4 → Generate delivery prompt
  → Claude Code updates docs + LESSONS_LEARNED
  → advance-phase.sh → phase4-gate-check → Project COMPLETED!
  → record-lesson.sh → cross-project knowledge base
```

### 6.4 Task Artifacts

All artifacts stored uniformly under `runs/<label>/` (no longer scattered in `/tmp`):

```
skills/claude-code-orchestrator/runs/<label>/
  ├── prompt.txt               # Original prompt
  ├── stream.jsonl             # Headless: complete stream-json
  ├── completion-report.json   # Completion report (JSON)
  ├── completion-report.md     # Completion report (Markdown)
  ├── execution-events.jsonl   # Interactive: sampled events
  ├── execution-summary.json   # Interactive: execution summary
  ├── diagnosis.json           # Failure diagnosis result
  ├── on-exit.log              # pane-died hook log
  ├── timeout.log              # timeout-guard log
  └── capture.log              # capture-execution log
```

One directory per task, persisted, survives restarts, archived by task.

---

## 7. When to Use and When Not To (Updated)

**Good fit:**
- 3+ parallel engineering tasks — three-layer monitoring ensures no task gets "lost"
- Projects with real complexity — Dev Process 4-phase ROI is highest on complex projects
- Post-hoc audit requirements — stream-json + 7 documents provide complete evidence chain
- Continuous iteration — knowledge base + weekly reports provide data-driven improvement direction

**Not a good fit:**
- Decisions that require deep human product judgment
- Extremely simple one-off tasks — just write a prompt and run Claude Code directly, no need for 4-phase process
- High-frequency exploratory debugging (IDE is more natural)

---

## 8. Actionable Practices (Updated)

1. **Default to headless.** Only use interactive when you expect mid-task takeover needs.
2. **Use Dev Process for complex projects.** Invest 2 phases reviewing requirements and design — trade upfront time for dramatically less rework.
3. **Don't panic on task failure.** Check the diagnosis in the Feishu notification first, then decide whether to fix the prompt and retry or manually intervene.
4. **Check the weekly report once a week.** The auto-generated Monday 9:30 stats report is your basis for optimizing dispatch strategy.
5. **Read report before diff.** Low risk → fast merge. High risk → dig into stream.jsonl to trace the process.
6. **Parallelize boldly.** Phase 3 multiple iterations, multiple independent tasks — all can be dispatched in parallel.
7. **Record lessons.** Use `record-lesson.sh` after every non-trivial issue. The next project benefits automatically.
8. **"Using itself to improve itself" works.** Dispatch a "improve this system" task to Claude Code, review output, merge the useful parts.

---

## 9. What Both Improvements Together Mean

v1 upgraded you from "managing windows" to "managing jobs."

v2 strengthens this job system on two orthogonal dimensions:

**Vertical — Execution Quality (Feedback Loop):**
- It knows what it's doing (stream-json complete record)
- It knows when something goes wrong (three-layer auto-detection)
- It can explain why something went wrong (diagnose-failure.sh auto-analysis)
- It can tell you how to improve using data (weekly report + failure pattern analysis)

**Horizontal — Development Discipline (Dev Process):**
- It won't skip requirements and jump straight to coding (Phase 1 gate)
- It won't skip technical design and jump straight to implementation (Phase 2 gate)
- It writes tests before implementation (Phase 3 TDD)
- It accumulates knowledge, tracks changes, delivers complete documentation (Phase 4 gate)

The feedback loop solves "what to do when things go wrong after the fact." Dev Process solves "how to have fewer things go wrong from the start." One is a post-hoc safety net, the other is a pre-emptive methodology. Together, they form a **sustainably operational AI engineering system.**

**Next step: Run more real projects through the Dev Process workflow, accumulate TASK_HISTORY and knowledge base data, and let the weekly report tell you what to optimize next.**

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/Yaxuan42/openclaw-tmux-claude-ops.git
cd openclaw-tmux-claude-ops

# 2. Environment check
bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run

# 3. Launch a task (single entry point)
bash skills/claude-code-orchestrator/scripts/start-tmux-task.sh \
  --label "my-task" --workdir "/path/to/project" \
  --prompt-file "prompt.txt" --task "Build feature X" \
  --mode headless

# 4. Check status
bash skills/claude-code-orchestrator/scripts/status-tmux-task.sh --label my-task

# 5. List all tasks
bash skills/claude-code-orchestrator/scripts/list-tasks.sh --json | jq .
```

## Project Structure

```
skills/claude-code-orchestrator/     # Orchestrator (task dispatch + monitoring)
  scripts/
    start-tmux-task.sh               # Single entry point for all tasks
    wake.sh                          # Notification + TASK_HISTORY recording
    on-session-exit.sh               # pane-died hook handler
    timeout-guard.sh                 # Background timeout watchdog
    diagnose-failure.sh              # Auto failure diagnosis
    watchdog.sh                      # Cron patrol backstop
    capture-execution.sh             # Interactive mode sampling
    complete-tmux-task.sh            # Fallback completion
    list-tasks.sh / status-tmux-task.sh / monitor-tmux-task.sh
    analyze-history.sh               # Weekly report generator
    bootstrap.sh                     # Environment setup
  runs/<label>/                      # Per-task artifact directories
  TASK_HISTORY.jsonl                 # Persistent task history

skills/dev-process/                  # Dev Process (4-phase methodology)
  scripts/
    init-project.sh                  # Project scaffold + CLAUDE.md injection
    dispatch-phase.sh                # Phase prompt generator → calls orchestrator
    advance-phase.sh                 # Gate check + phase advancement
    phase{1,2,3,4}-gate-check.sh     # Per-phase quality gates
    record-lesson.sh                 # Cross-project knowledge recording
  references/
    PROCESS_GUIDE.md                 # Methodology reference
    WEB_PROJECT_GUIDE.md             # Web project supplement

docs/                                # Narrative documentation
  FINAL_v2.md                        # Main write-up (Chinese)
CLAUDE.md                            # Agent onboarding instructions
AGENT_RUNBOOK.md                     # Executable runbook for agents
```
