# FINAL v2｜OpenClaw × Claude Code × tmux：从"可调度作业系统"到"可自我迭代、有方法论约束的作业系统"

> 这是 FINAL 的第二版。第一版讲清楚了"从管理窗口到管理作业"的质变。这一版追加两项关键改进：
> 1. **反馈闭环**——让作业系统能感知自己的执行过程，失败不可能被遗漏
> 2. **Spec 驱动的研发流程**——让 AI 写代码时像人一样先写需求、再做设计、再动手、最后交付
>
> **一句话主轴：你不再管理窗口，你开始管理作业——作业会自己告诉你哪里出了问题，而且从一开始就按章办事。**

---

## 0. 第一版回顾（30 秒版）

第一版解决了四个结构性缺陷：不可调度、不可观测、不可接管、不可复盘。核心架构是三层——主 Agent（OpenClaw）调度、子 Agent（Claude Code）执行、tmux 提供可观测 + 可接管层。强制交付协议把"done"变成了可审计的证据链。

如果你没看过第一版，先看完再回来。这一版只讲增量。

---

## 1. 为什么需要第二版：两个不同维度的问题

第一版解决了"怎么把任务派出去、怎么收回来"。但实战中暴露了两个更深层的问题：

**问题一：任务失败是黑箱。**

胡渊鸣（Taichi 创始人）并行跑 10 个 Claude Code 后发现任务完成率只有约 20%。原因不是模型不行，而是并行规模化后失败变成概率事件——网络抖动、文件找不到、依赖装不上、循环重试、上下文爆炸。他加了一步 `--output-format stream-json --verbose` 让 Manager 读取结构化执行日志、自动发现错误模式，**成功率从 20% 到 95%**。

核心原理极其朴素：**闭环反馈**。没有过程可见性，就没有诊断能力；没有诊断能力，就只能靠运气。

第一版的体系缺了这一环。任务成功时一切顺利，失败时你面对的是黑箱——只能 attach 进去翻 tmux 输出手动猜。

**问题二：AI 写的代码"能跑"但"没章法"。**

Claude Code 单任务执行力很强，但它的工作方式是"拿到 prompt 就开始写代码"。对简单任务没问题。对稍微复杂的项目——比如需要多轮迭代、需要和人对齐需求、需要保证架构一致性的任务——会出现：
- 需求理解偏差，写完才发现方向不对，返工
- 没有设计文档，后续修改时不知道当初为什么这么写
- 测试补在后面，而不是先写测试再写实现
- 交付物只有代码，没有 changelog、没有经验沉淀

本质问题是：**AI 有执行力但没有方法论约束**。它不会主动先写需求文档、先做技术设计、先想清楚测试策略。你不给它流程，它就不会有流程。

这一版同时补上这两块。

---

## 2. 改进一：反馈闭环——让失败不可能被遗漏

### 2.1 过程可观测性：从"采样快照"到"完整执行流"

第一版只有交互模式。capture-execution.sh 每 15 秒采样一次 tmux pane——像用定时截屏"监控"进程，采样间隙里的信息全丢了。

新增 `--mode headless`。Headless 模式下 Claude Code 以管道模式运行，原生输出结构化 JSON 日志流：

```bash
claude -p "$(cat prompt.txt)" \
  --dangerously-skip-permissions \
  --output-format stream-json \
  --verbose \
  2>&1 | tee "runs/<label>/stream.jsonl"
```

每一行都是一个 JSON 对象：

```jsonl
{"type":"system","subtype":"init","session_id":"...","tools":["Bash","Read","Write",...]}
{"type":"assistant","subtype":"tool_use","tool":"Write","input":{"file_path":"...","content":"..."}}
{"type":"result","subtype":"cost","cost_usd":0.0124,"duration_ms":3200,"input_tokens":2100,"output_tokens":450}
```

