
## Dev Process Rules (auto-injected by dev-process skill)

### 启动行为

每次开始工作前，**必须**先读取 `docs/STATUS.md`，确认当前阶段和待办事项。根据当前阶段执行对应行为：

### 阶段行为规则

| 阶段 | 允许的操作 | 禁止的操作 |
|------|-----------|-----------|
| Phase 1 (需求) | 编辑 MRD.md, PRD.md | 写代码、改架构 |
| Phase 2 (设计) | 编辑 DESIGN.md, TEST_PLAN.md, API_CONTRACT.md | 写业务代码 |
| Phase 3 (开发) | 写代码、写测试、更新 CHANGELOG.md | 修改 PRD scope |
| Phase 4 (交付) | 更新文档、写 LESSONS_LEARNED.md | 新增功能 |

### Spec 变更协议

在 Phase 3 开发过程中，如果发现需要偏离 PRD/DESIGN 的原始设计：

1. 在 `docs/CHANGELOG.md` 中用 `[spec-change]` 标签记录变更原因和影响
2. 在 `docs/STATUS.md` 的 Key Decisions 表格中记录决策
3. 继续开发，不要等待人工审批（异步通知会自动触发）

### 交付检查清单

Phase 4 完成前确认：

- [ ] 所有测试通过
- [ ] CHANGELOG.md 已更新
- [ ] LESSONS_LEARNED.md 已更新
- [ ] STATUS.md 迭代日志已更新
- [ ] 无未提交的代码变更

### 知识沉淀

遇到以下情况时，立即记录到 `docs/LESSONS_LEARNED.md`：

- 踩坑：花超过 30 分钟解决的问题
- 设计决策：在多个方案中做出选择时
- 意外发现：与预期不符的行为
