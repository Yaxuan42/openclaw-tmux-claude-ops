# Skills 层面迭代评估报告

> 评估日期：2026-02-14（初版）→ 2026-02-17（完成状态更新）
> 评估范围：`skills/claude-code-orchestrator/`（脚本 + SKILL.md + 交付协议）
> 评估视角：skills 层面（不涉及 OpenClaw 核心 / 模型选择 / 产品定位）
>
> **状态：P0 全部完成，P1 大部分完成，新增 Phase 0-3 闭环反馈系统**

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
| wake 回调触发 | wake.sh → feishu DM + gateway wake | ✅ **稳定**（已修复） |
| **Headless 模式**（新增） | `claude -p --output-format stream-json` | ✅ 稳定 |
| **事件驱动监控**（新增） | on-session-exit.sh + timeout-guard.sh | ✅ 稳定 |
| **失败自动诊断**（新增） | diagnose-failure.sh | ✅ 稳定 |
| **任务历史 + 周报**（新增） | wake.sh → TASK_HISTORY.jsonl + analyze-history.sh | ✅ 稳定 |
| **并行 headless 调度**（新增） | start-tmux-task.sh --mode headless | ✅ 已验证 |

### 做不到 / 边界外

1. ~~**完成检测**~~ → ✅ **已解决**：事件驱动监控（pane-died hook + timeout-guard）+ status-tmux-task.sh 零 token 探测。
2. ~~**质量门泛化**~~ → ✅ **已解决**：`--lint-cmd` / `--build-cmd` 参数化，空字符串跳过。
3. ~~**多任务全局视图**~~ → ✅ **已解决**：`list-tasks.sh` 一键列出所有 cc-* 会话状态。
4. ~~**错误恢复**~~ → ✅ **已解决**：on-session-exit.sh 自动检测异常退出 + 诊断 + 告警；watchdog.sh 兜底巡检。
5. ~~**Bootstrap**~~ → ✅ **已解决**：`bootstrap.sh` 一键检查环境 + `--dry-run` 验证 tmux 链路。
6. **自动重试**：诊断后仍需人工决定是否重试。（Phase 3+ 目标）
7. **sub-agent 编排**：未使用 OpenClaw sub-agent 做复杂任务拆分。

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

### P0：必须做 ✅ 全部完成

#### P0-1：质量门参数化 ✅ 已完成

`start-tmux-task.sh` 和 `complete-tmux-task.sh` 支持 `--lint-cmd` / `--build-cmd`，空字符串跳过。

#### P0-2：轻量完成检测 ✅ 已完成（并升级为事件驱动）

- `status-tmux-task.sh`：零 token 状态探测。
- `on-session-exit.sh`：tmux pane-died hook，session 退出瞬间触发（比轮询更快）。
- `timeout-guard.sh`：后台超时看门狗（默认 2h）。
- `watchdog.sh`：cron 每 10 分钟兜底巡检。

#### P0-3：Bootstrap 脚本 ✅ 已完成

`bootstrap.sh` 支持 `--dry-run`，README 已更新 Quick Start。

---

### P1：应该做 ✅ 大部分完成

#### P1-1：任务全局状态视图 ✅ 已完成

`list-tasks.sh` 支持 `--json` 输出，配合 OpenClaw 生成管家式汇总。

#### P1-2：JSON 生成加固 ✅ 已完成

`complete-tmux-task.sh` 已改用 `jq` 构建 JSON，消除 Python heredoc 注入风险。

#### P1-3：Proxy 配置外置

未实施。当前硬编码 proxy 不影响主流程。低优先级。

#### P1-4：wake 确认机制 ✅ 已解决（方案升级）

原方案：检测 wake 退出码 + 标记文件。
实际方案（更优）：
- wake.sh 改用 `openclaw message send` 飞书 DM 直推（绕过 gateway call agent 的三层 bug）
- 事件驱动监控（on-session-exit.sh + timeout-guard.sh）作为兜底
- watchdog.sh cron 每 10 分钟巡检

---

### P2：可以做（完善度 / 进阶能力）

#### P2-1：多机执行接口设计

未实施。当前 SSH 模式已可用，但 `remote-dispatch.sh` 封装尚未创建。

#### P2-2：执行超时 + 自动告警 ✅ 已完成（方案升级）

原方案：`--timeout` 参数 + at/cron。
实际方案（更优）：`timeout-guard.sh` 后台进程，start-tmux-task.sh 自动启动，默认 2h。超时后自动运行诊断、发送飞书告警、记录历史。PID 跟踪 + 自动清理。

#### P2-3：Session 日志持久化 ✅ 部分完成

- Headless 模式：stream.jsonl 即为完整持久日志（每行一个 JSON 事件）。
- Interactive 模式：capture-execution.sh 后台采样到 execution-events.jsonl。
- 未实现 tmux pipe-pane 全量日志（低优先级，有 stream.jsonl 和 capture 已够用）。

#### P2-4：SKILL.md 协议版本化

未实施。当前只有一套协议，暂不需要版本化。

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

skills 层已从"基本可用"进化为"完整闭环"（2026-02-17 更新）。

### 已完成

1. ✅ **质量门泛化**（P0-1）：`--lint-cmd` / `--build-cmd` 参数化，任何项目类型可用。
2. ✅ **事件驱动监控**（P0-2 升级）：pane-died hook + timeout-guard + watchdog cron 三层防护。
3. ✅ **Bootstrap 自举**（P0-3）：clone 即跑。
4. ✅ **Headless 模式**：`claude -p --output-format stream-json --verbose`，支持并行调度。
5. ✅ **通知修复**：飞书 DM 直推 + 富文本摘要（提取 Claude 自己的完成总结）。
6. ✅ **失败自动诊断**：diagnose-failure.sh 支持 4 种数据源、8 种失败模式。
7. ✅ **历史积累 + 周报**：wake.sh 自动记录，周一 9:30 自动发送周报。
8. ✅ **JSON 生成加固**：改用 jq，消除 Python heredoc 注入风险。

### 下一步

1. **自动重试**：基于诊断结果自动决定是否重试（当前需人工决定）。
2. **sub-agent 编排**：利用 OpenClaw sub-agent 做复杂任务拆分。
3. **多机调度封装**：`remote-dispatch.sh` 一条命令选择执行节点。