不是采样，是全量记录。每个 tool call、每行输出、每笔 token 消耗，全部结构化、可查询、可自动分析。

两种模式按需选择：

| 维度 | 交互模式（默认） | Headless 模式 |
|------|----------------|--------------|
| Claude 调用 | TUI（可 attach 接管键盘） | 管道（`claude -p --output-format stream-json`） |
| 过程日志 | 采样快照（15s 间隔） | 原生 stream-json（全量记录） |
| 适用场景 | 复杂、需要人工介入 | 明确、确定性高 |
| 并行能力 | 2-3 个 | 可大量并行 |

选择建议：**能 headless 就 headless**。只有你预判"很可能需要中途接管"时才用 interactive。

### 2.2 三层事件驱动监控

第一版的失败路径是黑洞：Claude Code 卡住不调用 wake 你不知道，session 崩溃你不知道，wake 通知本身静默失败（飞书 API 报错被 `|| true` 吞掉）你也不知道。

现在每个任务启动时自动配置三层防护：

**第一层：pane-died hook（即时，0 延迟）**
tmux `pane-died` 事件在 session 退出瞬间触发 `on-session-exit.sh`——检查是否有 report，异常时自动诊断 + 飞书告警。Claude Code 崩溃、OOM、网络断开，秒级收到通知。

**第二层：超时看门狗（后台，默认 2 小时）**
`timeout-guard.sh` 防的是"不崩溃但也不结束"——死循环、无限重试、等待不会来的输入。

**第三层：定期巡检（cron，每 10 分钟）**
`watchdog.sh` 兜底扫描所有 `cc-*` session，检测 dead/stuck/long-running/idle 状态。即使前两层都失效，10 分钟内你也会知道。

**全部是纯 shell，零 token 消耗。**

### 2.3 自动失败诊断

发现问题不够，还要说清楚原因。`diagnose-failure.sh` 分析 4 种数据源（stream.jsonl / execution-events.jsonl / tmux pane capture / completion-report），匹配 8 种常见失败模式（dependency_missing / timeout / code_error / loop / permission / rate_limit / context_overflow / unknown），输出结构化诊断：

```json
{
  "label": "fix-login-bug",
  "failureCategory": "dependency_missing",
  "evidence": ["ENOENT: no such file or directory: '/path/to/config.json'"],
  "suggestion": "检查依赖文件是否存在，或在 prompt 中明确文件路径",
  "retryable": true
}
```

你收到的不是"任务失败了"，而是"任务失败了，因为找不到 config.json，建议检查路径，可以重试"。

### 2.4 通知闭环修复

第一版的飞书通知实际上一直是静默失败的——三层 bug 全被 `|| true` 吞掉。最终改用 `openclaw message send --channel feishu --account main` 直接调 API，一步到位。

教训：**不要让通知链路有任何静默失败的可能**。通知是闭环的最后一环，它断了整个闭环就断了。

### 2.5 这步的威力

有了全量过程日志 + 三层自动监控 + 自动诊断，系统从"半闭环"变成"完整闭环"。失败不再是黑箱，而是可被自动发现、自动定位、结构化呈现的事件。这是任务成功率从不可预期走向可预期的基础设施。

---

## 3. 改进二：Dev Process——Spec 驱动的 4 阶段研发流程

### 3.1 问题：AI 有执行力，但没有方法论

给 Claude Code 一句"帮我写个用户管理系统"，它会立刻开始写代码。速度很快，但问题在后面：

- **需求没对齐**：你脑子里想的和它理解的不一样，写完才发现，返工成本极高
- **设计没文档**：代码能跑但没有架构设计，下次改的时候不知道当初为什么这么写
- **测试补在后面**：先写实现再补测试，测试沦为"走过场"
- **交付没沉淀**：项目做完只有代码，没有 changelog、没有踩坑记录，下个项目重复犯同样的错

人类工程师有职业素养和团队规范来约束这些行为。AI 没有——除非你把约束写进流程。

