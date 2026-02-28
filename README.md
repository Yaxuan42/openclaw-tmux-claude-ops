# OpenClaw × Claude Code × tmux：从"可调度作业系统"到"可自我迭代、有方法论约束的作业系统"

[English README](./README.en.md)

> 这是 FINAL 的第二版。第一版讲清楚了"从管理窗口到管理作业"的质变。这一版追加两项关键改进：
> 1. **反馈闭环**——让作业系统能感知自己的执行过程，失败不可能被遗漏
> 2. **Spec 驱动的研发流程**——让 AI 写代码时像人一样先写需求、再做设计、再动手、最后交付
>
> **一句话主轴：你不再管理窗口，你开始管理作业——作业会自己告诉你哪里出了问题，而且从一开始就按章办事。**

---

## 快捷入口

- 最终分享稿 v2（主线）：[`docs/FINAL_v2.md`](./docs/FINAL_v2.md)
- 最终分享稿 v1：[`docs/FINAL.md`](./docs/FINAL.md)
- Agent 执行手册：[`AGENT_RUNBOOK.md`](./AGENT_RUNBOOK.md)
- 归档草稿：`docs/archive/`
- 技能脚本：`skills/claude-code-orchestrator/` + `skills/dev-process/`

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/Yaxuan42/openclaw-tmux-claude-ops.git
cd openclaw-tmux-claude-ops

# 2. 环境检查
bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run

# 3. 启动任务（唯一入口）
bash skills/claude-code-orchestrator/scripts/start-tmux-task.sh \
  --label "my-task" --workdir "/path/to/project" \
  --prompt-file "prompt.txt" --task "实现功能 X" \
  --mode headless

# 4. 查看状态
bash skills/claude-code-orchestrator/scripts/status-tmux-task.sh --label my-task

# 5. 列出所有任务
bash skills/claude-code-orchestrator/scripts/list-tasks.sh --json | jq .
```

---

## 项目结构

```
skills/claude-code-orchestrator/     # 编排器（任务调度 + 监控）
  scripts/
    start-tmux-task.sh               # 唯一任务入口
    wake.sh                          # 通知 + TASK_HISTORY 记录
    on-session-exit.sh               # pane-died hook 处理
    timeout-guard.sh                 # 后台超时看门狗
    diagnose-failure.sh              # 自动失败诊断
    watchdog.sh                      # cron 巡检兜底
    capture-execution.sh             # interactive 模式采样
    complete-tmux-task.sh            # 兜底完成脚本
    list-tasks.sh / status-tmux-task.sh / monitor-tmux-task.sh
    analyze-history.sh               # 周报生成
    bootstrap.sh                     # 环境初始化
  runs/<label>/                      # 按任务归档的产物目录
  TASK_HISTORY.jsonl                 # 持久化任务历史

skills/dev-process/                  # Dev Process（4 阶段方法论）
  scripts/
    init-project.sh                  # 项目骨架 + CLAUDE.md 注入
    dispatch-phase.sh                # 阶段 prompt 生成 → 调用编排器
    advance-phase.sh                 # Gate Check + 阶段推进
    phase{1,2,3,4}-gate-check.sh     # 各阶段质量门
    record-lesson.sh                 # 跨项目知识记录
  references/
    PROCESS_GUIDE.md                 # 方法论参考
    WEB_PROJECT_GUIDE.md             # Web 项目补充

docs/                                # 叙事文档
  FINAL_v2.md                        # 主线分享稿（v2）
  FINAL.md                           # v1 分享稿
