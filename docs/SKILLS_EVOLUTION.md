# Skills 层面迭代评估报告

> 评估日期：2026-02-14
> 评估范围：`skills/claude-code-orchestrator/`（脚本 + SKILL.md + 交付协议）
> 评估视角：skills 层面（不涉及 OpenClaw 核心 / 模型选择 / 产品定位）

---

## 一、当前能力边界

### 能做到

| 能力 | 依赖 | 稳定度 |
|------|------|--------|
| 单机启动 tmux + Claude Code | tmux, claude CLI | 稳定 |
| SSH 远程启动 | 双向 SSH key | 可用，需手工配置 |
| 结构化 prompt 注入（含交付协议） | start-tmux-task.sh | 稳定 |
| Robust submit（多次重试 + 执行状态检测） | tmux capture-pane + rg | 较稳定 |
| 非阻塞进度查看（capture-pane） | monitor-tmux-task.sh | 稳定 |
| 交互式接管（tmux attach） | tmux | 稳定 |
| JSON + MD 完成报告生成 | Claude Code 自行产出 / complete-tmux-task.sh 兜底 | 较稳定 |
| wake 回调触发 | wake.sh → openclaw gateway | 可用，不够稳 |

### 做不到 / 边界外

1. **完成检测**：没有自动化的"任务完成了吗"探测——依赖 Claude Code 主动 wake，或人工问。
2. **质量门泛化**：hardcode `npm run lint / build`，对非 npm 仓库（如本仓库纯脚本 + 文档）直接失败。
3. **多任务全局视图**：每个 session 独立，没有"当前有哪些 job、分别什么状态"的汇总能力。
4. **错误恢复**：session 挂了（Claude 退出 / SSH 断开）没有自动重连或告警。
5. **Bootstrap**：新用户 clone 后不知道怎么跑起来（没有 `setup.sh` / 依赖检查 / 示例任务）。

---

## 二、最可能失败的环节（分类诊断）

### 2.1 提示词问题

| 现象 | 根因 | 严重度 |
|------|------|--------|
| Claude Code 没执行交付协议（没写报告/没 wake） | 协议嵌入在 prompt 里，但 Claude 可能被任务内容冲淡注意力 | 中 |
| 报告 JSON 格式不合规 | 人类写法示例（`true/false`）vs JSON 严格要求 | 低 |

### 2.2 脚本问题

| 现象 | 根因 | 严重度 |
|------|------|--------|
| `npm run lint/build` 在非 npm 仓库直接 fail | 质量门 hardcode | 高（影响所有非 npm 项目） |
| complete-tmux-task.sh 用 Python heredoc 拼 JSON（`'''$变量'''`）| shell 变量注入 + 特殊字符可能破坏 Python 字符串 | 中 |
| SSH 模式下 wake.sh 路径硬写本地绝对路径 | `WAKE_SCRIPT` 是本地 `$SCRIPT_DIR` 路径，SSH 回调时路径不存在 | 中 |

### 2.3 环境问题

| 现象 | 根因 | 严重度 |
|------|------|--------|
| Claude Code 启动后 UI 未被识别为 ready | `rg` 匹配的 ready 指纹可能因 Claude 版本更新而变化 | 中 |
| SSH 连接中断后 session 变"孤儿" | 无心跳 / 无超时检测 | 低（手工可恢复） |
| proxy 环境变量写死 127.0.0.1:6152/6153 | 不同机器端口不同 | 低（改参数即可） |

---

## 三、下一阶段迭代建议清单

### P0：必须做（不解决会持续阻塞日常使用）

#### P0-1：质量门参数化（脱离 npm 硬编码）

- **目的**：让任何类型仓库（npm / cargo / make / 纯脚本）都能通过质量门。
- **改法**：
  - `start-tmux-task.sh` 新增 `--lint-cmd` 和 `--build-cmd` 参数，默认 `npm run lint` / `npm run build`。
  - 当传入空字符串 `--lint-cmd ""` 时跳过该门。
  - `complete-tmux-task.sh` 同步支持 `--lint-cmd` / `--build-cmd`。
  - prompt 模板中的质量门部分改为动态生成。
- **收益**：所有仓库类型立即可用；消除本仓库自身的 lint/build 报错。
- **风险**：低。纯参数化，向后兼容（不传参则保持当前行为）。

#### P0-2：轻量完成检测（零额外 token）

- **目的**：解决"wake 没到、人工也不知道任务完没完"的核心痛点。
- **改法**：
  - 新建 `scripts/status-tmux-task.sh`：
    1. 用 `tmux capture-pane` 抓最后 50 行。
    2. 用 `rg` 检测完成信号：`"REPORT_JSON="`, `"WAKE_SENT="`, `"Co-Authored-By"`, `"✗"` 等模式。
    3. 检查 `/tmp/cc-<label>-completion-report.json` 是否已存在。
    4. 输出状态：`running` / `likely_done` / `stuck` / `dead`（session 不存在）。
  - OpenClaw 的 SKILL.md 在 completion loop 之前新增一步："如果超过 N 分钟没收到 wake，调用 `status-tmux-task.sh` 自检"。
