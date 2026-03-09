# OpenClaw Claude Code Orchestrator

[English README](./README.en.md)

> **一句话：OpenClaw 通过 tmux 编排调度 Claude Code，实现任务的自动派发、实时监控、故障自愈和结构化交付。**

---

## 核心能力

### 三层架构

```
OpenClaw（调度层）──→ tmux（隔离 & 可观测层）──→ Claude Code（执行层）
   派发/唤醒/决策         session 隔离 / attach        实际编码 / 工具调用
```

- **OpenClaw**：任务调度器，负责派发任务、接收完成回调、做出下一步决策
- **tmux**：提供进程隔离和可观测性——每个任务一个 session，可随时 attach 接管
- **Claude Code**：执行引擎，在 tmux session 中运行，完成后通过 `wake.sh` 回调 OpenClaw

### 双执行模式

| 模式 | 调用方式 | 过程日志 | 适用场景 |
|------|---------|---------|---------|
| **interactive** | Claude TUI（可 attach） | 15s 采样快照 | 复杂任务、需中途接管 |
| **headless** | `claude -p --output-format stream-json` | 全量结构化日志 | 确定性任务、大规模并行 |

### 三层自动监控（零 token 消耗）

| 层级 | 机制 | 响应时间 | 覆盖场景 |
|------|------|---------|---------|
| pane-died hook | tmux 事件驱动 | 秒级 | 进程崩溃、异常退出 |
| timeout-guard | 后台计时器（2h） | 分钟级 | 死循环、无限重试 |
| watchdog cron | 定期巡检（10min） | 10 分钟 | 兜底：漏网之鱼 |

### 自动故障诊断

`diagnose-failure.sh` 分析 4 种数据源，匹配 8 种失败模式，输出结构化诊断报告 → 飞书 DM 告警。

### 完整交付协议

任务完成 → `wake.sh` → 飞书通知 + `TASK_HISTORY.jsonl` 记录 + `openclaw gateway call wake` 回调。每个任务产出 `completion-report.json` + `completion-report.md`，可审计、可追溯。

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/Yaxuan42/openclaw-tmux-claude-ops.git
cd openclaw-tmux-claude-ops

# 2. 环境检查
bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run

# 3. 启动任务
bash skills/claude-code-orchestrator/scripts/start-tmux-task.sh \
  --label "my-task" --workdir "/path/to/project" \
  --prompt-file "prompt.txt" --task "实现功能 X" \
  --mode headless

# 4. 查看状态（零 token）
bash skills/claude-code-orchestrator/scripts/status-tmux-task.sh --label my-task

# 5. 列出所有任务
bash skills/claude-code-orchestrator/scripts/list-tasks.sh --json | jq .

# 6. 诊断失败任务
bash skills/claude-code-orchestrator/scripts/diagnose-failure.sh --label my-task

# 7. 查看周报
bash skills/claude-code-orchestrator/scripts/analyze-history.sh --markdown
```

---

## 执行流程

```
start-tmux-task.sh（唯一入口）
  → 创建 tmux session cc-<label>
  → 模式选择：
      interactive → Claude TUI + capture-execution.sh（15s 采样）
      headless   → claude -p --output-format stream-json → runs/<label>/stream.jsonl
  → 自动配置三层防护：
      1. pane-died hook → on-session-exit.sh
      2. timeout-guard.sh（后台 2h）
      3. watchdog cron（每 10min）

正常完成 → wake.sh
  ├ 飞书 DM 直推
  ├ 记录 TASK_HISTORY.jsonl（含 duration + cost）
  └ gateway wake → OpenClaw 读取 report

异常退出 → on-session-exit.sh → diagnose-failure.sh → 飞书告警
超时     → timeout-guard.sh   → diagnose-failure.sh → 飞书告警
兜底     → watchdog.sh cron   → 扫描所有 cc-* → 通知
```

---

## 项目结构

```
skills/claude-code-orchestrator/         # 核心：编排调度
  SKILL.md                               # Claude Code 技能定义
  scripts/
    start-tmux-task.sh                   # 唯一任务入口
    wake.sh                              # 完成回调 + 通知
    on-session-exit.sh                   # pane-died hook
    timeout-guard.sh                     # 超时看门狗
    diagnose-failure.sh                  # 自动故障诊断
    watchdog.sh                          # cron 巡检兜底
    capture-execution.sh                 # interactive 模式采样
    complete-tmux-task.sh                # 兜底完成脚本
    status-tmux-task.sh                  # 零 token 状态检测
    monitor-tmux-task.sh                 # 输出查看 / attach
    list-tasks.sh                        # 任务列表
    analyze-history.sh                   # 周报生成
    bootstrap.sh                         # 环境检查
  runs/<label>/                          # 按任务归档的产物目录
  TASK_HISTORY.jsonl                     # 持久化任务历史