### 3.2 解法：强制 4 阶段流程，每阶段有 Gate

Dev Process Skill 把 AI 开发任务拆成 4 个阶段，每个阶段有明确的产出物和质量门（Gate Check）：

```
Phase 1 (需求)  →  Phase 2 (设计)  →  Phase 3 (开发)  →  Phase 4 (交付)
  MRD + PRD         DESIGN + TEST      TDD 迭代          CHANGELOG + 经验沉淀
  人工审批 ✋         人工审批 ✋          自动 gate ⚙️         自动 gate ⚙️
```

| 阶段 | AI 允许做什么 | AI 禁止做什么 | 审批方式 |
|------|-------------|-------------|---------|
| Phase 1（需求） | 写 MRD（市场需求）、PRD（产品需求） | 写代码、改架构 | 人工 ✋ |
| Phase 2（设计） | 写 DESIGN（技术设计）、TEST_PLAN（测试计划） | 写业务代码 | 人工 ✋ |
| Phase 3（开发） | 写代码、写测试、更新 CHANGELOG | 修改 PRD scope | 自动 ⚙️ |
| Phase 4（交付） | 更新文档、写 LESSONS_LEARNED | 新增功能 | 自动 ⚙️ |

关键设计：**Phase 1/2 必须人工审批才能推进**。你在需求和设计阶段投入的审批时间，会在开发阶段以减少返工的方式十倍返还。Phase 3/4 自动 Gate（lint/build/test 全过 + git clean），不需要人盯。

### 3.3 Gate Check：不是建议，是硬门槛

每个阶段结束时运行 gate check 脚本，不通过就不能推进：

- **Phase 1 gate**：MRD 有实质内容？PRD 有 User Stories？有 Scope？有可测试的 Success Criteria？
- **Phase 2 gate**：DESIGN 有架构图？有数据模型？TEST_PLAN 有 TC 条目？有覆盖率目标？
- **Phase 3 gate**：测试全过？lint 全过？build 全过？git 工作区干净？
- **Phase 4 gate**：CHANGELOG 有实质条目？7 个必需文档全存在？LESSONS_LEARNED 有记录？

Gate 输出是结构化 JSON，便于程序化处理：

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

### 3.4 Spec 变更检测：开发中发现设计不对怎么办

Phase 3 开发过程中，AI 可能发现原始设计有问题。Dev Process 不阻断开发，而是要求：
1. 在 CHANGELOG 中标记 `[spec-change]`
2. 在 STATUS.md Key Decisions 表记录决策
3. 继续开发，不阻塞

Phase 3 gate 会自动检测 `[spec-change]` 标签，触发飞书通知给你。你可以事后审核这些偏差是否合理。

这个设计很务实：不要求 AI 停下来等人确认（那太慢了），但确保所有偏差都被记录和通知。

### 3.5 知识沉淀：跨项目的经验库

每个项目的 `docs/LESSONS_LEARNED.md` 记录本项目踩过的坑。`record-lesson.sh` 同时写入跨项目知识库 `cross_project_lessons.jsonl`。

下一个项目启动时，`dispatch-phase.sh` 自动读取最近 5 条历史经验教训，附加到 prompt 里。Claude Code 不会重复犯同样的错——**前提是你记录了**。

触发条件很实际：花超过 30 分钟解决的问题、在多个方案中做出选择时、发现与预期不符的行为、第三方库/API 的坑。

### 3.6 与 Orchestrator 的集成

Dev Process 和 Orchestrator 是**解耦设计**。`dispatch-phase.sh` 组合调用 orchestrator 的 `start-tmux-task.sh`：

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

bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 3 --iteration 1 \
  --lint-cmd "npm run lint" --build-cmd "npm run build"
# → 等待完成 → 自动 gate
bash scripts/advance-phase.sh --project-dir /path/to/project