- **收益**：零 token 成本检测任务状态；OpenClaw 可主动探测而非被动等 wake。
- **风险**：低。纯读操作，不影响执行中的 Claude Code。

#### P0-3：Bootstrap 脚本（clone 后可自举）

- **目的**：让新用户（或 agent）clone 后能一键验证环境 + 跑通 hello world。
- **改法**：
  - 新建 `scripts/bootstrap.sh`：
    1. 检查依赖：`tmux`, `claude`, `rg`, `python3`, `git`。
    2. 缺什么就报什么（不自动安装，只检测 + 提示）。
    3. 验证 tmux socket 目录可写。
    4. 可选 `--dry-run`：模拟启动一个 hello-world 任务（不实际调用 Claude），验证 tmux session 创建/销毁正常。
  - README.md 新增"Quick Start"块，指向 `bootstrap.sh`。
- **收益**：降低上手门槛；agent 也能用 bootstrap 做预检。
- **风险**：低。不修改现有脚本。

---

### P1：应该做（提升日常效率和可靠性）

#### P1-1：任务全局状态视图

- **目的**：一条命令看到所有活跃/完成/异常的任务。
- **改法**：
  - 新建 `scripts/list-tasks.sh`：
    1. `tmux -S <socket> list-sessions` 拿到所有 `cc-*` session。
    2. 对每个 session 调用 `status-tmux-task.sh` 拿状态。
    3. 检查 `/tmp/cc-<label>-completion-report.json` 是否存在。
    4. 输出表格：label / status / session_alive / report_exists / last_activity。
- **收益**：OpenClaw 可以一次性汇报所有任务状态；用户不需要逐个问。
- **风险**：低。依赖 P0-2。

#### P1-2：complete-tmux-task.sh JSON 生成加固

- **目的**：消除 shell 变量注入破坏 Python heredoc 的风险。
- **改法**：
  - 把 `git diff --stat` / `lint_out` / `build_out` 写入临时文件。
  - Python 脚本从文件读取，而非 shell 变量内嵌 `'''..'''`。
  - 或改用 `jq` 构建 JSON（`jq -n --arg ...`），消除 Python 依赖。
- **收益**：在包含引号、反斜杠、多行输出的仓库中不会崩溃。
- **风险**：低。

#### P1-3：Proxy 配置外置

- **目的**：不同机器不需要改脚本源码来改 proxy。
- **改法**：
  - `start-tmux-task.sh` 新增 `--proxy` 参数，默认从环境变量 `$OPENCLAW_PROXY` 读取。
  - 如果都没传，则不设置 proxy（当前行为是强制设置）。
- **收益**：减少"换台机器就要改脚本"的摩擦。
- **风险**：低。

#### P1-4：wake 确认机制

- **目的**：确认 wake 回调是否真的被 OpenClaw 收到。
- **改法**：
  - `wake.sh` 检查 `openclaw gateway call wake` 的退出码。
  - 如果失败，写一个 `/tmp/cc-<label>-wake-failed` 标记文件。
  - `status-tmux-task.sh` 检测到报告存在但 wake 失败时，输出 `done_wake_failed`。
  - OpenClaw 定期调 `list-tasks.sh` 时能发现这种状态。
- **收益**：闭合"wake 发了但没到"的盲区。
- **风险**：低。

---

### P2：可以做（完善度 / 进阶能力）

#### P2-1：多机执行接口设计

- **目的**：为 MacBook ↔ mini 双向调度预留干净接口。
- **改法**：
  - 不改现有脚本。新建 `scripts/remote-dispatch.sh`：
    1. 参数：`--target-host <alias>` + 现有所有 start-tmux-task.sh 参数。
    2. 内部调用 `start-tmux-task.sh --target ssh --ssh-host <alias>`。
    3. 同时注册一条"回收任务"：把 `status-tmux-task.sh` + 报告回传逻辑封装好。
  - SKILL.md 新增"远程执行"分支，指向 `remote-dispatch.sh`。
- **收益**：远程执行从"高级用户手写参数"变成"一条命令"。
- **风险**：中。SSH 环境差异难以穷举测试。

#### P2-2：执行超时 + 自动告警

- **目的**：任务跑了 30 分钟还没完成，主动告警。
- **改法**：
  - `start-tmux-task.sh` 新增 `--timeout <minutes>` 参数。
  - 启动时写一个 at/cron 任务，到时间后调用 `status-tmux-task.sh`；如果状态是 `running`，调用 `wake.sh "timeout-warning (${LABEL})" now`。
