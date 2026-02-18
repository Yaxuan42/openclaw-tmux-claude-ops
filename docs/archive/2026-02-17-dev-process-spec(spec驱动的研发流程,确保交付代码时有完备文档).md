# Dev Process Skill — 完整技术规格文档

**日期**: 2026-02-17
**版本**: 1.1（含 runs/ 目录迁移更新）
**位置**: `skills/dev-process/`

---

## 1. 概述

Dev Process 是一个 spec-driven 的 4 阶段研发流程 skill，为 AI agent 提供结构化的开发方法论约束。它通过文档模板、gate check 脚本、阶段推进机制和知识沉淀系统，确保 AI 开发任务遵循需求→设计→开发→交付的完整研发流程。

**核心价值**：
- 将模糊需求转化为结构化、可测试的 spec 文档
- 用 gate check 机制保证每个阶段的质量
- 通过 TDD 工作流保证代码质量
- 知识沉淀闭环避免重复踩坑

**与 orchestrator 的关系**：解耦设计。`dispatch-phase.sh` 组合调用 orchestrator 的 `start-tmux-task.sh`，但 dev-process 也可独立使用（手动编辑文档 + 跑 gate check）。

---

## 2. 4 阶段流程

```
Phase 1 (需求)  →  Phase 2 (设计)  →  Phase 3 (开发)  →  Phase 4 (交付)
  MRD + PRD         DESIGN + TEST      TDD iterations      CHANGELOG + docs
  人工审批 ✋         人工审批 ✋          自动 gate ⚙️         自动 gate ⚙️
```

### 阶段行为规则

| 阶段 | 允许的操作 | 禁止的操作 | Gate 审批 |
|------|-----------|-----------|-----------|
| Phase 1 (需求) | 编辑 MRD.md, PRD.md | 写代码、改架构 | 人工 ✋ |
| Phase 2 (设计) | 编辑 DESIGN.md, TEST_PLAN.md, API_CONTRACT.md | 写业务代码 | 人工 ✋ |
| Phase 3 (开发) | 写代码、写测试、更新 CHANGELOG.md | 修改 PRD scope | 自动 ⚙️ |
| Phase 4 (交付) | 更新文档、写 LESSONS_LEARNED.md | 新增功能 | 自动 ⚙️ |

### STATUS.md 是唯一状态源

Agent 每次开始工作前**必须**先读取 `docs/STATUS.md`，确认当前阶段和待办事项。所有阶段推进通过 `advance-phase.sh` 自动更新 STATUS.md。

---

## 3. 目录结构

### Skill 自身结构

```
skills/dev-process/
├── SKILL.md                          ← Skill 描述（OpenClaw 入口）
├── scripts/
│   ├── init-project.sh               ← 项目初始化
│   ├── dispatch-phase.sh             ← 分发阶段任务（调用 orchestrator）
│   ├── advance-phase.sh              ← 检查 gate + 推进阶段
│   ├── phase1-gate-check.sh          ← Phase 1 gate（需求）
│   ├── phase2-gate-check.sh          ← Phase 2 gate（设计）
│   ├── phase3-gate-check.sh          ← Phase 3 gate（开发）
│   ├── phase4-gate-check.sh          ← Phase 4 gate（交付）
│   ├── notify-spec-change.sh         ← Spec 变更飞书通知
│   └── record-lesson.sh              ← 记录经验教训
├── templates/
│   ├── STATUS_TEMPLATE.md            ← 项目状态模板
│   ├── MRD_TEMPLATE.md               ← 市场需求文档模板
│   ├── PRD_TEMPLATE.md               ← 产品需求文档模板
│   ├── DESIGN_TEMPLATE.md            ← 技术设计文档模板
│   ├── TEST_PLAN_TEMPLATE.md         ← 测试计划模板
│   ├── API_CONTRACT_TEMPLATE.md      ← API 契约模板（Web 项目）
│   ├── CHANGELOG_TEMPLATE.md         ← 变更日志模板
│   ├── LESSONS_LEARNED_TEMPLATE.md   ← 经验教训模板
│   └── CLAUDE_MD_INJECT.md           ← 注入目标项目 CLAUDE.md 的规则
├── references/
│   ├── PROCESS_GUIDE.md              ← 4 阶段完整方法论
│   └── WEB_PROJECT_GUIDE.md          ← Web 项目专属规范
└── knowledge_base/
    └── cross_project_lessons.jsonl   ← 跨项目知识库
```

### 初始化后的目标项目结构

