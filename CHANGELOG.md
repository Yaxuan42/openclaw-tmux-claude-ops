# Changelog

## 2026.3.9

### Changes (EN)

- **SKILL.md rewrite**: broadened trigger description for better skill activation coverage (monitoring, multi-task, headless, diagnosis, history analysis scenarios).
- Added **Concepts section** to SKILL.md — explicitly defines `{baseDir}`, session naming, reports, wake, and runs directory conventions.
- Added **parameter table** documenting all `start-tmux-task.sh` optional parameters (`--mode`, `--lint-cmd`, `--build-cmd`, `--target`, `--ssh-host`, `--socket`, `--mini-host`).
- Enhanced **status check** with table format and **timeout guidance** (15/30/60 min escalation tiers).
- Added **Error recovery** section covering crash, stuck, and wake-lost scenarios with concrete shell commands.
- Removed dead code: unused `tmux_cmd()` / `tmux_capture()` functions from `start-tmux-task.sh` (-16 lines).

### 变更（中文）

- **SKILL.md 重写**：扩展触发描述，覆盖监控、多任务、headless、诊断、历史分析等场景，提升技能激活准确率。
- 新增 **Concepts 段**，明确定义 `{baseDir}`、session 命名、reports、wake、runs 目录等核心概念。
- 新增 **参数表**，文档化 `start-tmux-task.sh` 的 7 个可选参数。
- **状态检测**升级为表格格式，新增**超时指导**（15/30/60 分钟分级处置）。
- 新增 **Error recovery 段**，覆盖 crash、stuck、wake 丢失三种场景的具体操作步骤。
- 移除死代码：`start-tmux-task.sh` 中从未调用的 `tmux_cmd()` / `tmux_capture()` 函数（-16 行）。

---

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
