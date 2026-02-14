# OpenClaw × Claude Code × tmux：手机调度多任务作业（示例项目包）

这个文件夹是一个可分享/可拷贝的“最小可用包”，用于演示并复用下面这套工作流：

- **OpenClaw（调度）**：接收任务（手机/Telegram），生成结构化 prompt，启动执行
- **Claude Code（执行）**：在 repo 里改代码/跑命令/写报告
- **tmux（可观测/可接管）**：每个任务一个 session，随时 attach 查看或接管

本包包含：
- 4 份分享文档（内部版/对外版，各两份：Aki 写 + Claude 写）
- 一套可直接运行的 `claude-code-orchestrator` 脚本（基于 tmux）

---

## 目录结构

- `docs/`
  - `2026-02-14-openclaw-claude-code-internal-aki.md`
  - `2026-02-14-openclaw-claude-code-public-aki.md`
  - `2026-02-14-openclaw-claude-code-internal-claude.md`
  - `2026-02-14-openclaw-claude-code-public-claude.md`
- `skills/claude-code-orchestrator/`
  - `SKILL.md`
  - `scripts/`
    - `start-tmux-task.sh`：启动任务（支持 local/ssh）
    - `monitor-tmux-task.sh`：查看输出/attach（支持 local/ssh）
    - `complete-tmux-task.sh`：兜底生成交付报告
    - `wake.sh`：触发 OpenClaw wake 回调
- `MANIFEST.sha256`：文件校验

---

## 前置条件（运行脚本）

在执行节点（本机或远程）需要：
- `tmux`
- `claude`（Claude Code CLI）
- `rg`（ripgrep，用于脚本检测）

如果你要用 `--target ssh`：
- Mac mini → MacBook 的 `ssh` 已配置免密（或至少可非交互连接）
- 若希望任务完成后自动回调：MacBook → Mac mini 的 `ssh` 也要能连（用于回传报告 + 触发 wake）

---

## 最小示例：本机启动一个任务（local）

```bash
bash skills/claude-code-orchestrator/scripts/start-tmux-task.sh \
  --label "demo" \
  --workdir "/path/to/your/repo" \
  --prompt-file "/path/to/reference.md" \
  --task "按参考文档执行：做一个小修改并产出报告。"

# 然后 attach
bash skills/claude-code-orchestrator/scripts/monitor-tmux-task.sh --attach --session cc-demo
```

---

## 远程示例：在 MacBook 上跑任务（ssh）

```bash
bash skills/claude-code-orchestrator/scripts/start-tmux-task.sh \
  --target ssh \
  --ssh-host macbook \
  --mini-host mini \
  --label "demo-remote" \
  --workdir "/Users/yaxuan/Projects/demo" \
  --prompt-file "/path/to/reference.md" \
  --task "在 macbook 上执行，并在结束时把报告回传到 mini 再 wake。"

# 远程 attach
bash skills/claude-code-orchestrator/scripts/monitor-tmux-task.sh \
  --target ssh --ssh-host macbook \
  --attach --session cc-demo-remote
```

---

## 文档点评与使用建议（客观对比）

这包里 `docs/` 有两种维度：
- **场景维度**：内部分享 vs 对外（公众号/博客）
- **作者维度**：Aki 版 vs Claude 版

### 内部分享：更推荐 Claude 版做主稿
- **优势**：结构更像可直接拿去讲的“技术分享底稿”，分层清晰、对比表强、SOP/风险边界更完整。
- **可能的不足**：信息密度偏高，非工程同学阅读需要你口头带节奏。
- **建议用法**：Claude 内部版当主稿；Aki 内部版当摘要/1 页版。

### 对外（公众号/博客）：更推荐 Claude 版做主稿，Aki 版做短分发
- **Claude 对外版优势**：开头场景钩子强，“三个瞬间”更易代入，天然带专业感但不油。
- **Claude 对外版风险**：示例较具体（某项目/改了几个文件），若要更通用可把案例去项目化。
- **Aki 对外版优势**：更克制、更短，更适合多平台同步（朋友圈/短博文/群里转发）。
- **建议用法**：Claude 对外版做长文主发；Aki 对外版做短版同步。

### 建议的“口径统一”
如果你后续要持续分享，建议固定一句主轴（减少版本口径漂移）：
> **你不再管理窗口，你开始管理作业。**

---

## 说明与边界

- 这套方案的本质是“远程代码执行能力”。请务必控制 SSH key 权限，必要时用 `authorized_keys` 的 `command=` 限制回调命令范围。
- 强烈建议所有执行都在 git 管控的 repo 内进行，确保可回滚。

