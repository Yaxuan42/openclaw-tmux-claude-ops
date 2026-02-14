# OpenClaw × Claude Code × tmux：把 AI 执行从"开窗口"变成"管作业"

> 内部技术分享 | 2026-02-14

---

## 1. 背景与痛点

我们现在同时推进的事经常在 5~10 件：UI 调整、接口联调、文档整理、构建排查、数据脚本。传统做法是每件事打开一套环境：

- N 个 VS Code 窗口
- N 个终端 tab（或 iTerm 分屏）
- N 个 AI 聊天窗（Claude/ChatGPT 网页 or IDE 插件）

这套操作的核心矛盾不是"忙"，而是四个结构性问题：

| 问题 | 具体表现 |
|------|---------|
| **不可调度** | 任务发起依赖"人坐在电脑前"，出门就停摆 |
| **不可观测** | 哪个任务卡住了？卡在 lint 还是卡在构建？你不知道 |
| **不可接管** | 发现卡了，要先找到那个窗口、回忆上下文、重新介入 |
| **不可复盘** | 做完了，但改了哪些文件、lint 过没过、有没有超出范围——信息散落 |

这四个问题不随 AI 模型能力提升而消失。它们是**工作流的缺陷**，不是模型的缺陷。

## 2. 新工作流：三层分工

我们把执行链拆成三个明确的角色。

### 2.1 调度层 — OpenClaw（Codex 5.3）

职责：**把一句话变成一个可运行的作业**。

机制：
1. 接收任务输入（Telegram / 飞书 / 手机任意渠道）
2. 生成结构化 prompt——包括任务描述、交付协议、约束条件、回调指令
3. 选择执行节点（本机 or SSH 远程主机）
4. 调用 `start-tmux-task.sh`，启动 tmux 会话、注入 prompt
5. 任务完成后接收 wake 回调，读取报告，做上下文判断

关键点：prompt 是文件（不是 shell 参数），避免了引号嵌套和 SSH 转义问题。

### 2.2 执行层 — Claude Code

职责：**在具体 repo 里干活**。

在 tmux 会话内以 `claude --dangerously-skip-permissions` 运行。读代码、改代码、跑命令、产出报告。不负责调度，不负责通知。

### 2.3 可观测 / 可接管层 — tmux

职责：**让每个任务成为一个有状态的后台会话**。

- 每个任务对应一个 session：`cc-<label>`
- 统一 socket：`/tmp/clawdbot-tmux-sockets/clawdbot.sock`
- 查看进度：`tmux capture-pane` 或 `monitor-tmux-task.sh --lines 200`
- 接管：`tmux attach -t cc-<label>`，直接获得键盘控制

tmux 的 pane 输出就是最朴素的 observability——stdout 即日志，无需额外协议。

## 3. 为什么称之为"质变"

不是"AI 更聪明了"的质变，是工作结构的改变。

### 3.1 对比表

| 维度 | 之前（多窗口） | 之后（Job 模式） |
|------|----------------|------------------|
| 任务发起 | 坐在电脑前打开 IDE | 手机发一句话 |
| 进度感知 | 在脑子里记"哪个窗口在跑什么" | `tmux ls` 或 monitor 脚本看状态 |
| 卡住处理 | 找窗口 → 回忆上下文 → 手动介入 | `tmux attach` → 直接接管 |
| 任务结束 | 聊天窗口里一句"done" | 结构化报告（JSON + Markdown） |
| 复盘 | 翻聊天记录 | 读 `completion-report.json`：changedFiles / diffStat / lint / build / risk |

### 3.2 关键机制

**① 报告即交付物**
任务不以"说 done"结束，而以产出 completion report 结束。报告强制包含：改了什么文件、diff 统计、lint/build 是否通过、风险等级、是否 scope drift。你收到的不是一句话，是一份可审计的交付物。

**② Wake = 交付触发器，不是交付本身**
prompt 里硬编码了三阶段约束：先跑质量门（lint/build），再写报告，最后才允许发 wake。防止"我跑完了但不知道做了啥"。

**③ 可中断不丢失**
tmux session 在 Claude Code 退出后依然存在。你可以事后 attach 进去翻 scrollback，看完整执行过程。

## 4. 落地规范

### 4.1 Label 命名

格式：`cc-<label>`，全小写，连字符分隔，无空格。

示例：`cc-billing-fix-rounding`、`cc-gallery-detail-polish`。

Label 同时用于：session 名称、报告文件前缀、回调追踪 ID。

### 4.2 强制交付协议

每个任务 prompt 末尾嵌入三阶段指令：

**阶段 A — 质量门：**
```
git status --short
git diff --name-only
git diff --stat
npm run lint
npm run build
```

**阶段 B — 报告产出：**
```
/tmp/cc-<label>-completion-report.json
/tmp/cc-<label>-completion-report.md
```

JSON 结构：
```json
{
  "label": "...",
  "workdir": "...",
  "changedFiles": [...],
  "diffStat": "...",
  "lint": {"ok": true, "summary": "..."},
  "build": {"ok": true, "summary": "..."},
  "risk": "low|medium|high",
  "scopeDrift": true/false,
  "recommendation": "keep|partial_rollback|rollback",
  "notes": "..."
}
```

**阶段 C — Wake 回调：**
```bash
bash "scripts/wake.sh" "Claude Code done (<label>) report=..." now
```

### 4.3 回调处理

OpenClaw 收到 wake 后：
1. 60 秒内确认收到
2. 读取 report JSON
3. 若 report 缺失，执行 `complete-tmux-task.sh` 兜底生成
4. 抓取 tmux pane 最后 200 行作为执行记录
5. 结合上下文做判断（不是模板化回复）
6. 若检测到 scope drift，要求人工确认

## 5. 风险与边界

### 5.1 权限控制

这套方案的本质是**远程代码执行**。必须做到：

- SSH key 限制最小必要权限
- 回调命令在 `authorized_keys` 中用 `command=` 限定可执行范围
- 每个任务在指定 repo/目录内工作，不越界

### 5.2 可回滚

所有改动通过 git 管理。报告里 `recommendation` 字段支持三种判定：keep / partial_rollback / rollback。报告本身就是回滚决策的输入。

### 5.3 监控

- 实时：tmux attach 或 `monitor-tmux-task.sh`
- 事后：tmux scrollback + completion report
- 异常：wake 超时未到 → 主动 attach 排查

### 5.4 不适合的场景

- 需要人类判断的产品决策（不应交给自动化流程）
- 超长时间无人值守 + 高风险改动（应拆分成小 job）
- 强交互式调试（需要频繁人机对话的场景，直接用 IDE 更好）

## 6. 结语

这套方案的核心不是某个工具有多强，而是**三层分工把"用 AI 写代码"从一个手动操作变成了一个可管理的工程流程**。

一句话：**你不再管理窗口，你开始管理作业。**

---

### 可直接照抄的 3 条实践建议

1. **给每个任务一个 label，用 tmux session 隔离**
   ```bash
   tmux -S /tmp/my.sock new-session -d -s cc-my-task
   ```
   不要用"窗口切换"管理并行任务。Label 是追踪 ID，session 是隔离边界。

2. **把交付协议写进 prompt，不要靠口头约定**
   在任务指令末尾硬编码 `git diff --stat && npm run lint && npm run build`，并要求输出 JSON 报告。这是最低成本的质量门。

3. **先看报告再看代码**
   收到完成通知后，先读 `completion-report.json` 的 `changedFiles`、`lint.ok`、`build.ok`、`risk`。只有需要深入时再 `tmux attach` 看过程、看 diff。这会显著降低你的审查负担。
