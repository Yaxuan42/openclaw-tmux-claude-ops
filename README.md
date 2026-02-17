# OpenClaw × Claude Code × tmux：把并行 AI 执行变成“可调度作业系统”

[English README](./README.en.md)

这个仓库刻意分成两套阅读路径：

- **给人看的（意义 / 方式变化 / 典型场景）**：你读完会明白为什么需要 *OpenClaw 作为主 Agent*，以及 tmux 为什么是并行 AI 工作流的结构件。
- **给 agent 看的（可执行 Runbook）**：你把 MD 直接丢给 OpenClaw / Claude Code，它就能按步骤把任务跑起来。

> 目标不是“用户自己阅读然后折腾”，而是：**人类负责理解与决策；Agent 负责执行与交付。**

---

## 快捷入口

- 最终分享稿（主线）：[`docs/FINAL.md`](./docs/FINAL.md)
- Agent 执行手册（主线）：[`AGENT_RUNBOOK.md`](./AGENT_RUNBOOK.md)
- 归档草稿：`docs/archive/`
- 技能脚本：`skills/claude-code-orchestrator/`

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/Yaxuan42/openclaw-tmux-claude-ops.git
cd openclaw-tmux-claude-ops

# 2. Check environment
bash skills/claude-code-orchestrator/scripts/bootstrap.sh