CLAUDE.md                            # Agent 入职手册
AGENT_RUNBOOK.md                     # Agent 可执行手册
```

---

## 0. 第一版回顾（30 秒版）

第一版解决了四个结构性缺陷：不可调度、不可观测、不可接管、不可复盘。核心架构是三层——主 Agent（OpenClaw）调度、子 Agent（Claude Code）执行、tmux 提供可观测 + 可接管层。强制交付协议把"done"变成了可审计的证据链。

---

## 1. 为什么需要第二版：两个不同维度的问题

第一版解决了"怎么把任务派出去、怎么收回来"。但实战中暴露了两个更深层的问题：

**问题一：任务失败是黑箱。**

胡渊鸣（Taichi 创始人）并行跑 10 个 Claude Code 后发现任务完成率只有约 20%。原因不是模型不行，而是并行规模化后失败变成概率事件——网络抖动、文件找不到、依赖装不上、循环重试、上下文爆炸。他加了一步 `--output-format stream-json --verbose` 让 Manager 读取结构化执行日志、自动发现错误模式，**成功率从 20% 到 95%**。

核心原理极其朴素：**闭环反馈**。没有过程可见性，就没有诊断能力；没有诊断能力，就只能靠运气。

**问题二：AI 写的代码"能跑"但"没章法"。**

Claude Code 单任务执行力很强，但它的工作方式是"拿到 prompt 就开始写代码"。对简单任务没问题。对稍微复杂的项目会出现：需求理解偏差写完才发现、没有设计文档、测试补在后面、交付物只有代码。

本质问题是：**AI 有执行力但没有方法论约束**。你不给它流程，它就不会有流程。

---

## 2. 改进一：反馈闭环——让失败不可能被遗漏

### 2.1 Headless 模式：全量结构化日志

新增 `--mode headless`，原生输出 stream-json：

```bash
claude -p "$(cat prompt.txt)" \
  --dangerously-skip-permissions \
  --output-format stream-json --verbose \
  2>&1 | tee "runs/<label>/stream.jsonl"
```

每一行都是一个 JSON 对象——不是采样，是全量记录。每个 tool call、每行输出、每笔 token 消耗，全部结构化、可查询、可自动分析。

| 维度 | 交互模式（默认） | Headless 模式 |
|------|----------------|--------------|
| Claude 调用 | TUI（可 attach 接管） | 管道（`claude -p --output-format stream-json`） |
| 过程日志 | 采样快照（15s 间隔） | 原生 stream-json（全量记录） |
| 适用场景 | 复杂、需要人工介入 | 明确、确定性高 |
| 并行能力 | 2-3 个 | 可大量并行 |

### 2.2 三层事件驱动监控

1. **pane-died hook（秒级）**：tmux session 退出瞬间触发 → 自动诊断 + 飞书告警
2. **超时看门狗（后台 2h）**：防"不崩溃但也不结束"——死循环、无限重试
3. **定期巡检（cron 10min）**：兜底扫描所有 `cc-*` session

**全部纯 shell，零 token 消耗。**

### 2.3 自动失败诊断

`diagnose-failure.sh` 分析 4 种数据源，匹配 8 种失败模式，输出结构化诊断：

```json
{
  "label": "fix-login-bug",
  "failureCategory": "dependency_missing",
  "evidence": ["ENOENT: no such file or directory: '/path/to/config.json'"],
  "suggestion": "检查依赖文件是否存在，或在 prompt 中明确文件路径",
  "retryable": true
}
```

---

## 3. 改进二：Dev Process——Spec 驱动的 4 阶段研发流程

### 3.1 强制 4 阶段流程，每阶段有 Gate

```
Phase 1 (需求)  →  Phase 2 (设计)  →  Phase 3 (开发)  →  Phase 4 (交付)
  MRD + PRD         DESIGN + TEST      TDD 迭代          CHANGELOG + 经验沉淀
  人工审批 ✋         人工审批 ✋          自动 gate ⚙️         自动 gate ⚙️