```
project/
├── docs/
│   ├── STATUS.md           ← 唯一状态源（阶段、迭代日志、决策、阻塞）
│   ├── MRD.md              ← Phase 1 产出（市场需求）
│   ├── PRD.md              ← Phase 1 产出（产品需求）
│   ├── DESIGN.md           ← Phase 2 产出（技术设计）
│   ├── TEST_PLAN.md        ← Phase 2 产出（测试计划）
│   ├── API_CONTRACT.md     ← Phase 2 产出（Web 项目专属）
│   ├── CHANGELOG.md        ← Phase 3/4 更新（变更日志）
│   └── LESSONS_LEARNED.md  ← Phase 4 更新（经验教训）
├── src/
├── tests/
└── CLAUDE.md               ← 注入了 Dev Process 规则
```

---

## 4. 脚本详细规格

### 4.1 `init-project.sh` — 项目初始化

**用途**：创建项目文档骨架，注入 CLAUDE.md 流程规则。

**命令**：
```bash
bash {baseDir}/scripts/init-project.sh \
  --project-dir <dir> --project-name <name> \
  [--project-type web|general] [--force]
```

**参数**：

| 参数 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `--project-dir` | 是 | - | 项目根目录 |
| `--project-name` | 是 | - | 项目名（自动 sanitize 为 `[a-zA-Z0-9_-]`） |
| `--project-type` | 否 | `general` | `web` 会额外创建 `API_CONTRACT.md` |
| `--force` | 否 | false | 覆盖已有 `docs/` 目录 |

**行为**：
1. 创建 `docs/`、`src/`、`tests/` 目录
2. 从 `templates/` 复制文档模板，替换 `{{PROJECT_NAME}}`、`{{CREATED_DATE}}`、`{{PROJECT_TYPE}}`
3. Web 项目额外复制 `API_CONTRACT_TEMPLATE.md`
4. 追加或创建 `CLAUDE.md`（如已存在且包含 Dev Process Rules 则跳过）

**幂等性**：默认不覆盖已有 `docs/`，需 `--force` 才覆盖。CLAUDE.md 注入检测已有规则则跳过。

---

### 4.2 `dispatch-phase.sh` — 阶段任务分发

**用途**：组合 orchestrator 的 `start-tmux-task.sh`，为指定阶段生成 prompt 并启动 tmux session。

**命令**：
```bash
bash {baseDir}/scripts/dispatch-phase.sh \
  --project-dir <dir> --phase <1|2|3|4> \
  [--iteration <N>] [--mode interactive|headless] \
  [--lint-cmd "..."] [--build-cmd "..."]
```

**参数**：

| 参数 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `--project-dir` | 是 | - | 项目根目录 |
| `--phase` | 是 | - | 阶段号 1-4 |
| `--iteration` | 否 | `1` | Phase 3 迭代序号 |
| `--mode` | 否 | `interactive` | `interactive` 或 `headless` |
| `--lint-cmd` | 否 | - | Lint 命令 |
| `--build-cmd` | 否 | - | Build 命令 |

**Label 命名约定**：

| Phase | Label 模式 |
|-------|-----------|
| 1 | `<project-name>-req` |
| 2 | `<project-name>-design` |
| 3 | `<project-name>-dev-iter-<N>` |
| 4 | `<project-name>-deliver` |

**Prompt 生成逻辑**：
- 每个阶段生成专属 prompt，包含方法论引用（`PROCESS_GUIDE.md`）、当前 STATUS.md 内容、相关文档摘要
- Phase 2 prompt 包含 PRD 摘要；Phase 3 包含 DESIGN + TEST_PLAN 摘要
- Web 项目 Phase 2 额外引用 `WEB_PROJECT_GUIDE.md`
- 自动附加最近 5 条历史经验教训

**Prompt 文件位置**（已更新）：
- 存放在 orchestrator 的 `runs/<label>/prompt.txt`（不再是 `/tmp`）

**前置检查**：
- 验证 STATUS.md 存在
- 检查当前阶段是否与请求阶段匹配（不匹配仅警告，不阻断）

---

### 4.3 `advance-phase.sh` — Gate Check + 阶段推进

**用途**：运行当前阶段的 gate check，通过后推进 STATUS.md 到下一阶段。

**命令**：
```bash
bash {baseDir}/scripts/advance-phase.sh \
  --project-dir <dir> [--force] \
  [--lint-cmd "..."] [--build-cmd "..."] [--iteration <N>]
```

**参数**：

