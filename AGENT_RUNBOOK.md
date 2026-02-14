# 给 Agent 看的：OpenClaw 调度 Claude Code（tmux）一键跑通 Runbook

> 目的：把这份 MD 直接作为 reference doc 交给主 Agent（OpenClaw / Claude Code 皆可），它就能一步步执行完成“启动任务 → 监控 → 报告 → 回调”。

## 0) 约定
- 调度节点：Mac mini（运行 OpenClaw）
- 执行节点：本机（mini）或远程（macbook）
- tmux session 命名：`cc-<label>`

## 1) 环境检查（必须先做）
在 **执行节点**（本机或远程）确认：
- `tmux` 可用
- `claude --version` 可用
- `rg` 可用

命令：
```bash
which tmux && tmux -V
which claude && claude --version
which rg && rg --version
```

若使用远程执行（ssh）：在 mini 上确认
```bash
ssh macbook 'which tmux && tmux -V && which claude && claude --version && which rg && rg --version'
```

## 2) 选择执行模式

### A. 本机执行（local）
使用：
- 代码仓库在 mini 上
- 不需要跨机器回调

### B. 远程执行（ssh）
使用：
- 代码仓库在 macbook 上（例如 `/Users/yaxuan/Projects/<proj>`）
- 需要 macbook 结束后把报告回传到 mini 并触发 wake

远程模式额外要求：
- mini → macbook：ssh 可连
- macbook → mini：ssh 可连（用于回传报告 + wake）

## 3) 启动一个任务（唯一入口）

### 3.1 local 启动
```bash
bash skills/claude-code-orchestrator/scripts/start-tmux-task.sh \
  --label "<label>" \
  --workdir "<repo_dir>" \
  --prompt-file "<reference_doc_path>" \
  --task "<task_text>"
```

### 3.2 ssh 启动（在 macbook 上跑）
```bash
bash skills/claude-code-orchestrator/scripts/start-tmux-task.sh \
  --target ssh \
  --ssh-host macbook \
  --mini-host mini \
  --label "<label>" \
  --workdir "/Users/yaxuan/Projects/<project>" \
  --prompt-file "<reference_doc_path>" \
  --task "<task_text>"
```

说明：
- 脚本会自动把 `--prompt-file` scp 到远端 `/tmp/`，避免路径不可达。
- 交付报告默认写在 `/tmp/cc-<label>-completion-report.{json,md}`。

## 4) 监控与接管

### 4.1 查看最后 200 行输出
local：
```bash
bash skills/claude-code-orchestrator/scripts/monitor-tmux-task.sh --session cc-<label> --lines 200
```

ssh：
```bash
bash skills/claude-code-orchestrator/scripts/monitor-tmux-task.sh \
  --target ssh --ssh-host macbook \
  --session cc-<label> --lines 200
```

### 4.2 直接接管（attach）
local：
```bash
bash skills/claude-code-orchestrator/scripts/monitor-tmux-task.sh --attach --session cc-<label>
```

ssh：
```bash
bash skills/claude-code-orchestrator/scripts/monitor-tmux-task.sh \
  --target ssh --ssh-host macbook \
  --attach --session cc-<label>
```

## 5) 完成与报告

任务完成应满足：
- 生成：`/tmp/cc-<label>-completion-report.json`
- 生成：`/tmp/cc-<label>-completion-report.md`
- 最后一步触发 wake：
  - local：直接调用 `wake.sh`
  - ssh：先 `scp` 报告回 mini，再 `ssh mini` 调用 `wake.sh`

若 wake 已到但报告缺失：
```bash
bash skills/claude-code-orchestrator/scripts/complete-tmux-task.sh --label <label> --workdir <repo_dir>
```

## 6) 安全边界（必须遵守）
- 这套流程本质是远程代码执行，SSH key 必须最小权限。
- 强烈建议在 git repo 内工作，保证可回滚。
