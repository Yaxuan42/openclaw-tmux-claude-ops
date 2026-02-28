# 建立反馈闭环机制：OpenClaw + Claude Code 体系优化方案

> 灵感来源：胡渊鸣《我给10个Claude Code打工》Step 7
> 核心命题：通过结构化过程日志 + 自动监控 + 失败诊断，将任务成功率从不稳定提升至可预期
> 撰写时间：2026-02-17
> 最后更新：2026-02-17（Phase 0-3 全部完成）

---

## 一、背景

### 1.1 胡渊鸣 Step 7 的核心洞察

胡渊鸣在并行化运行多个 Claude Code 实例后，发现任务完成率只有约 20%。关键突破在于给 Claude Code 加上 `--output-format stream-json --verbose` 参数，让 Manager 程序能够：

- 读取每个 Claude Code 实例的结构化执行日志
- 自动发现错误模式（API 超时、文件找不到、循环重试等）
- 针对性调整 prompt 或重试策略

结果：**任务成功率从 20% 提升到 95%**。

核心原理：**闭环反馈**。没有过程可见性，就没有诊断能力；没有诊断能力，就只能靠运气。

### 1.2 为什么需要做这件事

当前体系已经具备了任务派发、执行监控和完成通知的基本能力。经过 Phase 0/1/2 的实施，**完整闭环已跑通验证**。具体进展：

1. ~~capture-execution.sh 已集成但未经实战验证~~ → ✅ **Phase 0 已验证**（verify-loop 任务成功产出日志）
2. ~~TASK_HISTORY.jsonl 有数据但可能是测试数据~~ → ✅ **已清理伪造数据**，当前 8 条真实记录（含 3 个并行 headless 任务）
3. ~~wake 通知飞书 DM 静默失败~~ → ✅ **已修复**（改用 `openclaw message send`，详见 2.7）
4. ~~HEARTBEAT.md 仍为空~~ → ✅ **Phase 2 已新增 watchdog cron job**（每 10 分钟巡检）
5. ~~headless 模式（`claude -p` + stream-json）尚未实现~~ → ✅ **Phase 1 已实现并验证**
6. ~~repo 与 deployed 版本已分叉~~ → ✅ **Phase 0 已同步**，后续改动同步 commit（最新 `6c63e89`）

---

## 二、现状分析（基于 2026-02-17 系统实况审计）

### 2.1 运行环境

| 组件 | 版本/状态 |
|------|----------|
| OpenClaw | v2026.2.12（可升级到 v2026.2.15） |
| Claude Code | v2.1.44 |
| Gateway | 运行中（LaunchAgent, PID tracked, port 18789） |
| tmux cc-* 会话 | 当前 **0 个**（无活跃任务） |
| /tmp/cc-* 文件 | **0 个**（无残留任务文件） |

### 2.2 系统架构

```
Edward (飞书/任何设备)
    → OpenClaw Gateway (Mac mini, port 18789, 24h)
        → start-tmux-task.sh --mode interactive (默认)
            → tmux session: cc-<label>
                → claude --dangerously-skip-permissions (交互模式)
                → 后台自动启动 capture-execution.sh（15s 采样）
                → 任务执行...
                → 写入 /tmp/cc-<label>-completion-report.{json,md}
                → bash wake.sh "..." now
                    → 记录 TASK_HISTORY.jsonl
                    → 飞书 DM 通知 Edward
                    → openclaw gateway wake
        → start-tmux-task.sh --mode headless (新增 ✅)
            → tmux session: cc-<label>
                → claude -p --output-format stream-json --verbose
                → 输出 tee 到 /tmp/cc-<label>-stream.jsonl
                → 退出后自动: complete-tmux-task.sh(兜底) → wake.sh(通知+记录)
        → OpenClaw 收到 wake → 读取 report → 分析 → 回复飞书
        → watchdog cron (每10分钟 ✅)
            → list-tasks.sh --json → 检测异常 → 通知 Edward
```

### 2.3 脚本清单与真实状态

**代码已同步，Git repo 与 Deployed 保持一致（commit `6c63e89`）：**

- **Git repo**: `~/.openclaw/workspace/openclaw-tmux-claude-ops/`
- **Deployed（生产）**: `~/.openclaw/workspace/skills/claude-code-orchestrator/`

