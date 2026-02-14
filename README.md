# OpenClaw × Claude Code × tmux：把并行 AI 执行变成“可调度作业系统”

这个仓库刻意分成两套阅读路径：

- **给人看的（意义 / 方式变化 / 典型场景）**：你读完会明白为什么需要 *OpenClaw 作为主 Agent*，以及 tmux 为什么是并行 AI 工作流的结构件。
- **给 agent 看的（可执行 Runbook）**：你把 MD 直接丢给 OpenClaw / Claude Code，它就能按步骤把任务跑起来。

> 目标不是“用户自己阅读然后折腾”，而是：**人类负责理解与决策；Agent 负责执行与交付。**

---

## 你应该从哪里开始

- 人类读者：从 `HUMAN_README.md` 开始
- Agent 执行：把 `AGENT_RUNBOOK.md` 作为 reference doc 交给 OpenClaw

---

## 仓库内容

- `docs/`：
  - [docs/FINAL.md](./docs/FINAL.md)（融合版最终稿）
  - `docs/archive/`：归档版本（不作为主线内容）
- `skills/claude-code-orchestrator/`：tmux 编排脚本（local/ssh 都支持）
- [HUMAN_README.md](./HUMAN_README.md)：给人看的（意义/方式变化 + 主 Agent 角色）
- [AGENT_RUNBOOK.md](./AGENT_RUNBOOK.md)：给 agent 看的（可执行 Runbook）
- `MANIFEST.sha256`：校验

---

## 文档点评与使用建议（客观对比）

### 内部分享：更推荐 Claude 版做主稿
- **优势**：更像可直接拿去讲的技术分享底稿（分层清晰、对比表强、SOP/风险边界更完整）。
- **不足**：信息密度偏高，非工程同学阅读需要你口头带节奏。
- **用法**：Claude 内部版当主稿；Aki 内部版当摘要/1 页版。

### 对外（公众号/博客）：更推荐 Claude 版做主稿，Aki 版做短分发
- **Claude 对外版优势**：开头场景钩子强，“三个瞬间”更易代入。
- **Claude 对外版风险**：示例较具体，必要时可去项目化。
- **Aki 对外版优势**：更克制、更短，适合多平台同步。

### 口径统一建议
建议固定一句主轴：
> **你不再管理窗口，你开始管理作业。**

---

## 说明与边界

- 这套方案本质是“远程代码执行能力”。请控制 SSH key 最小权限，必要时用 `authorized_keys` 的 `command=` 限制回调命令范围。
- 强烈建议所有执行都在 git 管控的 repo 内进行，确保可回滚。