- **收益**：防止静默挂死。
- **风险**：中。at/cron 可靠性依赖环境；需要清理机制。

#### P2-3：Session 日志持久化

- **目的**：tmux scrollback 重启后消失；需要持久日志。
- **改法**：
  - `start-tmux-task.sh` 启动时启用 `tmux pipe-pane -t $SESSION "cat >> /tmp/cc-${LABEL}.log"`。
  - 或在 prompt 中要求 Claude Code 把关键输出 tee 到日志文件。
- **收益**：事后复盘不依赖 tmux session 存活。
- **风险**：低。日志文件可能较大，需定期清理。

#### P2-4：SKILL.md 协议版本化

- **目的**：随着协议迭代，避免新旧 prompt 模板不兼容。
- **改法**：
  - SKILL.md 头部新增 `protocol_version: 2`。
  - `start-tmux-task.sh` 根据版本号选择 prompt 模板。
  - 旧版本 prompt 仍可用，但标记为 deprecated。
- **收益**：平滑升级；多个 OpenClaw 实例可以共存不同协议版本。
- **风险**：低。

---

## 四、特别关注事项

### 4.1 零成本完成检测方案（已在 P0-2 描述）

核心思路：**不调用 LLM、不消耗 token**。

检测链路：
```
tmux capture-pane (最后50行)
    → rg 检测完成信号模式
    → 检查 report.json 是否存在
    → 输出状态码
```

成本：一次 bash 调用 ≈ 0 token，执行 < 1 秒。

OpenClaw 侧的使用方式：
- 在 SKILL.md 的 completion loop 前加一个"预检"步骤。
- 或在 heartbeat 中加一行 `status-tmux-task.sh` 调用（每次 heartbeat 只多一次 shell 调用，不触发 LLM）。

### 4.2 Bootstrap 自举能力（已在 P0-3 描述）

关键设计原则：
- **检测而非安装**：bootstrap 只告诉你缺什么，不替你装。
- **dry-run 验证**：不需要真跑 Claude Code 就能验证 tmux 编排链路。
- **agent 可调用**：输出结构化（JSON 或 exit code），便于 OpenClaw 自动判断。

### 4.3 多机接口设计（已在 P2-1 描述）

设计原则：
- **不改主线**：local 模式的代码路径不受影响。
- **封装而非替换**：`remote-dispatch.sh` 包装 `start-tmux-task.sh`，不替代它。
- **回收闭环**：远程执行的报告回传 + wake 回调必须是一个原子操作。

---

## 五、建议落地路线图（2 周节奏）

### Week 1：夯实基础

| 日期 | 里程碑 | 交付物 | 依赖 |
|------|--------|--------|------|
| Day 1-2 | P0-1 质量门参数化 | 修改 `start-tmux-task.sh` + `complete-tmux-task.sh`，支持 `--lint-cmd` / `--build-cmd` | 无 |
| Day 3 | P0-2 轻量完成检测 | 新建 `scripts/status-tmux-task.sh`，更新 SKILL.md | 无 |
| Day 4 | P0-3 Bootstrap 脚本 | 新建 `scripts/bootstrap.sh`，更新 README | 无 |
| Day 5 | P0 验收 + P1-2 JSON 加固 | 用本仓库自身做端到端测试（bootstrap → start → status → complete） | P0-1/2/3 |

### Week 2：扩展能力

| 日期 | 里程碑 | 交付物 | 依赖 |
|------|--------|--------|------|
| Day 6 | P1-1 任务全局视图 | 新建 `scripts/list-tasks.sh` | P0-2 |
| Day 7 | P1-3 Proxy 外置 + P1-4 wake 确认 | 修改 `start-tmux-task.sh` + `wake.sh` | 无 |
| Day 8-9 | P2-3 Session 日志持久化 | 修改 `start-tmux-task.sh`（pipe-pane） | 无 |
| Day 10 | 集成测试 + 文档更新 | 更新 AGENT_RUNBOOK.md / SKILL.md / README.md | 全部 |

### 验收标准

每个里程碑完成时必须满足：
1. `bootstrap.sh --dry-run` 全部通过。
2. 对至少一个真实仓库做 `start → status → complete` 全流程。
3. 新增/修改的脚本通过 `shellcheck`（如果可用）。
4. SKILL.md 和 AGENT_RUNBOOK.md 同步更新。

---

## 六、总结

当前 skills 层的核心架构（三层分工 + tmux 编排 + 交付协议）是正确的。最大的三个改进机会是：

1. **质量门泛化**（P0-1）：从"只能用于 npm 项目"到"任何项目"。
2. **零成本完成检测**（P0-2）：从"被动等 wake"到"主动探测状态"。
3. **Bootstrap 自举**（P0-3）：从"要有人教"到"clone 即跑"。

这三项都是 skills 层改动，不涉及 OpenClaw 核心，风险低、收益确定、实施快。