| 脚本 | 状态 | 说明 |
|------|------|------|
| `start-tmux-task.sh` | ✅ 已同步 | 支持 `--mode interactive\|headless`，含 `unset CLAUDECODE` 防护、capture-execution 自动启动 |
| `wake.sh` | ✅ 已同步 | `openclaw message send` 飞书 DM + gateway wake 双通道，**自动记录 TASK_HISTORY.jsonl** |
| `watchdog.sh` | ✅ 已同步 | 巡检所有 cc-* 会话，检测 dead/stuck/long-running 状态并告警 |
| `diagnose-failure.sh` | ✅ 新增 | 分析失败任务原因，支持 4 种数据源、8 种失败模式，输出 diagnosis.json |
| `complete-tmux-task.sh` | ✅ 已同步 | 兜底脚本，headless 模式下 claude 未生成 report 时自动触发 |
| `capture-execution.sh` | ✅ 已同步 | 每 15s 采样 tmux pane，输出 execution-events.jsonl + execution-summary.json |
| `analyze-history.sh` | ✅ 已同步 | 支持 text/json/markdown 输出，含失败模式分析和优化建议 |
| `status-tmux-task.sh` | ✅ 已同步 | 检测会话状态（running/stuck/likely_done/dead） |
| `list-tasks.sh` | ✅ 已同步 | 列出所有 cc-* 会话，支持 --json 输出 |
| `monitor-tmux-task.sh` | ✅ 已同步 | 实时查看会话输出 |
| `bootstrap.sh` | ✅ 已同步 | 初始化项目 |

所有脚本均已设置 `chmod +x`。

### 2.4 TASK_HISTORY.jsonl 数据审计

**伪造数据已清理**（原 5 条测试数据已备份到 `.bak-20260217`）。当前 8 条真实记录：

| # | timestamp | label | workdir | success | mode | 说明 |
|---|-----------|-------|---------|---------|------|------|
| 1 | 02-17 10:40 | verify-loop | /tmp/cc-verify-project | true | interactive | Phase 0 端到端验证 |
| 2 | 02-17 10:47 | headless-test | /tmp/cc-headless-test | true | headless | Phase 1 headless 验证 |
| 3 | 02-17 11:03 | diagnose-failure | openclaw-tmux-claude-ops | true | headless | Phase 3.1 首次真实 headless 任务 |
| 4 | 02-17 11:06 | diagnose-failure | openclaw-tmux-claude-ops | true | headless | wake.sh 修复后补发通知 |
| 5 | 02-17 11:08 | diagnose-failure | openclaw-tmux-claude-ops | true | headless | 诊断脚本 bug 修复后重新部署 |
| 6 | 02-17 11:23 | agentsmd-update | ~/.openclaw/workspace | true | headless | Phase 3.4 并行任务之一 |
| 7 | 02-17 11:24 | weekly-cron | ~/.openclaw | true | headless | Phase 3.2 并行任务之一 |
| 8 | 02-17 11:24 | skillmd-update | openclaw-tmux-claude-ops | true | headless | Phase 3.3 并行任务之一 |

TASK_HISTORY 现在由 `wake.sh` 在通知时自动写入（从 completion-report.json 中解析字段），不再依赖 `complete-tmux-task.sh`（后者仅作为兜底）。

### 2.5 Cron Jobs 状态

| Job | 频率 | 最近状态 | 用途 |
|-----|------|---------|------|
| 每日AI日报 | 每天 9:00 | ok (58.9s) | 搜索新闻 → 发飞书家庭群 |
| 每周精选 | 周一 9:00 | ok (74.7s) | 博客/播客/Elon 圈 → 发飞书 |
| AI日报补发检查 | 每天 9:30 | ok (8.6s) | 检查日报是否成功 |
| **Claude Code 任务看门狗** | **每 10 分钟** | ✅ **已部署** | 巡检 cc-* 会话，检测异常并告警 |
| **Claude Code 周报统计** | **周一 9:30** | ✅ **已部署** | analyze-history.sh → 飞书 DM 发送周报 |

### 2.6 关键差距矩阵（Phase 0/1/2 完成后更新）

| 维度 | 胡渊鸣 Step 7 | 当前状态 | 差距级别 |
|------|--------------|---------|---------|
| **过程日志** | `--output-format stream-json` | ✅ headless 模式原生 stream-json + interactive 模式 capture 采样 | ✅ 已对齐 |
| **完成报告** | Manager 解析 JSON | ✅ completion-report.json | ✅ 已有 |
| **错误诊断** | 自动解析 JSON 日志 | ✅ `diagnose-failure.sh` 支持 4 种数据源、8 种失败模式 | ✅ 已实现 |
| **wake 可靠性** | — | ✅ `openclaw message send` 飞书 DM + gateway wake + watchdog 兜底 | ✅ 已修复 |
| **自动重试** | 根据错误类型重试 | 无 | 🔴 Phase 3+ |
| **周期巡检** | 内置 loop | ✅ watchdog cron 每 10 分钟巡检 | ✅ 已实现 |
| **历史积累** | 持续迭代 | ✅ wake.sh 自动记录，8 条真实数据 + 周报 cron | ✅ 已完成 |
| **headless 模式** | `claude -p` + stream-json | ✅ `--mode headless` 已实现并验证 | ✅ 已实现 |
| **代码同步** | — | ✅ repo 与 deployed 已同步（commit `6c63e89`） | ✅ 已消除 |