bash scripts/dispatch-phase.sh --project-dir /path/to/project --phase 4 --mode headless
bash scripts/advance-phase.sh --project-dir /path/to/project
# → "Project COMPLETED!"
```

也可以不用 orchestrator，手动编辑文档 + 跑 gate check。Dev Process 独立可用。

### 3.7 这步的威力

没有 Dev Process，AI 写代码是"一锤子买卖"——写完能跑就完了。有了 Dev Process：

| 维度 | 没有 Dev Process | 有 Dev Process |
|------|-----------------|---------------|
| 需求对齐 | 写完才发现不对 | Phase 1 先写 MRD/PRD，人工审批后再动手 |
| 技术设计 | 没有文档，全在代码里 | Phase 2 先写 DESIGN/TEST_PLAN，有架构图 |
| 测试策略 | 先写代码后补测试 | Phase 3 TDD：先写测试再写实现 |
| 变更追踪 | 没有记录 | CHANGELOG + spec-change 自动通知 |
| 经验沉淀 | 下次重复踩坑 | LESSONS_LEARNED + 跨项目知识库 |
| 交付质量 | 只有代码 | 7 份文档 + 完整 git history + gate 审计记录 |

**你多花 2 个阶段的审批时间（需求 + 设计），换来的是开发阶段大幅减少的返工和交付后大幅减少的维护成本。** 这不是额外负担，是投资回报率最高的约束。

---

## 4. "用自己改进自己"：一个具体案例

`diagnose-failure.sh` 这个脚本本身就是用 headless Claude Code 开发的——**用这套体系来改进这套体系**。

任务数据：
- 总耗时：3.5 分钟
- 总 tool calls：41 次
- 成本：$0.88
- stream.jsonl：104 行，239KB

Claude Code 的执行过程完全可追溯：
1. 读取 prompt → 启动子代理探索项目结构
2. Glob + Read 多个参考脚本学习代码风格
3. Write 250 行的 diagnose-failure.sh
4. 创建 mock 测试数据 → 跑测试
5. 发现 jq/grep 边界 bug → 自动修复 → 重新测试通过
6. 清理测试文件 → git status/diff → 写 completion report

人工 review 仍然发现了 3 个问题（`totalToolCalls` 统计不准、prompt 文本被误诊为错误、duration 提取方式不对），说明人工审查依然不可或缺。但重点是：**Claude Code 能独立完成 90% 的工作，人只需要做最后 10% 的判断。**

随后的 3 个 headless 任务（周报 cron、SKILL.md 更新、AGENTS.md 更新）被同时并行派发，各自独立完成，总耗时 ~40 秒。这验证了规模化并行的可行性。

---

## 5. 改进前后的完整对比

```
【第一版：半闭环，无方法论】

Edward 发任务 → Claude Code 拿到 prompt 直接写代码（仅 interactive）
                    ↓ 完成              ↓ 失败
              wake → 通知 (可能静默失败)    → ？（无人知道）
              report → 可审计             → 手动 attach → 翻 tmux 输出

【第二版：完整闭环 + 方法论约束】

Edward 发任务 → Dev Process 4 阶段流程
  Phase 1 需求 → Phase 2 设计 → [人工审批 ✋] → Phase 3 开发 → Phase 4 交付
                                                  ↓
                              Claude Code 执行（interactive 或 headless，可并行多个）
                                  ↓ 完成                        ↓ 失败/卡住
                            wake.sh                        三层自动发现
                            ├ 飞书 DM 直推                  ├ pane-died hook（秒级）
                            ├ 记录 TASK_HISTORY             ├ timeout-guard（2h 兜底）
                            └ gateway wake                 └ watchdog cron（10min 巡检）
                                  ↓                              ↓
                            OpenClaw 读取 report           diagnose-failure.sh
                            → 回复飞书                     → 结构化诊断 → 飞书告警
                                  ↓ gate check                   ↓
                            advance-phase.sh             → 人工决策：重试/修 prompt/放弃
                            → 自动质量门 → 推进下一阶段
                                  ↓ 每周一 9:30
                            analyze-history.sh → 周报 → 飞书 DM → 优化策略
                                  ↓ 经验沉淀
                            LESSONS_LEARNED → 跨项目知识库 → 下个项目的 prompt 自动引用