skills/dev-process/                      # 扩展：Spec 驱动研发流程
  scripts/
    init-project.sh                      # 项目骨架初始化
    dispatch-phase.sh                    # 阶段 prompt → 调用编排器
    advance-phase.sh                     # Gate Check + 阶段推进
    phase{1,2,3,4}-gate-check.sh         # 各阶段质量门
    record-lesson.sh                     # 跨项目知识记录
  references/
    PROCESS_GUIDE.md                     # 方法论参考
    WEB_PROJECT_GUIDE.md                 # Web 项目补充

docs/                                    # 文档
CLAUDE.md                               # Agent 入职手册
AGENT_RUNBOOK.md                         # Agent 可执行手册
CHANGELOG.md                             # 变更日志
```

---

## Dev Process：Spec 驱动的 4 阶段研发流程

在编排器之上叠加方法论约束，让 AI 按"需求 → 设计 → 开发 → 交付"的流程工作：

```
Phase 1 (需求)  →  Phase 2 (设计)  →  Phase 3 (开发)  →  Phase 4 (交付)
  MRD + PRD         DESIGN + TEST      TDD 迭代          CHANGELOG + 经验沉淀
  人工审批 ✋         人工审批 ✋          自动 gate ⚙️         自动 gate ⚙️
```

- Phase 1/2 必须人工审批才能推进——在需求和设计阶段投入审批时间，换来开发阶段大幅减少的返工
- Phase 3/4 自动 gate check：测试全过？lint/build 全过？文档齐全？
- 每个项目产出 `LESSONS_LEARNED.md`，跨项目知识库 `cross_project_lessons.jsonl` 自动复用

---

## 任务产物

每个任务在 `runs/<label>/` 下产出：

| 文件 | 说明 |
|------|------|
| `prompt.txt` | 原始 prompt |
| `stream.jsonl` | headless 全量日志 |
| `completion-report.json` | 完成报告（JSON） |
| `completion-report.md` | 完成报告（Markdown） |
| `execution-events.jsonl` | interactive 采样事件 |
| `diagnosis.json` | 失败诊断结果 |
| `on-exit.log` | pane-died hook 日志 |
| `timeout.log` | timeout-guard 日志 |

---

## 实践建议

1. **默认用 headless**——只有预判需要中途接管时才用 interactive
2. **复杂项目用 Dev Process**——花 2 个阶段审批需求和设计，换来开发阶段大幅减少的返工
3. **任务失败先看诊断**——飞书通知里的诊断结论，再决定是修 prompt 重试还是手动介入
4. **大胆并行**——headless 模式下可大量并行派发独立任务
5. **每周看一次周报**——`analyze-history.sh` 生成的统计报告是优化派活策略的依据

---

## 适用场景

**适合：** 并行多个工程任务、有一定复杂度的项目开发、需要事后审计的场景、持续迭代的团队

**不适合：** 极简单的一次性任务（直接跑 Claude Code 即可）、强依赖人类判断的产品决策

---

## 更多文档

- Agent 执行手册：[`AGENT_RUNBOOK.md`](./AGENT_RUNBOOK.md)
- 变更日志：[`CHANGELOG.md`](./CHANGELOG.md)
- 分享稿 v2（演进叙事）：[`docs/FINAL_v2.md`](./docs/FINAL_v2.md)
- 分享稿 v1：[`docs/FINAL.md`](./docs/FINAL.md)

---

## 说明

- 单机即可运行；如引入远程执行，请用最小权限控制 SSH key
- 建议所有执行在 git 管控的 repo 内进行，确保可回滚
- 飞书通知目标通过 `OPENCLAW_CC_ALERT_TARGET` 环境变量配置