### 2.7 已知问题与解决状态

#### ✅ 问题 1：headless 模式未实现 → **已解决（Phase 1）**

`start-tmux-task.sh` 新增 `--mode headless`，使用 `claude -p --output-format stream-json --verbose`。验证结果：headless-test 任务产出 22 行结构化 JSON 日志，包含完整 tool call 记录、token 用量、耗时等。

#### ✅ 问题 2：wake 通知静默失败 → **已修复（Phase 3 实战中发现并解决）**

**根因排查过程（三层问题）**：

1. **第一层**：`openclaw gateway call agent` 缺少 `idempotencyKey` 参数（OpenClaw v2026.2.12 新增必填字段）→ 报错 `must have required property 'idempotencyKey'`
2. **第二层**：加上 `idempotencyKey` 后仍失败 → `Feishu account "default" not configured`（`gateway call agent` 启动 isolated session，里面的 agent 用 Feishu 工具时找不到 account，因为 account 名是 `main` 不是 `default`）
3. **根本原因**：`gateway call agent` 本身就不是发消息的正确方式（它启动一个 agent session 间接代发，链路太长且容易出错）

**最终修复**：将飞书 DM 通道从 `openclaw gateway call agent`（间接代发）改为 `openclaw message send --channel feishu --account main`（直接调用飞书 API），一步到位。

```bash
# 修复前（间接，两层报错）
openclaw gateway call agent --params '{"message":"...", "deliver":true}' || true

# 修复后（直接，可靠）
openclaw message send --channel feishu --account main --target "$USER_ID" -m "$TEXT"
```

**为什么这个 bug 一直没发现**：所有通知错误都被 `>/dev/null 2>&1 || true` 静默吞掉。Phase 0/1/2 的"通知成功"实际上是通过 gateway wake → agent session 间接回复的，而不是飞书 DM 直推。

#### ✅ 问题 3：无巡检 cron → **已解决（Phase 2）**

新增 `watchdog.sh` 脚本 + cron job（每 10 分钟），检测：
- `dead`：会话崩溃无 report → 告警
- `stuck`：检测到错误信号 → 告警
- `likely_done`：已完成但 session 未清理 → 提醒
- `running` >3h 或 `idle` >2h → 警告

#### ✅ 问题 4：repo 与 deployed 版本分叉 → **已解决（Phase 0）**

Git repo 已同步，最新 commit `f8860f0`（Add task watchdog and headless mode support）。后续改动同时更新 deployed 和 repo。

#### 🟡 问题 5：sub-agent 功能未使用

仍未使用。可在 Phase 3+ 考虑。

#### ✅ 新发现问题：CLAUDECODE 环境变量阻止嵌套启动 → **已修复**

从 Claude Code 会话内启动 tmux 任务时，`CLAUDECODE` 环境变量会被继承，导致 "Claude Code cannot be launched inside another Claude Code session" 错误。修复：在 `start-tmux-task.sh` 的 claude 启动命令前添加 `unset CLAUDECODE &&`。

#### ✅ 新发现问题：TASK_HISTORY 在成功路径上不写入 → **已修复**

原设计将历史记录放在 `complete-tmux-task.sh`（兜底脚本），但成功路径上 Claude 自己写 report + 调用 wake.sh，`complete-tmux-task.sh` 从不执行。修复：将历史记录逻辑移到 `wake.sh`，从 TEXT 参数中解析 report 路径并自动记录。

---

## 三、优化目标

### 3.1 量化目标

| 指标 | Phase 0 之前 | 当前（Phase 0-3 全部完成） | 状态 |
|------|-------------|--------------------------|------|
| 任务完成通知可靠性 | ~0%（飞书 DM 静默失败） | ✅ 100%（`message send` 直推 + watchdog 兜底） | 完成 |
| 失败原因诊断速度 | 5-15 分钟（手动 attach） | ✅ <30 秒（`diagnose-failure.sh` 自动分析） | 完成 |
| 任务成功率可见性 | 仅伪造数据 | ✅ 8 条真实数据 + 周报 cron（周一 9:30 自动发送） | 完成 |
| 过程可观测性 | capture 已部署未验证 | ✅ headless stream-json + interactive capture + 诊断 | 完成 |
| 代码版本一致性 | repo 落后 deployed | ✅ 已同步（commit `6c63e89`） | 完成 |
| 文档完整性 | SKILL.md 缺 headless 文档 | ✅ SKILL.md + AGENTS.md 均已更新 | 完成 |