```

一张表看清差异：

| 维度 | 第一版 | 第二版 |
|------|-------|-------|
| 执行模式 | 仅 interactive | interactive + headless 双模式 |
| 过程日志 | 15s 采样快照 | stream-json 全量记录（headless） |
| 失败发现 | 靠人注意到 | 三层自动发现（秒级 → 分钟级 → 10min 巡检） |
| 失败诊断 | 手动 attach 猜 | diagnose-failure.sh 自动分析 8 种模式 |
| 通知可靠性 | 静默失败 | 直推 + watchdog 兜底 |
| 并行能力 | 2-3 个 | headless 可大量并行 |
| 诊断速度 | 5-15 分钟 | <30 秒 |
| 开发方法论 | 无（拿到 prompt 直接写） | 4 阶段 spec 驱动（需求→设计→开发→交付） |
| 需求对齐 | 靠 prompt 写得好 | MRD/PRD + 人工审批 |
| 技术设计 | 无 | DESIGN + TEST_PLAN + 人工审批 |
| 测试策略 | 交付协议里的 lint/build | TDD 工作流 + gate check |
| 变更追踪 | 无 | CHANGELOG + spec-change 自动通知 |
| 经验沉淀 | 无 | LESSONS_LEARNED + 跨项目知识库自动复用 |
| 交付物 | 代码 + report | 代码 + 7 份文档 + report + gate 审计 |
| 迭代方向 | 靠感觉 | 靠数据（周报 + 知识库 + 失败模式分析） |

---

## 6. 完整架构（更新后）

### 6.1 角色分工

三层不变，但每层都增厚了：

- **主 Agent（OpenClaw）**：调度 + 流程管控。现在不只是"派任务"，还要按 Dev Process 流程驱动 4 个阶段，在 Phase 1/2 等待人工审批，在 Phase 3/4 自动推进
- **子 Agent（Claude Code）**：执行引擎。行为受 Dev Process 注入的 CLAUDE.md 规则约束——必须先读 STATUS.md、只能做当前阶段允许的操作
- **可观测层（tmux + 监控）**：不只是"能 attach 看输出"，而是全量日志 + 三层自动监控 + 自动诊断

### 6.2 执行流程

```
start-tmux-task.sh（唯一入口）
  → 创建 tmux session cc-<label>
  → 模式选择：
      interactive → Claude TUI + capture-execution.sh（15s 采样）
      headless   → claude -p --output-format stream-json → runs/<label>/stream.jsonl
  → 自动配置三层防护：
      1. pane-died hook → on-session-exit.sh
      2. timeout-guard.sh（后台 2h）
      3. watchdog cron（已部署，每 10min）

正常完成 → wake.sh
  ├ 从 stream.jsonl 提取 Claude 的完成摘要
  ├ 飞书 DM 直推（openclaw message send）
  ├ 记录 TASK_HISTORY.jsonl
  └ gateway wake → OpenClaw 读取 report → 回复飞书

异常退出 → on-session-exit.sh → diagnose-failure.sh → 飞书告警
超时     → timeout-guard.sh   → diagnose-failure.sh → 飞书告警
兜底     → watchdog.sh cron   → 扫描所有 cc-* → 通知
```

### 6.3 Dev Process 流程

```
init-project.sh → 创建 docs/ 文档骨架 + 注入 CLAUDE.md 规则

dispatch-phase.sh --phase 1 → 生成需求阶段 prompt → start-tmux-task.sh
  → Claude Code 写 MRD + PRD（禁止写代码）
  → advance-phase.sh → phase1-gate-check → 人工审批 → 推进