| 参数 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `--project-dir` | 是 | - | 项目根目录 |
| `--force` | 否 | false | P1/P2 人工审批确认 |
| `--lint-cmd` | 否 | - | P3 gate 用 |
| `--build-cmd` | 否 | - | P3 gate 用 |
| `--iteration` | 否 | - | P3 gate 用 |

**流程**：
1. 从 STATUS.md 读取当前阶段
2. 调用对应 gate check 脚本
3. Gate 失败 → 输出失败原因，exit 1
4. P1/P2 gate 通过但未 `--force` → 提示人工确认后再跑
5. P3 特殊处理：检查 STATUS.md 中是否有未完成 checklist 项；检测 spec-change 并触发通知
6. Gate 通过 + 确认 → 更新 STATUS.md（Current Phase + Completed Phases）
7. Phase 4 完成 → 标记 `**COMPLETED** ✅`

---

### 4.4 Gate Check 脚本

所有 gate 脚本统一接口：`exit 0` = pass, `exit 1` = fail，JSON 输出。

#### `phase1-gate-check.sh`

```bash
bash {baseDir}/scripts/phase1-gate-check.sh --project-dir <dir>
```

**检查项**：

| Check | 说明 |
|-------|------|
| `mrd_exists` | MRD.md 存在且 Market Problem 部分有实质内容（>10 行，非纯模板） |
| `prd_exists` | PRD.md 存在 |
| `prd_user_stories` | PRD 包含 User Stories 节，有 `US-xxx` 条目 |
| `prd_scope` | PRD 包含 Scope 节（In Scope 有内容） |
| `prd_success_criteria` | PRD 包含 Success Criteria 节（有可勾选项） |

**输出**：`humanApprovalRequired: true`

#### `phase2-gate-check.sh`

```bash
bash {baseDir}/scripts/phase2-gate-check.sh --project-dir <dir>
```

**检查项**：

| Check | 说明 |
|-------|------|
| `design_exists` | DESIGN.md 存在 |
| `design_architecture` | DESIGN.md Architecture 节有实质内容 |
| `design_data_model` | DESIGN.md Data Model 节存在 |
| `test_plan_exists` | TEST_PLAN.md 存在 |
| `test_plan_cases` | TEST_PLAN.md 有 `TC-xxx` 条目 |
| `test_plan_coverage` | TEST_PLAN.md 有 Coverage Targets 节 |
| `api_contract`（Web） | API_CONTRACT.md 有 Endpoints 节（仅 Web 项目） |

**输出**：`humanApprovalRequired: true`

#### `phase3-gate-check.sh`

```bash
bash {baseDir}/scripts/phase3-gate-check.sh \
  --project-dir <dir> [--iteration <N>] [--lint-cmd "..."] [--build-cmd "..."]
```

**检查项**：

| Check | 说明 |
|-------|------|
| `tests_pass` | `npm test` / `pytest` 通过（自动检测项目类型） |
| `lint` | lint 命令通过（未配置则 skip） |
| `build` | build 命令通过（未配置则 skip） |
| `status_updated` | STATUS.md Iteration Log 有条目 |
| `git_clean` | 工作目录无未提交变更 |
| `spec_change`（信息性） | CHANGELOG.md 中检测到 `[spec-change]` 标签 |

**输出**：`humanApprovalRequired: false`, `specChangeDetected: true/false`

**Gate name**：`phase3`（无迭代号）或 `phase3-iter-N`

#### `phase4-gate-check.sh`

```bash
bash {baseDir}/scripts/phase4-gate-check.sh --project-dir <dir>
```

**检查项**：

| Check | 说明 |
|-------|------|
| `changelog_content` | CHANGELOG.md 有实质条目（`^- .+` 非空行） |
| `docs_complete` | 7 个必需文档全部存在 |
| `lessons_updated` | LESSONS_LEARNED.md 有日期行条目（`^\| [0-9]{4}-`） |
| `git_clean` | 工作目录无未提交变更 |

**输出**：`humanApprovalRequired: false`

#### Gate 输出 JSON 格式

```json
{
  "gate": "phase3-iter-2",
  "passed": true,
  "checks": [
    {"name": "tests_pass", "ok": true, "detail": "Tests passed: 42 passing"},
    {"name": "lint", "ok": true, "detail": "Lint passed"}
  ],
  "specChangeDetected": false,
  "humanApprovalRequired": false
}
```

---

### 4.5 `notify-spec-change.sh` — Spec 变更通知

**用途**：从 CHANGELOG.md 提取 `[spec-change]` 条目，通过飞书 DM 通知。