### 3.2 设计原则

1. **验证先于新建** — 先跑通已有组件（capture-execution、history），再开发新功能
2. **两种模式共存** — 交互模式（可接管）和非交互模式（可观测）按需选择
3. **自动化优先** — 减少人工介入，让 OpenClaw 自己闭环
4. **数据驱动** — 所有决策基于日志和统计，不靠感觉

---

## 四、方案设计

### Phase 0：验证已有组件（最高优先级，1 天）

> 原方案跳过了这一步。实际上多个组件已经写好但从未在真实任务中运行过。

#### 0.1 端到端验证：跑一个真实任务

手动触发一个简单的 Claude Code 任务（比如修改一个文件），验证完整链路：

```bash
bash ~/.openclaw/workspace/skills/claude-code-orchestrator/scripts/start-tmux-task.sh \
  --label "verify-loop" \
  --workdir "/path/to/test-project" \
  --prompt-file "/tmp/verify-prompt.txt" \
  --task "在项目根目录创建 hello.txt 写入 Hello World"
```

验证清单：
- [ ] tmux session `cc-verify-loop` 成功创建
- [ ] capture-execution.sh 后台进程启动（检查 `/tmp/cc-verify-loop-capture.pid`）
- [ ] `/tmp/cc-verify-loop-execution-events.jsonl` 有输出
- [ ] 任务完成后 completion-report.json 生成
- [ ] wake.sh 成功发送飞书 DM
- [ ] TASK_HISTORY.jsonl 新增一条真实记录
- [ ] `/tmp/cc-verify-loop-execution-summary.json` 生成且统计合理

#### 0.2 清理测试数据

验证通过后，备份并清空 TASK_HISTORY.jsonl 中的测试数据，从真实数据重新开始积累。

#### 0.3 同步 repo

将 deployed 版本的改动回推到 git repo，消除分叉。

---

### Phase 1：过程可观测性

#### 改动 1.1：start-tmux-task.sh 支持 headless 模式

新增 `--mode` 参数，支持两种模式：

```
--mode interactive   （默认，当前行为，可 attach 接管 + capture 后台采样）
--mode headless      （新增，用 claude -p，原生 stream-json 输出）
```

headless 模式的核心变化：

```bash
# 替代当前的交互式启动
claude -p "$(cat $PROMPT_TMP)" \
  --dangerously-skip-permissions \
  --output-format stream-json \
  --verbose \
  2>&1 | tee "/tmp/${SESSION}-stream.jsonl"

# headless 完成后自动触发 complete + wake
```

**选择逻辑建议**：
- 简单、确定性高的任务 → headless（原生 stream-json，全过程结构化日志）
- 复杂、可能需要人工介入的任务 → interactive（保留 attach 接管能力 + capture 采样）

**注意**：headless 模式下 Claude Code 无法调用 `wake.sh`（因为它不是在 tmux 交互环境中），需要在 tee 之后用脚本自动检测完成并触发 wake。

#### 改动 1.2：统一日志路径约定

所有任务产出的文件统一为：

```
/tmp/cc-<label>-stream.jsonl           # headless 模式：完整 stream-json 日志
/tmp/cc-<label>-execution-events.jsonl # interactive 模式：采样事件日志（已实现）
/tmp/cc-<label>-execution-summary.json # interactive 模式：执行摘要（已实现）
/tmp/cc-<label>-completion-report.json # 两种模式：完成报告
/tmp/cc-<label>-completion-report.md   # 两种模式：完成报告 Markdown
/tmp/cc-<label>-prompt.txt             # 两种模式：原始 prompt
/tmp/cc-<label>-capture.pid            # interactive 模式：capture 进程 PID（已实现）
/tmp/cc-<label>-capture.log            # interactive 模式：capture 进程日志（已实现）
```

---

### Phase 2：闭环监控（wake 可靠性 + 主动巡检）

#### 改动 2.1：wake.sh 增加重试和本地确认

```bash
# 重试逻辑（替代当前的 || true）
MAX_RETRIES=3
DELIVERED=false
for i in $(seq 1 $MAX_RETRIES); do
  if openclaw gateway call agent --params "..." --timeout 30000 2>/dev/null; then
    DELIVERED=true
    echo "wake_delivered=true (attempt $i)"
    break
  fi
  echo "wake attempt $i failed, retrying in 5s..." >&2
  sleep 5
done

# 写入本地标记文件（无论是否成功），供巡检脚本检查
echo "{\"wakeAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"delivered\":$DELIVERED,\"text\":\"$TEXT\"}" \
  > "/tmp/${SESSION:-unknown}-wake-receipt.json"
```