```

| 阶段 | AI 允许做什么 | AI 禁止做什么 | 审批方式 |
|------|-------------|-------------|---------|
| Phase 1（需求） | 写 MRD、PRD | 写代码、改架构 | 人工 ✋ |
| Phase 2（设计） | 写 DESIGN、TEST_PLAN | 写业务代码 | 人工 ✋ |
| Phase 3（开发） | 写代码、写测试、更新 CHANGELOG | 修改 PRD scope | 自动 ⚙️ |
| Phase 4（交付） | 更新文档、写 LESSONS_LEARNED | 新增功能 | 自动 ⚙️ |

**Phase 1/2 必须人工审批才能推进。** 你在需求和设计阶段投入的审批时间，会在开发阶段以减少返工的方式十倍返还。

### 3.2 Gate Check：硬门槛

- **Phase 1**：MRD 有实质内容？PRD 有 User Stories / Scope / Success Criteria？
- **Phase 2**：DESIGN 有架构？TEST_PLAN 有 TC 条目 + 覆盖率目标？
- **Phase 3**：测试全过？lint/build 全过？git 工作区干净？
- **Phase 4**：CHANGELOG 有实质条目？7 个必需文档全存在？LESSONS_LEARNED 有记录？

### 3.3 Spec 变更检测

Phase 3 开发中发现设计不对：
1. 在 CHANGELOG 标记 `[spec-change]`
2. 在 STATUS.md Key Decisions 记录
3. 继续开发，不阻塞
4. Gate 自动检测 → 飞书通知

### 3.4 知识沉淀

每个项目的 `docs/LESSONS_LEARNED.md` + 跨项目知识库 `cross_project_lessons.jsonl`。下一个项目启动时自动引用最近 5 条历史经验。

### 3.5 与编排器集成

```bash
# 初始化项目文档骨架
bash scripts/init-project.sh --project-dir /path/to/project --project-name my-app --project-type web

# 逐阶段推进
bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 1 --mode headless
# → 等待完成 → 人工审核 MRD/PRD
bash scripts/advance-phase.sh --project-dir /path/to/project --force

bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 2 --mode headless
# → 等待完成 → 人工审核 DESIGN/TEST_PLAN
bash scripts/advance-phase.sh --project-dir /path/to/project --force

bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 3 --iteration 1
# → 等待完成 → 自动 gate
bash scripts/advance-phase.sh --project-dir /path/to/project

bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 4 --mode headless
bash scripts/advance-phase.sh --project-dir /path/to/project
# → "Project COMPLETED!"
```

---

## 4. "用自己改进自己"

`diagnose-failure.sh` 本身就是用 headless Claude Code 开发的——用这套体系来改进这套体系。

- 耗时 3.5 分钟 / 41 次 tool calls / $0.88
- Claude Code 独立完成 90%，人只做最后 10% 判断
- 随后 3 个 headless 任务并行派发，各自独立完成，总耗时 ~40s

---

## 5. 改进前后对比

```
【第一版：半闭环，无方法论】

Edward 发任务 → Claude Code 拿到 prompt 直接写代码（仅 interactive）
                    ↓ 完成              ↓ 失败
              wake → 通知 (可能静默失败)    → ？（无人知道）

【第二版：完整闭环 + 方法论约束】

Edward 发任务 → Dev Process 4 阶段流程
  Phase 1 需求 → Phase 2 设计 → [人工审批 ✋] → Phase 3 开发 → Phase 4 交付
                                                  ↓
                              Claude Code 执行（interactive 或 headless，可并行）
                                  ↓ 完成                        ↓ 失败/卡住
                            wake.sh                        三层自动发现
                            ├ 飞书 DM 直推                  ├ pane-died hook（秒级）
                            ├ 记录 TASK_HISTORY             ├ timeout-guard（2h 兜底）
                            └ gateway wake                 └ watchdog cron（10min 巡检）
                                  ↓                              ↓
                            OpenClaw 读取 report           diagnose-failure.sh
                            → 回复飞书                     → 结构化诊断 → 飞书告警
                                  ↓ gate check
                            advance-phase.sh → 自动质量门 → 推进下一阶段
                                  ↓ 经验沉淀
                            LESSONS_LEARNED → 跨项目知识库 → 下个项目自动引用
