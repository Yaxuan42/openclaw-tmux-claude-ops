---
name: dev-process
description: Spec-driven 4-phase development process (需求→设计→开发→交付) with structured docs, TDD workflow, gate checks, and knowledge retention. Use when launching coding projects that need methodology discipline, not just task dispatch.
---

# Dev Process — Spec-Driven 研发流程

提供 4 阶段 spec-driven 研发方法论，约束 AI agent 遵循统一流程，产出结构化文档，支持 TDD 和知识沉淀。与 claude-code-orchestrator 解耦，可独立使用。

## 4 阶段流程

```
Phase 1 (需求)  →  Phase 2 (设计)  →  Phase 3 (开发)  →  Phase 4 (交付)
  MRD + PRD         DESIGN + TEST      TDD iterations      CHANGELOG + docs
  人工审批 ✋         人工审批 ✋          自动 gate ⚙️         自动 gate ⚙️
```

## Quick Start

### 1. 初始化项目

```bash
bash {baseDir}/scripts/init-project.sh \
  --project-dir /path/to/project \
  --project-name my-project \
  --project-type web    # or "general"
```

创建 `docs/` 目录和所有文档模板，注入 CLAUDE.md 流程规则。

### 2. 分发阶段任务（通过 orchestrator）

```bash
# Phase 1: 需求分析
bash {baseDir}/scripts/dispatch-phase.sh \
  --project-dir /path/to/project --phase 1 --mode headless

# Phase 2: 技术设计
bash {baseDir}/scripts/dispatch-phase.sh \
  --project-dir /path/to/project --phase 2 --mode headless

# Phase 3: 开发迭代 (可多次)
bash {baseDir}/scripts/dispatch-phase.sh \
  --project-dir /path/to/project --phase 3 --iteration 1 \
  --lint-cmd "npm run lint" --build-cmd "npm run build"

# Phase 4: 交付验收
bash {baseDir}/scripts/dispatch-phase.sh \
  --project-dir /path/to/project --phase 4 --mode headless
```

### 3. 检查 gate 并推进阶段

```bash
# 检查当前阶段的 gate
bash {baseDir}/scripts/advance-phase.sh --project-dir /path/to/project

# P1/P2 需要人工审批后加 --force
bash {baseDir}/scripts/advance-phase.sh --project-dir /path/to/project --force
```

## 脚本说明

### `init-project.sh`

初始化项目文档骨架。

```bash
bash {baseDir}/scripts/init-project.sh \
  --project-dir <dir> --project-name <name> \
  [--project-type web|general] [--force]
```

- 创建 `docs/`、`src/`、`tests/` 目录
- 复制文档模板并填充项目名和日期
- Web 项目额外生成 `API_CONTRACT.md`
- 追加/创建 CLAUDE.md 流程规则

### `dispatch-phase.sh`

组合 orchestrator 的 `start-tmux-task.sh` 分发阶段任务。

```bash
bash {baseDir}/scripts/dispatch-phase.sh \
  --project-dir <dir> --phase <1|2|3|4> \
  [--iteration <N>] [--mode interactive|headless] \
  [--lint-cmd "..."] [--build-cmd "..."]
```

- 读取 STATUS.md 验证当前阶段
- 生成阶段专属 prompt（包含方法论引用、当前状态、历史经验）
- 调用 `start-tmux-task.sh` 启动 tmux session
- Label 约定：`<name>-req` / `<name>-design` / `<name>-dev-iter-N` / `<name>-deliver`

### `advance-phase.sh`

检查 gate + 推进 STATUS.md。

```bash
bash {baseDir}/scripts/advance-phase.sh \
  --project-dir <dir> [--force] \
  [--lint-cmd "..."] [--build-cmd "..."] [--iteration <N>]
```

- P1/P2：gate 通过后需 `--force` 才推进（人工审批）
- P3：gate 通过后检查是否还有未完成任务
- P4：gate 通过 → 标记 COMPLETED
- 自动更新 STATUS.md 的 Current Phase 和 Completed Phases

### Gate Check 脚本

所有 gate 脚本：`exit 0` = pass, `exit 1` = fail，JSON 输出。

| 脚本 | 检查项 | 审批 |
|------|--------|------|
| `phase1-gate-check.sh` | MRD 有内容, PRD 有 User Stories/Scope/Success Criteria | 人工 ✋ |
| `phase2-gate-check.sh` | DESIGN 有 Architecture/Data Model, TEST_PLAN 有 Test Cases/Coverage | 人工 ✋ |
| `phase3-gate-check.sh` | 测试通过, lint/build 通过, STATUS 更新, git clean, spec-change 检测 | 自动 ⚙️ |
| `phase4-gate-check.sh` | CHANGELOG 有内容, 所有 docs 存在, LESSONS_LEARNED 更新, git clean | 自动 ⚙️ |

```bash
bash {baseDir}/scripts/phase3-gate-check.sh \
  --project-dir <dir> [--iteration <N>] [--lint-cmd "..."] [--build-cmd "..."]
```

输出格式：
```json
{
  "gate": "phase3-iter-2",
  "passed": true,
  "checks": [{"name": "tests_pass", "ok": true, "detail": "..."}],
  "specChangeDetected": false,
  "humanApprovalRequired": false
}
```

### `notify-spec-change.sh`

检测并发送 spec 变更通知。

```bash
bash {baseDir}/scripts/notify-spec-change.sh \
  --project-dir <dir> --label <label> [--iteration <N>]
```

从 CHANGELOG.md 提取 `[spec-change]` 条目，通过 Feishu DM 通知 Edward。

### `record-lesson.sh`

记录经验到项目和跨项目知识库。

```bash
bash {baseDir}/scripts/record-lesson.sh \
  --project-dir <dir> \
  --category Architecture|Code|Testing|Process \
  --problem "描述问题" \
  --solution "解决方案" \
  [--severity low|medium|high]
```

- 追加项目的 `docs/LESSONS_LEARNED.md`
- 追加 `knowledge_base/cross_project_lessons.jsonl`

## 文档结构

初始化后项目目录：

```
project/
├── docs/
│   ├── STATUS.md           ← 唯一状态源
│   ├── MRD.md              ← Phase 1 产出
│   ├── PRD.md              ← Phase 1 产出
│   ├── DESIGN.md           ← Phase 2 产出
│   ├── TEST_PLAN.md        ← Phase 2 产出
│   ├── API_CONTRACT.md     ← Phase 2 产出 (web only)
│   ├── CHANGELOG.md        ← Phase 3/4 更新
│   └── LESSONS_LEARNED.md  ← Phase 4 更新
├── src/
├── tests/
└── CLAUDE.md               ← 注入了流程规则
```

## 参考文档

| 文件 | 用途 |
|------|------|
| `references/PROCESS_GUIDE.md` | 4 阶段完整方法论（agent 参考） |
| `references/WEB_PROJECT_GUIDE.md` | Web 项目专属规范 |

## 设计原则

1. **STATUS.md 是唯一状态源**：agent 每次先读 STATUS.md
2. **与 orchestrator 解耦**：`dispatch-phase.sh` 纯粹组合调用，不修改 orchestrator 脚本
3. **独立可用**：可手动 init → 编辑文档 → 跑 gate，不依赖 orchestrator
4. **Gate 输出 JSON**：便于程序化解析
5. **知识沉淀闭环**：项目级 + 跨项目级经验记录