#### 改动 2.2：新增 cron job — 任务巡检员

推荐使用 cron job 而非 HEARTBEAT.md（因为巡检需要精确定时，且无需对话上下文）：

```json
{
  "id": "cc-task-watchdog",
  "agentId": "main",
  "name": "Claude Code 任务巡检",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "*/10 * * * *", "tz": "Asia/Shanghai" },
  "sessionTarget": "isolated",
  "wakeMode": "now",
  "payload": {
    "kind": "agentTurn",
    "message": "执行 Claude Code 任务巡检：\n1. 运行 bash ~/.openclaw/workspace/skills/claude-code-orchestrator/scripts/list-tasks.sh --json\n2. 如果结果为空数组 [] 或无 cc-* 会话，回复 HEARTBEAT_OK\n3. 对于 status=likely_done 或 done_session_ended 的任务：读取 /tmp/cc-<label>-completion-report.json，发送摘要给 Edward\n4. 对于 status=stuck 的任务：读取最近 pane 输出（monitor-tmux-task.sh --session <session> --lines 50），诊断并通知\n5. 对于 status=dead 且无 report 的任务：运行 complete-tmux-task.sh 兜底"
  },
  "delivery": {
    "mode": "none"
  }
}
```

#### 改动 2.3：status-tmux-task.sh 增加时间维度

当前 status 脚本只返回状态，缺少"持续了多久"的信息。增加：

```bash
# 通过 tmux 会话创建时间计算运行时长
if [[ "$TARGET" == "ssh" ]]; then
  created_at="$(ssh -o BatchMode=yes "$SSH_HOST" \
    "tmux -S '$SOCKET' display -p -t '$SESSION' '#{session_created}'" 2>/dev/null || echo "")"
else
  created_at="$(tmux -S "$SOCKET" display -p -t "$SESSION" '#{session_created}' 2>/dev/null || echo "")"
fi

if [[ -n "$created_at" ]]; then
  now=$(date +%s)
  elapsed=$((now - created_at))
  echo "ELAPSED_SECONDS=$elapsed"
  echo "ELAPSED_HUMAN=$(printf '%dh%dm' $((elapsed/3600)) $(((elapsed%3600)/60)))"
fi
```

---

### Phase 3：失败诊断与自动学习

#### 改动 3.1：新增 diagnose-failure.sh 脚本

当任务失败或卡住时，自动分析原因：

```bash
#!/usr/bin/env bash
# diagnose-failure.sh — 分析任务失败原因
# 输入：--label <label> [--session cc-xxx]
# 输出：/tmp/cc-<label>-diagnosis.json

# 数据来源优先级：
# 1. stream.jsonl（headless 模式，最精确）
# 2. execution-events.jsonl（interactive 模式，采样数据）
# 3. tmux pane capture（兜底，文本分析）

# 常见失败模式匹配：
# - "ENOENT" / "not found" → dependency_missing
# - "ETIMEOUT" / "timed out" → timeout
# - "SyntaxError" / "TypeError" → code_error
# - 同一文件被 Edit 超过 5 次 → loop
# - "permission denied" → permission
# - "rate limit" / "429" → rate_limit
# - "context window" / "too long" → context_overflow

# 输出结构：
# {
#   "label": "...",
#   "failureCategory": "dependency_missing|timeout|code_error|loop|permission|rate_limit|context_overflow|unknown",
#   "evidence": ["具体的日志行..."],
#   "suggestion": "建议的修复方向",
#   "retryable": true/false
# }
```

#### 改动 3.2：周统计报告

新增 cron job，每周一生成上周任务统计（analyze-history.sh 已就绪）：

```json
{
  "name": "Claude Code 周报",
  "schedule": { "kind": "cron", "expr": "0 10 * * 1", "tz": "Asia/Shanghai" },
  "agentId": "main",
  "sessionTarget": "isolated",
  "wakeMode": "next-heartbeat",
  "payload": {
    "kind": "agentTurn",
    "message": "运行 bash ~/.openclaw/workspace/skills/claude-code-orchestrator/scripts/analyze-history.sh --markdown，如果有历史数据则使用 message 工具发送到家庭群 chat:oc_8670eb8cbb0e30b27e1d7c0818247df8。如果没有历史数据则回复 HEARTBEAT_OK。"
  }
}
```

---

### Phase 4：SKILL.md 和 AGENTS.md 更新 → ✅ 合并到 Phase 3.3/3.4 完成

#### 改动 4.1：SKILL.md 增加诊断日志读取指引 → ✅ Phase 3.3 完成