# 3. Verify tmux lifecycle (optional)
bash skills/claude-code-orchestrator/scripts/bootstrap.sh --dry-run
```

---

## 项目结构

- `docs/`：
  - `FINAL.md`：融合版最终稿（主线）
  - `archive/`：历史归档（不作为主线内容）
- `skills/claude-code-orchestrator/`：tmux 编排脚本（local/ssh 都支持）
  - `scripts/start-tmux-task.sh`：启动任务（支持 `--mode interactive|headless`）
  - `scripts/wake.sh`：通知 + 记录 TASK_HISTORY（飞书 DM 直推 + gateway wake 双通道）
  - `scripts/on-session-exit.sh`：tmux pane-died 事件驱动的异常退出处理
  - `scripts/timeout-guard.sh`：后台超时看门狗（默认 2h）
  - `scripts/diagnose-failure.sh`：失败诊断（4 种数据源，8 种失败模式）
  - `scripts/watchdog.sh`：定期巡检（cron 每 10 分钟）
  - `scripts/capture-execution.sh`：interactive 模式后台采样
  - `scripts/analyze-history.sh`：历史分析 + 周报
  - `scripts/list-tasks.sh`：列出所有 cc-* 会话
  - `scripts/status-tmux-task.sh`：零 token 状态检测
  - `scripts/monitor-tmux-task.sh`：实时查看会话
  - `scripts/complete-tmux-task.sh`：兜底完成脚本
  - `scripts/bootstrap.sh`：环境初始化
  - `TASK_HISTORY.jsonl`：任务历史记录
- `AGENT_RUNBOOK.md`：给 agent 看的（可执行 Runbook）
- `MANIFEST.sha256`：校验

---

# OpenClaw 作为主 Agent 的“调度系统”，如何带着一群 Claude Code 干活

这篇不是教程，不要求你照着折腾。它讲三件事：
1) 为什么需要 **主 Agent（OpenClaw）**
2) 为什么 **tmux** 是并行 AI 工作流的“结构件”
3) 这种方式的“质变”到底是什么

## 1. 问题不在模型，而在并行时代的人类注意力
当你同时推进 5~10 件事（改 UI、修 bug、写脚本、排查构建），传统方式会自然退化成：
- 多个 IDE 窗口 + 多个终端 tab + 多个 AI 对话窗口
- 你在脑子里维护一张“窗口 ↔ 任务”的映射表

真正的瓶颈不是 AI 不够聪明，而是：
- **不可调度**：必须坐在电脑前才能发起
- **不可观测**：你不知道哪个任务卡住了
- **不可接管**：卡住时先找窗口，再补上下文
- **不可复盘**：做完只剩一句 done，没有证据链

## 2. OpenClaw 的角色：管家 + CTO（主 Agent / 调度层）
在这套体系里，OpenClaw 不是“又一个写代码的 agent”。它更像：
- **管家**：接收任务、排队、分配执行节点、收集交付物
- **CTO**：强制工程化约束（质量门、报告、回调），把“聊天式能力”变成“可审计作业”

一句话：
> **主 Agent 负责把任务变成 Job；子 Agent 负责把 Job 做完。**

## 3. Claude Code 的角色：执行引擎（子 Agent / 执行层）
Claude Code 的优势是“在 repo 里动手”：
- 读代码、改代码、跑命令、修报错

但它不天然解决“并行管理”。当你同时跑多个 Claude Code，真正需要的是：
- 给每个任务一个隔离空间
- 给每个任务一个可观察的日志
- 给每个任务一个可回收的交付物

## 4. tmux 的角色：把任务从‘窗口’升级为‘会话/作业’（可观测 + 可接管）
tmux 的价值非常朴素：
- 每个任务一个 session：`cc-<label>`
- **随时 attach** 看输出
- 卡住了直接接管键盘

这就把“并行”从 UI 层（开很多窗口）推进到了系统层（管理一组作业）。

## 5. 质变点：从管理窗口到管理作业
这套组合带来的质变，本质是结构变化：
- 窗口 → job
- 口头 done → 报告（diff/lint/build/risk）
- 走回工位才开始 → 手机上也能发起

**你不再管理窗口，你开始管理作业。**

---

## 文档点评与使用建议（客观对比）

- 内部分享：更推荐 `docs/archive/` 里的 Claude internal 版做主稿；Aki internal 版当摘要。
- 对外（公众号/博客）：更推荐 Claude public 版做主稿；Aki public 版做短分发。

建议固定一句主轴（减少口径漂移）：
> **你不再管理窗口，你开始管理作业。**

---

## 说明与边界

- 主线默认单机即可跑出质变；如果引入远程/多设备执行，请用最小权限控制 SSH key，并在必要时用 `authorized_keys` 的 `command=` 限制回调命令范围。
- 强烈建议所有执行都在 git 管控的 repo 内进行，确保可回滚。

---

## 现状与下一步（真实状态，2026-02-17 更新）

这套流程已经过完整闭环验证（Phase 0-3 全部完成），核心链路已经稳定。

### ✅ 已稳定 & 验证通过

- **双模式执行**：`--mode interactive`（默认，可接管）和 `--mode headless`（`claude -p` + stream-json，原生结构化日志）按需选择。
- **通知可靠性 100%**：飞书 DM 直推（`openclaw message send`）+ gateway wake 双通道。wake.sh 会提取 Claude Code 自己的完成摘要作为通知内容。
- **事件驱动监控**：
  - `on-session-exit.sh`：tmux pane-died hook 自动触发，检测异常退出、运行诊断、发送告警、记录历史。纯 shell，零 LLM token 消耗。
  - `timeout-guard.sh`：后台超时看门狗（默认 2h），超时自动诊断并通知。
  - `watchdog.sh`：cron 每 10 分钟巡检兜底。
- **失败自动诊断**：`diagnose-failure.sh` 支持 4 种数据源、8 种失败模式自动分析。
- **历史积累 + 周报**：wake.sh 自动记录 TASK_HISTORY.jsonl，周一 9:30 自动发送周报。
- **并行任务验证通过**：3 个 headless 任务同时启动，各自独立完成，总耗时 ~40 秒。
- **并行任务可观测性**：
  - `bash skills/claude-code-orchestrator/scripts/list-tasks.sh`
  - `bash skills/claude-code-orchestrator/scripts/list-tasks.sh --json | jq .`

### 🧭 下一步
- **自动重试**：根据 diagnose-failure.sh 的诊断结果自动决定是否重试。
- **多设备调度**：MacBook ↔ mini 双向 SSH 打通后，让 OpenClaw 选择执行节点。
- **sub-agent 能力**：利用 OpenClaw sub-agent 做更复杂的任务编排。

---

## 推荐给朋友的最小上手方式

我现在给朋友的推荐模式大概是：

> @Edward https://github.com/Yaxuan42/openclaw-tmux-claude-ops 试试让 openclaw clone 过去能不能自己搞定。