**命令**：
```bash
bash {baseDir}/scripts/notify-spec-change.sh \
  --project-dir <dir> --label <label> [--iteration <N>]
```

**行为**：
- 用 `rg` 提取 `[spec-change]` 行
- 通过 `openclaw message send --type feishu_dm` 发送通知
- 目标：Edward（hardcoded Feishu user ID `ou_e5eb026fddb0fe05895df71a56f65e2f`）
- 无 spec-change 时静默退出

**触发时机**：`advance-phase.sh` 在 Phase 3 gate 检测到 `specChangeDetected: true` 时自动调用。

---

### 4.6 `record-lesson.sh` — 经验记录

**用途**：记录经验到项目级和跨项目知识库。

**命令**：
```bash
bash {baseDir}/scripts/record-lesson.sh \
  --project-dir <dir> \
  --category Architecture|Code|Testing|Process \
  --problem "描述问题" \
  --solution "解决方案" \
  [--severity low|medium|high]
```

**行为**：
1. 追加表格行到 `docs/LESSONS_LEARNED.md` 对应分类节
2. 追加 JSON 行到 `knowledge_base/cross_project_lessons.jsonl`

**LESSONS_LEARNED.md 追加逻辑**：
- 查找 `## <Category>` 节
- 在该节的表格后追加新行
- 若分类不存在，在文件末尾新建分类节

**cross_project_lessons.jsonl 格式**：
```json
{
  "timestamp": "2026-02-17T10:00:00Z",
  "project": "my-project",
  "category": "Code",
  "problem": "...",
  "solution": "...",
  "severity": "medium"
}
```

---

## 5. 文档模板规格

### 5.1 STATUS_TEMPLATE.md

项目状态唯一来源。

| 节 | 内容 |
|----|------|
| Current Phase | 当前阶段标记（`**Phase N: xxx** ⬅️ 当前阶段`） |
| Completed Phases | Phase 1-4 checkbox（自动更新） |
| Iteration Log | 表格：#, Date, Phase, Summary, Gate Result |
| Next Step | 下一步指引 |
| Key Decisions | 表格：Date, Decision, Rationale, Impact |
| Blockers | 阻塞清单 |

### 5.2 MRD_TEMPLATE.md（市场需求）

| 节 | 内容 |
|----|------|
| Market Problem | 核心问题一句话描述 + 数据支撑 |
| Target Users | 表格：用户类型, 痛点, 使用场景, 优先级 |
| Business Goals | 量化业务目标 |
| Success Metrics | 表格：指标, 当前值, 目标值, 度量方法 |
| Constraints | 时间/资源/技术/合规约束 |
| Competitive Analysis | 竞品分析（可选） |
| Open Questions | 待确认问题 |

### 5.3 PRD_TEMPLATE.md（产品需求）

| 节 | 内容 |
|----|------|
| Overview | 一句话产品目标 |
| User Stories | 表格：ID(US-xxx), 角色, 需求, 验收标准, 优先级 |
| Functional Requirements | 每个功能含输入/处理/输出/边界条件 |
| Non-Functional Requirements | 表格：类别, 需求, 指标 |
| Scope | In Scope / Out of Scope |
| Success Criteria | 可测试的验收标准 checklist |
| Dependencies | 外部依赖 |
| Milestones | 表格：里程碑, 预期日期, 交付物 |

### 5.4 DESIGN_TEMPLATE.md（技术设计）

| 节 | 内容 |
|----|------|
| Architecture | ASCII/Mermaid 架构图 + 组件职责表 |
| Data Model | 核心数据结构和字段描述 |
| API Design | 内部接口表：Interface, Input, Output, Notes |
| Error Handling | 表格：错误类型, 处理策略, 用户可见行为 |
| Security Considerations | 校验/认证/数据保护/日志脱敏 checklist |
| Tech Stack | 表格：层级, 技术, 版本, 理由 |
| Migration Plan | 数据/接口迁移策略 |
| Risks & Mitigations | 表格：风险, 影响, 缓解措施 |
| Open Design Questions | 待决设计问题 |

### 5.5 TEST_PLAN_TEMPLATE.md（测试计划）

| 节 | 内容 |
|----|------|
| Test Strategy | 表格：层级, 工具, 覆盖目标, 执行时机 |
| Test Cases | 表格：ID(TC-xxx), 类型, 描述, 输入, 预期输出, 优先级, 状态 |
| Coverage Targets | 表格：模块, 行覆盖目标, 当前覆盖 |
| TDD Workflow | Red-Green-Refactor 循环 + 迭代 checklist |
| Test Data | 测试数据准备策略 |
| Test Environment | 测试环境配置 |