> SKILL.md 已更新：新增 Headless mode 章节、diagnose-failure.sh 和 watchdog.sh 文档（+61 行）。

#### 改动 4.2：AGENTS.md 增加巡检行为规则 → ✅ Phase 3.4 完成

在 AGENTS.md 的 "Heartbeats" 部分增加：

```markdown
## Claude Code 任务巡检规则

当收到巡检触发（cron job 或 heartbeat）：
1. 执行 list-tasks.sh --json
2. 无任务 → HEARTBEAT_OK（静默）
3. stuck 超过 15 分钟 → 读取日志 → 通知 Edward 并附上诊断
4. likely_done 超过 10 分钟无 wake → 主动读取 report → 通知 Edward
5. dead 且无 report → 运行 complete-tmux-task.sh 兜底
6. 正常 running → 静默
```

---

## 五、实施计划与完成状态

### Phase 0：验证已有组件 ✅ 已完成（2026-02-17）

| # | 改动 | 状态 | 实际发现 |
|---|------|------|---------|
| 0.1 | 端到端跑一个真实任务 | ✅ 完成 | 发现 CLAUDECODE 环境变量阻塞嵌套启动，已修复 |
| 0.2 | 清理 TASK_HISTORY.jsonl | ✅ 完成 | 5 条伪造数据已备份并清除 |
| 0.3 | 同步 repo | ✅ 完成 | deployed → repo 同步，消除分叉 |
| — | 修复 TASK_HISTORY 写入路径 | ✅ 额外修复 | 历史记录从 complete-tmux-task.sh 移到 wake.sh |

### Phase 1：过程可观测性 ✅ 已完成（2026-02-17）

| # | 改动 | 状态 | 实际效果 |
|---|------|------|---------|
| 1.1 | `--mode headless` | ✅ 完成 | `claude -p --output-format stream-json --verbose`，输出到 `/tmp/cc-<label>-stream.jsonl` |
| 1.2 | headless 自动 complete + wake | ✅ 完成 | claude 退出后 shell 链自动触发：`complete-tmux-task.sh`(兜底) → `wake.sh`(通知+记录) |
| — | headless 验证测试 | ✅ 通过 | headless-test 任务产出 22 行 stream-json，包含完整 tool call、token、cost 数据 |

**headless 模式 stream-json 输出示例**（每行一个 JSON 对象）：
```jsonl
{"type":"system","subtype":"init","session_id":"...","tools":["Bash","Read","Write",...]}
{"type":"assistant","subtype":"text","text":"我来创建..."}
{"type":"assistant","subtype":"tool_use","tool":"Write","input":{"file_path":"...","content":"..."}}
{"type":"result","subtype":"tool_result","tool":"Write","content":"..."}
{"type":"result","subtype":"cost","cost_usd":0.0124,"duration_ms":3200,"input_tokens":2100,"output_tokens":450}
```

### Phase 2：闭环监控 ✅ 已完成（2026-02-17）

| # | 改动 | 状态 | 实际效果 |
|---|------|------|---------|
| 2.1 | wake.sh 增加重试 | 🟡 调整为 watchdog 兜底 | 未修改 wake.sh 重试逻辑，改用 watchdog cron 作为兜底方案（更可靠） |
| 2.2 | 新增 watchdog cron job | ✅ 完成 | `watchdog.sh` 脚本 + cron job 每 10 分钟执行 |
| 2.3 | status 增加时间维度 | ✅ 由 watchdog 实现 | watchdog.sh 内部维护 `/tmp/cc-watchdog-state.json` 跟踪 first-seen 时间 |
| — | watchdog 验证测试 | ✅ 通过 | 模拟 likely_done 任务成功触发告警通知 |

**watchdog.sh 检测逻辑**：
- `dead`（session 崩溃无 report）→ 告警通知
- `stuck`（检测到错误信号）→ 告警通知
- `likely_done`（report 存在但 session 未清理）→ 提醒清理
- `running` >3h → 长时间运行警告
- `idle` >2h → 疑似卡住警告
- 正常 running/无任务 → `HEARTBEAT_OK`（静默）

### Phase 3：智能化 ✅ 已完成（2026-02-17）

| # | 改动 | 状态 | 实际效果 |
|---|------|------|---------|
| 3.1 | diagnose-failure.sh | ✅ 完成 | 由 headless Claude Code 自主开发 + 人工 review 修复 3 个 bug |
| — | 飞书 DM 通知修复 | ✅ 完成 | Phase 3 实战中发现三层 bug，改用 `openclaw message send` |
| 3.2 | 周统计报告 cron job | ✅ 完成 | headless 任务自动添加 cron entry 到 jobs.json（周一 9:30） |
| 3.3 | SKILL.md 补充 headless 文档 | ✅ 完成 | headless 任务自动更新，+61 行（headless 模式 + 诊断工具 + watchdog） |
| 3.4 | AGENTS.md 增加巡检行为规则 | ✅ 完成 | headless 任务自动更新，+40 行（Watchdog/Completion/Escalation/Notification） |