```

| 维度 | 第一版 | 第二版 |
|------|-------|-------|
| 执行模式 | 仅 interactive | interactive + headless 双模式 |
| 过程日志 | 15s 采样快照 | stream-json 全量记录 |
| 失败发现 | 靠人注意到 | 三层自动发现（秒级 → 分钟级 → 10min） |
| 失败诊断 | 手动 attach 猜 | diagnose-failure.sh 自动分析 8 种模式 |
| 通知可靠性 | 静默失败 | 直推 + watchdog 兜底 |
| 并行能力 | 2-3 个 | headless 可大量并行 |
| 开发方法论 | 无 | 4 阶段 spec 驱动 |
| 需求对齐 | 靠 prompt 写得好 | MRD/PRD + 人工审批 |
| 技术设计 | 无 | DESIGN + TEST_PLAN + 人工审批 |
| 测试策略 | 交付协议里的 lint/build | TDD 工作流 + gate check |
| 变更追踪 | 无 | CHANGELOG + spec-change 自动通知 |
| 经验沉淀 | 无 | LESSONS_LEARNED + 跨项目知识库自动复用 |
| 交付物 | 代码 + report | 代码 + 7 份文档 + report + gate 审计 |

---

## 6. 完整架构

### 6.1 执行流程

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
  ├ 从 stream.jsonl 提取完成摘要
  ├ 飞书 DM 直推
  ├ 记录 TASK_HISTORY.jsonl（含 duration + cost）
  └ gateway wake → OpenClaw 读取 report

异常退出 → on-session-exit.sh → diagnose-failure.sh → 飞书告警
超时     → timeout-guard.sh   → diagnose-failure.sh → 飞书告警
兜底     → watchdog.sh cron   → 扫描所有 cc-* → 通知
```

### 6.2 Dev Process 流程

```
init-project.sh → 创建 docs/ 文档骨架 + 注入 CLAUDE.md 规则

dispatch-phase.sh --phase 1 → 需求阶段 prompt → start-tmux-task.sh
  → Claude Code 写 MRD + PRD → phase1-gate-check → 人工审批 → 推进

dispatch-phase.sh --phase 2 → 设计阶段 prompt
  → Claude Code 写 DESIGN + TEST_PLAN → phase2-gate-check → 人工审批 → 推进

dispatch-phase.sh --phase 3 --iteration N → 开发阶段 prompt
  → Claude Code TDD 迭代 → phase3-gate-check → 自动推进
  → [spec-change 检测] → 飞书通知

dispatch-phase.sh --phase 4 → 交付阶段 prompt
  → 更新文档 + LESSONS_LEARNED → phase4-gate-check → COMPLETED!
```

### 6.3 任务产物

```
skills/claude-code-orchestrator/runs/<label>/
  ├── prompt.txt               # 原始 prompt
  ├── stream.jsonl             # headless：完整 stream-json
  ├── completion-report.json   # 完成报告（JSON）
  ├── completion-report.md     # 完成报告（Markdown）
  ├── execution-events.jsonl   # interactive：采样事件
  ├── execution-summary.json   # interactive：执行摘要
  ├── diagnosis.json           # 失败诊断结果
  ├── on-exit.log              # pane-died hook 日志
  ├── timeout.log              # timeout-guard 日志
  └── capture.log              # capture-execution 日志
```

---

## 7. 适用与不适用

**适合：**
- 并行 3 件以上的工程任务——三层监控保证不会"丢"任务
- 有一定复杂度的项目——Dev Process 4 阶段的 ROI 在复杂项目上最高
- 需要事后审计——stream-json + 7 份文档提供完整证据链
- 需要持续迭代——知识库 + 周报提供数据驱动的改进方向

**不适合：**
- 强依赖人类判断的产品决策
- 极简单的一次性任务——直接写 prompt 跑 Claude Code 就行
- 高频探索性调试（直接 IDE 更顺手）

---

## 8. 实践建议

1. **默认用 headless**。只有预判需要中途接管时才用 interactive
2. **复杂项目用 Dev Process**。花 2 个阶段审批需求和设计，换来开发阶段大幅减少的返工
3. **任务失败先看诊断**。飞书通知里的诊断结论，再决定是修 prompt 重试还是手动介入
4. **每周看一次周报**。周一 9:30 自动发送的统计报告是你优化派活策略的依据
5. **先读 report 再读 diff**。低风险快速合，高风险再深入看 stream.jsonl
6. **大胆并行**。Phase 3 的多个迭代、多个独立任务，都可以并行派发
7. **记录经验**。每次踩坑用 `record-lesson.sh` 记录，下个项目会自动受益
8. **"用自己改进自己"**。给 Claude Code 派一个"改进这套体系"的任务，review 产出，合并有用的部分

---

## 说明与边界

- 主线默认单机即可跑出质变；如果引入远程/多设备执行，请用最小权限控制 SSH key
- 强烈建议所有执行都在 git 管控的 repo 内进行，确保可回滚