dispatch-phase.sh --phase 2 → 生成设计阶段 prompt
  → Claude Code 写 DESIGN + TEST_PLAN（禁止写业务代码）
  → advance-phase.sh → phase2-gate-check → 人工审批 → 推进

dispatch-phase.sh --phase 3 --iteration N → 生成开发阶段 prompt
  → Claude Code TDD 迭代（先写测试再写实现）
  → advance-phase.sh → phase3-gate-check（lint/build/test/git clean） → 自动推进
  → [spec-change 检测] → 飞书通知

dispatch-phase.sh --phase 4 → 生成交付阶段 prompt
  → Claude Code 更新文档 + LESSONS_LEARNED
  → advance-phase.sh → phase4-gate-check → Project COMPLETED!
  → record-lesson.sh → 跨项目知识库
```

### 6.4 任务产物

所有产物统一存放在 `runs/<label>/` 目录（不再散落在 `/tmp`）：

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

每个任务一个目录，持久化保存，重启不丢失，按任务归档查看。

---

## 7. 适用与不适用（更新版）

适合：
- 并行 3 件以上的工程任务——三层监控保证不会"丢"任务
- 有一定复杂度的项目——Dev Process 4 阶段的投资回报率在复杂项目上最高
- 需要事后审计——stream-json + 7 份文档提供完整证据链
- 需要持续迭代——知识库 + 周报提供数据驱动的改进方向

不适合：
- 强依赖人类判断的产品决策
- 极简单的一次性任务——直接写 prompt 跑 Claude Code 就行，不需要 4 阶段流程
- 高频探索性调试（直接 IDE 更顺手）

---

## 8. 可直接照抄的实践建议（更新版）

1. **默认用 headless**。只有预判需要中途接管时才用 interactive。
2. **复杂项目用 Dev Process**。花 2 个阶段审批需求和设计，换来开发阶段大幅减少的返工。
3. **任务失败不要慌**。先看飞书通知里的诊断结论，再决定是修 prompt 重试还是手动介入。
4. **每周看一次周报**。周一 9:30 自动发送的统计报告是你优化派活策略的依据。
5. **先读 report 再读 diff**。低风险快速合，高风险再深入看 stream.jsonl 追溯过程。
6. **大胆并行**。Phase 3 的多个迭代、多个独立任务，都可以并行派发。
7. **记录经验**。每次踩坑用 `record-lesson.sh` 记录，下个项目会自动受益。
8. **"用自己改进自己"是可行的**。给 Claude Code 派一个"改进这套体系"的任务，review 产出，合并有用的部分。

---

## 9. 两步加起来意味着什么

第一版让你从"管理窗口"升级到"管理作业"。

第二版在两个正交维度上强化了这个作业系统：

**纵轴——执行质量（反馈闭环）**：
- 它知道自己在干什么（stream-json 全量记录）
- 它知道自己出了什么问题（三层监控自动发现）
- 它能说清楚为什么出问题（diagnose-failure.sh 自动分析）
- 它能用数据告诉你如何改进（周报 + 失败模式分析）

**横轴——开发规范（Dev Process）**：
- 它不会跳过需求分析直接写代码（Phase 1 gate）
- 它不会跳过技术设计直接实现（Phase 2 gate）
- 它会先写测试再写实现（Phase 3 TDD）
- 它会沉淀经验、追踪变更、交付完整文档（Phase 4 gate）

反馈闭环解决的是"做了之后出问题怎么办"。Dev Process 解决的是"怎么从一开始就少出问题"。一个是事后补救的安全网，一个是事前预防的方法论。两者叠加，才是一个**可持续运行的 AI 工程体系**。

**接下来要做的事：用 Dev Process 流程跑更多真实项目，积累 TASK_HISTORY 和知识库数据，让周报告诉你下一步该优化什么。**