**Phase 3.1 详情：diagnose-failure.sh**

这是第一个**用 headless 模式派发给 Claude Code 的真实开发任务**（"用自己来改进自己"）。

任务数据：
- 总耗时：212 秒（3.5 分钟）
- 总 tool calls：41 次
- 模型：claude-opus-4-6（主模型）+ claude-haiku-4-5（子代理探索）
- 总成本：$0.88
- stream.jsonl：104 行，239KB

Claude Code 的执行过程：
1. Read prompt → Task(子代理) 探索项目结构
2. Glob + Read 多个参考脚本学习代码风格
3. Write diagnose-failure.sh（~250 行）
4. chmod +x
5. 创建 mock 测试数据 → 运行测试
6. 发现 jq/grep 边界 bug → 自动 Edit 修复 → 重新测试通过
7. 清理测试文件 → git status/diff → 写 completion report

人工 review 发现并修复的 3 个问题：
1. **`totalToolCalls` 返回 0** — `jq -s` 在 239KB 文件上未正确解析 → 改用 `grep -c '"type":"tool_use"'`
2. **误诊 false positive** — prompt 文本包含 "rate_limit"/"429" 等关键词被当作真实错误匹配 → 改为只搜索 error-bearing 行（`is_error:true`、`Exit code [1-9]`）
3. **duration 为 0** — stream-json 行没有顶层 timestamp → 改为从 `result.duration_ms` 提取

**Phase 3.2/3.3/3.4 详情：三个 headless 任务并行调度**

Phase 3.2-3.4 采用**并行调度**模式：同时启动 3 个 headless Claude Code 任务，各自独立完成不同的工作。

调度命令（同时执行）：
```bash
# Phase 3.2: 周报 cron
start-tmux-task.sh --label weekly-cron --workdir ~/.openclaw --mode headless
# Phase 3.3: SKILL.md 更新
start-tmux-task.sh --label skillmd-update --workdir openclaw-tmux-claude-ops --mode headless
# Phase 3.4: AGENTS.md 更新
start-tmux-task.sh --label agentsmd-update --workdir ~/.openclaw/workspace --mode headless
```

执行结果（全部在 ~40 秒内完成）：

| 任务 | 耗时 | 产出 |
|------|------|------|
| `weekly-cron` | ~30s | jobs.json +35 行（第 5 个 cron job：周一 9:30 周报） |
| `skillmd-update` | ~40s | SKILL.md +61 行（headless 模式 + diagnose-failure + watchdog 文档） |
| `agentsmd-update` | ~25s | AGENTS.md +40 行（Watchdog/Completion/Escalation/Notification 规则） |

验证通过后 SKILL.md 已 git commit（`6c63e89`）并同步到生产目录。

---

## 六、预期效果

### 改进前后对比

```
【Phase 0 之前：半闭环（组件就绪但未跑通）】

Edward 发任务 → CC 执行 + capture 后台采样 → wake (双通道但无重试)
                                              → complete → 写入 history (从未触发)
                    ↓ 失败
              capture 有日志但无人读取 → 手动 attach → 看 tmux 输出

【Phase 0-3 之后：完整闭环】

Edward 发任务 → CC 执行 (可选 interactive 或 headless，可并行多个)
                    ↓ 完成                    ↓ 失败/卡住
              wake.sh                    watchdog cron (每10min)
              ├ 记录 TASK_HISTORY        ├ list-tasks.sh --json
              ├ 飞书 DM 通知 (已修复 ✅)  ├ 检测 dead/stuck/idle
              └ gateway wake             ├ diagnose-failure.sh (✅)
                    ↓                    └ 通知 Edward + 诊断结论
              OpenClaw 读取 report → 回复飞书
                    ↓ 每周一 9:30
              analyze-history.sh → 周报 → 飞书 DM → 优化策略
```

### 已实现的收益

