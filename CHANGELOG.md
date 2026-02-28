# Changelog

## 2026.2.28

### Changes (EN)

- Claude Code Orchestrator received major upgrades: event-driven tmux hooks (`on-session-exit.sh`, `timeout-guard.sh`), headless mode with `stream-json`, failure diagnosis, and task history analytics.
- Added **dev-process** skill with a 4-phase spec-driven workflow (requirements → design → implementation → delivery), quality gates, templates, and cross-project lessons recording.
- Improved reliability and security in orchestrator scripts:
  - fixed SSH wake quoting/variable expansion,
  - added safer parameter validation (e.g. label whitelist),
  - made notification target configurable via env var,
  - cleaned repository hygiene (`.DS_Store` removal + `.gitignore`).
- Updated documentation and runbooks across Chinese/English READMEs and final docs.

### 变更（中文）

- Claude Code Orchestrator 完成一轮大升级：引入事件驱动的 tmux hook（`on-session-exit.sh`、`timeout-guard.sh`）、支持 headless + `stream-json`、失败自动诊断、任务历史分析。
- 新增 **dev-process** 技能，提供 4 阶段 Spec 驱动流程（需求 → 设计 → 开发 → 交付），并配套质量门禁、模板和跨项目经验沉淀机制。
- 编排器脚本在可靠性与安全性上完成修复：
  - 修复 SSH wake 引号与变量展开问题；
  - 增加参数校验（如 label 白名单）；
  - 通知目标改为环境变量可配置；
  - 清理仓库卫生（移除 `.DS_Store` 并补充 `.gitignore`）。
- 中英文 README、Runbook 与最终文档已同步更新。

### Thanks / 致谢

Thanks to all contributors for this PR and follow-up hardening work:

- @edward-zyz
- @Yaxuan42
- Claude Opus 4.6 (co-authored commits)