### 5.6 API_CONTRACT_TEMPLATE.md（Web 项目专属）

| 节 | 内容 |
|----|------|
| Base URL | 开发/生产环境端点 |
| Authentication | 表格：方法, Header, 格式 |
| Response Format | 标准成功/错误 JSON 结构 |
| Endpoints | 每个端点详细定义：参数、成功/错误响应 |
| Error Codes | 表格：Code, HTTP Status, 描述, 处理建议 |
| TypeScript Interfaces | 前后端共享类型定义 |
| Rate Limiting | 限流策略 |
| Versioning | API 版本管理策略 |

### 5.7 CHANGELOG_TEMPLATE.md

- 标签约定：`[spec-change]`（偏离原始 spec）、`[breaking]`（破坏性变更）、`[security]`（安全修复）
- 分类：Added / Changed / Fixed / Removed / Spec Changes

### 5.8 LESSONS_LEARNED_TEMPLATE.md

- 四个分类节：Architecture / Code / Testing / Process
- 每个分类一个表格：Date, Problem, Root Cause, Solution, Severity
- Phase 4 必须更新

### 5.9 CLAUDE_MD_INJECT.md

注入目标项目 CLAUDE.md 的规则片段：
- 启动行为（必读 STATUS.md）
- 阶段行为规则表
- Spec 变更协议
- 交付检查清单
- 知识沉淀触发条件

---

## 6. 方法论参考文档

### 6.1 PROCESS_GUIDE.md

4 阶段完整方法论，供 agent 参考。核心原则：

1. **Spec 先行**：先写文档再写代码
2. **TDD 驱动**：先写测试再写实现
3. **迭代交付**：小步快跑，每个迭代完整 Red-Green-Refactor
4. **知识沉淀**：每次踩坑都记录

每个阶段定义了目标、产出物、编写流程、Gate 条件。

### 6.2 WEB_PROJECT_GUIDE.md

Web 项目专属规范，包含：

- **前后端分离约定**：目录结构、协作原则
- **API 设计规范**：RESTful 约定、统一响应格式（`ApiResponse<T>`）、分页约定、错误码体系（VALIDATION_ / AUTH_ / RESOURCE_ / SYSTEM_）
- **安全清单**：10 项必检项（输入验证、SQL 注入、XSS、CSRF、认证、授权、CORS、Rate Limiting、Secrets、依赖安全）
- **前端规范**：状态管理选型、性能基线（LCP < 2.5s、FID < 100ms、CLS < 0.1）
- **后端规范**：中间件顺序、数据库约定、结构化日志规范

---

## 7. 知识沉淀系统

### 两级知识库

| 层级 | 文件 | 范围 |
|------|------|------|
| 项目级 | `<project>/docs/LESSONS_LEARNED.md` | 当前项目 |
| 跨项目 | `knowledge_base/cross_project_lessons.jsonl` | 所有项目 |

### 记录触发条件

- 花超过 30 分钟解决的问题
- 在多个方案中做出选择时
- 发现与预期不符的行为
- 第三方库/API 的坑

### 经验复用

`dispatch-phase.sh` 生成 prompt 时自动读取最近 5 条经验教训，附加到 prompt 末尾的"历史经验"节。

---

## 8. Spec 变更检测协议

开发过程中发现 spec 不合理时的处理流程：

```
开发中发现问题
  ↓
在 CHANGELOG.md 记录 [spec-change] 标签
  ↓
在 STATUS.md Key Decisions 表记录决策
  ↓
继续开发（不阻塞）
  ↓
advance-phase.sh Phase 3 gate 检测到 specChangeDetected
  ↓
自动调用 notify-spec-change.sh
  ↓
飞书 DM 通知 Edward → 人工审核
```

---

## 9. 与 Orchestrator 集成

### 调用链路

```
dispatch-phase.sh
  ├── 读取 STATUS.md（验证阶段）
  ├── 生成 prompt → runs/<label>/prompt.txt
  └── 调用 start-tmux-task.sh
        ├── --label <project>-<phase>
        ├── --workdir <project-dir>
        ├── --prompt-file runs/<label>/prompt.txt
        └── --mode interactive|headless
```

### 任务产物位置（已更新）

任务运行产物统一存放在 orchestrator 的 `runs/<label>/` 目录：

