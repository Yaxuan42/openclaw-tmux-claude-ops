# Spec-Driven 研发流程方法论

> 本文档供 AI agent 参考，定义 4 阶段 spec-driven 研发流程。

## 核心原则

1. **Spec 先行**：先写文档再写代码，文档是代码的"合同"
2. **TDD 驱动**：先写测试再写实现，测试是 spec 的可执行形式
3. **迭代交付**：小步快跑，每个迭代都是完整的 Red-Green-Refactor 循环
4. **知识沉淀**：每次踩坑都记录，避免重复犯错

---

## Phase 1: 需求分析

### 目标
将模糊的想法转化为清晰、可测试的需求文档。

### 产出物
- `docs/MRD.md` — 市场需求文档（为什么做）
- `docs/PRD.md` — 产品需求文档（做什么）

### MRD 编写流程

1. **明确问题**：用一句话描述要解决的核心问题
2. **定义用户**：画出目标用户画像和使用场景
3. **设定指标**：定义可量化的成功指标
4. **识别约束**：列出时间、资源、技术约束

### PRD 编写流程

1. **提炼 User Stories**：从 MRD 中提取用户故事，格式为"作为...我希望...以便..."
2. **定义功能需求**：每个 FR 包含输入、处理、输出、边界条件
3. **定义非功能需求**：性能、安全、可用性指标
4. **划定范围**：明确 In Scope 和 Out of Scope
5. **设定验收标准**：可测试的 Success Criteria

### 好 PRD 的标准

- **可测试**：每个需求都能对应至少一个测试用例
- **无歧义**：避免"应该"、"可能"等模糊词，用"必须"、"当...则..."
- **有边界**：明确什么不做，比"做什么"更重要
- **可度量**：性能指标有具体数字，不是"足够快"

### Gate 条件（人工审批）

- MRD.md 存在且有实质内容
- PRD.md 包含 User Stories、Scope、Success Criteria
- 人工确认需求合理性

---

## Phase 2: 技术设计

### 目标
将 PRD 转化为可实现的技术方案。

### 产出物
- `docs/DESIGN.md` — 技术设计文档
- `docs/TEST_PLAN.md` — 测试计划
- `docs/API_CONTRACT.md` — API 契约（Web 项目）

### DESIGN.md 编写流程

1. **架构设计**：画出整体架构，明确组件职责和交互
2. **数据模型**：定义核心数据结构和数据流
3. **接口设计**：定义组件间的内部接口
4. **错误处理**：列出错误类型和处理策略
5. **安全设计**：输入验证、认证授权、数据保护
6. **技术选型**：每个选型给出理由

### TEST_PLAN.md 编写流程

1. **测试策略**：确定测试层级（单元/集成/E2E）和工具
2. **测试用例**：从 PRD 的 Success Criteria 推导测试用例
3. **覆盖目标**：设定各模块的覆盖率目标
4. **TDD 工作流**：定义 Red-Green-Refactor 循环的具体操作

### API_CONTRACT.md 编写流程（Web 项目）

1. **统一格式**：定义请求/响应格式、错误码体系
2. **端点定义**：每个端点包含方法、路径、参数、响应
3. **类型定义**：TypeScript 接口（前后端共享）
4. **限流策略**：如需要

### Gate 条件（人工审批）

- DESIGN.md 包含 Architecture 和 Data Model
- TEST_PLAN.md 包含 Test Cases 和 Coverage Targets
- API_CONTRACT.md 存在且有内容（Web 项目）
- 人工确认设计方案合理性

---

## Phase 3: 开发迭代

### 目标
按照 spec 实现功能，通过 TDD 保证质量。

### TDD 工作流

每个迭代循环：

```
1. 从 TEST_PLAN.md 选取下一组测试用例
2. Red:    写失败测试（明确预期行为）
3. Green:  写最少代码让测试通过
4. Refactor: 重构代码，保持测试绿色
5. 更新 STATUS.md 迭代日志
6. 检查覆盖率是否达标
```

### 迭代模型

- 每个迭代是一个独立的 orchestrator task：`<project>-dev-iter-N`
- 每个迭代聚焦一组相关的功能点
- 迭代结束时运行 gate check

### 何时停止迭代

- 所有 TEST_PLAN.md 中的测试用例已实现并通过
- 覆盖率达到目标
- lint 和 build 通过
- 没有已知的 P0/P1 bug

### Spec 变更检测协议

开发过程中可能发现 spec 不合理或遗漏，处理流程：

1. **记录变更**：在 CHANGELOG.md 中使用 `[spec-change]` 标签
2. **说明原因**：为什么需要偏离原始 spec
3. **评估影响**：变更对其他功能的影响范围
4. **继续开发**：不阻塞，异步通知会自动触发
5. **通知触发**：gate check 检测到 `[spec-change]` → Feishu 通知

### Gate 条件（自动）

- 测试通过（`npm test` 或自定义命令）
- lint 通过
- build 通过
- STATUS.md 迭代日志已更新
- 工作目录干净（git clean）
- 如有 `[spec-change]` → 触发 Feishu 通知

---

## Phase 4: 交付验收

### 目标
确保产出物完整、文档更新、知识沉淀。

### 交付检查清单

1. **代码完整性**
   - [ ] 所有功能已实现
   - [ ] 所有测试通过
   - [ ] lint/build 通过
   - [ ] 无未提交的变更

2. **文档更新**
   - [ ] CHANGELOG.md 有实质内容
   - [ ] STATUS.md 标记为 COMPLETED
   - [ ] LESSONS_LEARNED.md 已更新
   - [ ] DESIGN.md 反映最终实现（如有变更）

3. **知识沉淀**
   - [ ] 重要经验写入 LESSONS_LEARNED.md
   - [ ] 高价值经验同步到跨项目知识库

### CHANGELOG 写法

- 按 Added/Changed/Fixed/Removed 分类
- 每条记录说明"什么变了"和"为什么变"
- `[spec-change]` 标签的条目需要额外说明影响

### Gate 条件（自动）

- CHANGELOG.md 有实质内容（不只是模板）
- 所有 docs/ 下的文档都存在
- LESSONS_LEARNED.md 已更新
- 工作目录干净

---

## 横切关注点

### 知识沉淀协议

**何时记录**：
- 花超过 30 分钟解决的问题
- 在多个方案中做出选择时
- 发现与预期不符的行为
- 第三方库/API 的坑

**如何记录**：
- 项目级：`docs/LESSONS_LEARNED.md`（当前项目）
- 跨项目：`knowledge_base/cross_project_lessons.jsonl`（通过 `record-lesson.sh`）

**记录格式**：
- Problem：遇到了什么问题
- Root Cause：根本原因是什么
- Solution：怎么解决的
- Severity：影响程度（low/medium/high）

### 决策日志

重要的设计/技术决策记录在 STATUS.md 的 Key Decisions 表格中：
- 决策内容
- 选择理由
- 影响范围

### 文档与代码的一致性

- Phase 3 中如果 spec 变更，同步更新对应文档
- Phase 4 验收时检查文档是否反映最终实现
- 不追求"文档完美"，但追求"文档准确"