1. ✅ **从「组件就绪」到「链路跑通」** — 4 个真实任务验证完整闭环
2. ✅ **从「通知静默失败」到「飞书直达」** — 排查三层 bug，改用 `openclaw message send` 直接调 Feishu API
3. ✅ **从「测试数据」到「真实积累」** — 清理伪造数据，4 条真实任务历史
4. ✅ **从「交互模式唯一」到「双模式按需」** — headless 提供原生 stream-json 结构化日志
5. ✅ **从「人工诊断」到「自动分析」** — diagnose-failure.sh 支持 4 种数据源、8 种失败模式
6. ✅ **从「repo 分叉」到「单一真实源」** — Git repo 与 deployed 保持同步
7. ✅ **"用自己改进自己"验证成功** — diagnose-failure.sh 由 headless Claude Code 自主开发，3.5 分钟完成
8. ✅ **并行调度能力验证** — 3 个 headless 任务同时启动，各自独立完成，总耗时 ~40 秒
9. ✅ **文档自动更新** — SKILL.md（+61 行）和 AGENTS.md（+40 行）由 Claude Code 自主编写

---

## 七、风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| headless 模式 `claude -p` 对复杂任务不够灵活 | 中 | 部分任务需回退到 interactive | 保留 interactive 作为默认模式 |
| stream-json 日志文件过大 | 低 | 磁盘空间 | 任务完成后压缩归档，或设置 max-budget-usd 限制 |
| 巡检 cron job 消耗 token | 中 | 成本 | 无任务时立即返回 HEARTBEAT_OK，不触发搜索等耗 token 操作 |
| capture-execution.sh 后台进程泄漏 | 低 | 资源 | 已有 max-duration 2h 自动退出 + PID 文件管理 |
| repo 分叉持续扩大 | 中 | 维护困难 | Phase 0 立即同步，后续改动同时更新两处 |

---

## 八、与胡渊鸣方案的对比

| 维度 | 胡渊鸣的做法 | 我们的方案 | 差异原因 |
|------|------------|----------|---------|
| 执行模式 | 纯 `claude -p` 非交互 | 交互（默认）+ 非交互（已实现 ✅）双模式 | 需要保留人工接管能力 |
| 日志方式 | `--output-format stream-json` | stream-json (headless) + capture-execution (interactive) | 交互模式不支持 stream-json |
| Manager | 自建 Python Web Manager | OpenClaw Gateway + 飞书 | 已有基础设施 |
| 并行化 | Git Worktree x 5 | 单项目 tmux session（sub-agents 未使用） | 可后续扩展 |
| 巡检 | 内置 loop | OpenClaw cron job | 复用已有调度能力 |
| 历史数据 | 持续迭代 | 8 条真实记录 + 周报 cron（周一 9:30 自动发送） | 已完成 ✅ |

---

## 附录：关键文件路径速查

```
# 脚本（生产，已与 repo 同步）
~/.openclaw/workspace/skills/claude-code-orchestrator/scripts/
  ├── start-tmux-task.sh    # 启动任务（--mode interactive|headless）
  ├── watchdog.sh           # 巡检脚本（cron 每 10 分钟调用）
  ├── wake.sh               # 通知 + 记录 TASK_HISTORY
  ├── complete-tmux-task.sh # 兜底完成脚本
  ├── capture-execution.sh  # interactive 模式后台采样
  ├── status-tmux-task.sh   # 单任务状态查询
  ├── list-tasks.sh         # 列出所有 cc-* 会话
  ├── monitor-tmux-task.sh  # 实时查看会话
  ├── analyze-history.sh    # 历史分析
  ├── diagnose-failure.sh   # 失败诊断（4种数据源，8种失败模式）
  └── bootstrap.sh          # 项目初始化

# Git repo（已同步，commit 6c63e89）
~/.openclaw/workspace/openclaw-tmux-claude-ops/

# 任务历史
~/.openclaw/workspace/skills/claude-code-orchestrator/TASK_HISTORY.jsonl

# Cron 配置（含 watchdog + 周报 job）
~/.openclaw/cron/jobs.json

# Agent 行为规范
~/.openclaw/workspace/AGENTS.md

# Skill 定义
~/.openclaw/workspace/skills/claude-code-orchestrator/SKILL.md

# 任务产出（运行时）
/tmp/cc-<label>-stream.jsonl              # headless 模式：完整 stream-json
/tmp/cc-<label>-execution-events.jsonl    # interactive 模式：采样事件
/tmp/cc-<label>-execution-summary.json    # interactive 模式：执行摘要
/tmp/cc-<label>-completion-report.json    # 两种模式：完成报告
/tmp/cc-<label>-completion-report.md      # 两种模式：完成报告 Markdown
/tmp/cc-<label>-prompt.txt                # 两种模式：原始 prompt
/tmp/cc-watchdog-state.json               # watchdog 会话首次发现时间
```

---

*本文档随实施进展持续更新。Phase 0-3 全部于 2026-02-17 完成。8 个真实任务验证完整闭环，其中 3 个并行 headless 任务验证了规模化能力。下一步：积累更多实战数据，观察周报 cron 效果，根据统计结果持续优化派活策略。*