| 文件 | 说明 |
|------|------|
| `runs/<label>/prompt.txt` | 阶段 prompt |
| `runs/<label>/stream.jsonl` | headless 模式流输出 |
| `runs/<label>/completion-report.json` | 完成报告 |
| `runs/<label>/execution-events.jsonl` | 执行事件流 |
| `runs/<label>/execution-summary.json` | 执行摘要 |

（完整文件列表见 `docs/2026-02-17-runs-dir-migration.md`）

---

## 10. 完整使用流程

### 10.1 初始化

```bash
# 创建项目并初始化文档
bash skills/dev-process/scripts/init-project.sh \
  --project-dir /path/to/my-project \
  --project-name my-project \
  --project-type web
```

### 10.2 Phase 1: 需求分析

```bash
# 分发 Phase 1 任务
bash skills/dev-process/scripts/dispatch-phase.sh \
  --project-dir /path/to/my-project --phase 1 --mode headless

# 等待任务完成后，检查 gate
bash skills/dev-process/scripts/advance-phase.sh \
  --project-dir /path/to/my-project

# 人工审核通过后
bash skills/dev-process/scripts/advance-phase.sh \
  --project-dir /path/to/my-project --force
```

### 10.3 Phase 2: 技术设计

```bash
bash skills/dev-process/scripts/dispatch-phase.sh \
  --project-dir /path/to/my-project --phase 2 --mode headless

# gate + 人工审批
bash skills/dev-process/scripts/advance-phase.sh \
  --project-dir /path/to/my-project --force
```

### 10.4 Phase 3: 开发迭代

```bash
# 迭代 1
bash skills/dev-process/scripts/dispatch-phase.sh \
  --project-dir /path/to/my-project --phase 3 --iteration 1 \
  --lint-cmd "npm run lint" --build-cmd "npm run build"

# 检查 gate（自动）
bash skills/dev-process/scripts/advance-phase.sh \
  --project-dir /path/to/my-project \
  --lint-cmd "npm run lint" --build-cmd "npm run build" --iteration 1

# 如果还需要更多迭代
bash skills/dev-process/scripts/dispatch-phase.sh \
  --project-dir /path/to/my-project --phase 3 --iteration 2 \
  --lint-cmd "npm run lint" --build-cmd "npm run build"

# 所有迭代完成后推进
bash skills/dev-process/scripts/advance-phase.sh \
  --project-dir /path/to/my-project --force
```

### 10.5 Phase 4: 交付验收

```bash
bash skills/dev-process/scripts/dispatch-phase.sh \
  --project-dir /path/to/my-project --phase 4 --mode headless

# gate（自动）
bash skills/dev-process/scripts/advance-phase.sh \
  --project-dir /path/to/my-project
# → 输出 "Project COMPLETED!"
```

### 10.6 经验记录（任何时候）

```bash
bash skills/dev-process/scripts/record-lesson.sh \
  --project-dir /path/to/my-project \
  --category Code \
  --problem "ESM import 路径必须带 .js 后缀" \
  --solution "tsconfig 配置 moduleResolution: node16" \
  --severity medium
```

---

## 11. Shell 脚本约定

与 orchestrator 一致：

- **Shebang**: `#!/usr/bin/env bash` + `set -euo pipefail`
- **Arg parsing**: `while [[ $# -gt 0 ]]; do case "$1" in`
- **SCRIPT_DIR**: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- **JSON 输出**: 全部使用 `jq -n --arg/--argjson`
- **Pattern matching**: `rg -q` （不用 grep）
- **macOS/GNU 兼容**: `sed` 操作检测 `--version` 区分 GNU/macOS

---

## 12. 设计原则

1. **STATUS.md 是唯一状态源** — agent 每次先读 STATUS.md
2. **与 orchestrator 解耦** — `dispatch-phase.sh` 纯粹组合调用，不修改 orchestrator 脚本
3. **独立可用** — 可手动 init → 编辑文档 → 跑 gate，不依赖 orchestrator
4. **Gate 输出 JSON** — 便于程序化解析
5. **知识沉淀闭环** — 项目级 + 跨项目级经验记录
6. **Prompt 是中文** — 任务指令使用中文，JSON 字段名和脚本输出使用英文
7. **人工审批节点明确** — P1/P2 需人工 `--force`，P3/P4 自动通过

---

## 13. 变更日志

| 日期 | 变更 |
|------|------|
| 2026-02-17 | 初始版本 |
| 2026-02-17 | `dispatch-phase.sh` prompt 文件从 `/tmp` 迁移到 orchestrator `runs/<label>/` 目录 |
