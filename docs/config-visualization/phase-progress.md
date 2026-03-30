# 阶段进度记录

## 2026-03-18

### 已完成

1. Phase 1（真相源策略）
- 明确权威优先级：`config_types.zig` > `config_parse.zig` > `config.zig` > `config.example.json` > docs
- 输出文档：`phase-01-truth-source.md`

2. Phase 2（字段目录）
- 新增脚本：`tools/nullclaw_config_catalog.py`
- 产出：`docs/nullclaw-config-catalog.json`
- 当前 catalog 叶子字段数：143

3. Phase 3（覆盖差异）
- 产出：`docs/nullclaw-ui-coverage-report.md`
- 当前覆盖率：10.49%（15/143）

4. Phase 4（catalog v2 精度升级）
- 脚本升级为 v2：引入 `config_types.zig` 结构化解析、`config_parse.zig` 叶子路径提取
- 产出更新：
  - `docs/nullclaw-config-catalog.json`（`version: 2`）
  - `docs/nullclaw-ui-coverage-report.md`（v2）
- 当前统计：
  - Catalog 字段：715
  - UI 已覆盖：142
  - 覆盖率：19.86%

5. Phase 5（P0 首轮落地）
- `ConfigEditorUI` 改为 `staticSections.slice(1)` 循环渲染，去除重复 section 模板
- 新增 P0 区块：
  - `Gateway`
  - `Reliability`
  - `Security`
- 构建验证：`cd ui && npm run build` 通过
- 覆盖率更新：22.52%（161/715）

6. Phase 5（P0/P1 扩展迭代 2）
- `configSchemas.ts` 大规模扩展：
  - 静态区块补齐：`browser/cost/cron/scheduler/identity/heartbeat/a2a/composio/hardware/tunnel/...`
  - 渠道字段补齐并新增：`external/max/teams`
- `ConfigEditorUI` 修复 `Models` 区类型渲染能力缺口（支持 `toggle/password/select/list`）
- 报告刷新：
  - `docs/nullclaw-config-catalog.json`
  - `docs/nullclaw-ui-coverage-report.md`
- 验证：`python3 tools/nullclaw_config_catalog.py`、`cd ui && npm run build` 均通过
- 覆盖率更新：74.56%（381/511）

7. Phase 6（后端驱动 UI 架构蓝图）
- 在不参考现有 UI 的前提下，仅按后端 API/状态模型输出页面 IA 和交互规则
- 明确四层配置模型：
  - Hub 共享层（providers/channels）
  - 实例运行层（auto_start/launch_mode/verbose）
  - 实例配置层（config raw/resolved）
  - Agent 路由层（profiles/bindings）
- 明确多实例与多 agent 布局、入口、按钮状态机、Tab 顺序
- 产出：`phase-06-backend-driven-ui-architecture.md`

8. Phase 6 - Stage A/B（已落地）
- Stage A 文档：`stage-a-shell-and-routing.md`
- Stage B 文档：`stage-b-instance-runtime.md`
- 已完成：
  - 顶层 IA 路由壳层：`/`、`/instances`、`/resources`、`/orchestration`、`/settings`
  - 实例详情固定 Tab 顺序与动作状态机
  - 启动参数弹层（临时覆盖）+ 持久默认设置（PATCH）
  - failed 态直达 `Logs(nullhubx)` 的恢复入口
  - 运行摘要增强（重启次数、健康失败计数、最近监控事件）
  - Stage B 相关构建告警清理

9. Phase 6 - Stage C（已落地）
- Stage C 文档：`stage-c-agents-workspace.md`
- 已完成：
  - Agents 子工作区拆分为 `Profiles/Bindings` 子 Tab
  - 跨表联动校验：Bindings 引用未持久化 Profiles 时阻塞保存并引导修复
  - 重复绑定规则检测（agent/channel/account/peer 组合）
  - 批量保存入口（按 `Profiles -> Bindings` 顺序）与 dirty tracking
  - 问题定位与保存反馈中文化

## 2026-03-19

### 已完成

1. Phase 6 - Stage B 状态源稳定性修复
- `statusStore` 主拉取从 `/api/status` 调整为 `/api/instances`。
- 实例详情页实例检测从 `/api/status` 调整为 `/api/instances`。
- 结果：`/api/status` 超时时，首页与实例详情不再因为状态接口失败而误判“无实例”。
- 执行记录同步：`stage-b-instance-runtime.md`（新增 2026-03-19 修复补充）。

2. Phase 6 - Stage B 详情页交互稳定性修复
- 新增单实例读取接口接入：`GET /api/instances/{component}/{name}`，详情页优先使用单实例快照。
- 仅在确认 404 时显示“当前状态快照中未找到该实例”，临时错误保留上次有效快照。
- 详情页“返回实例工作区”改为原生链接，避免异常状态下 `goto` 导航失效。

3. Phase 6 - Stage B 轮询与防重入修复
- 详情页状态拉取改为“重入丢弃”策略，移除请求排队循环，降低请求堆积和页面卡顿风险。
- 详情页辅助接口增加超时封顶（6s），避免慢接口拖住整页状态更新。
- 实例卡片 `start/stop/delete` 增加本地状态守卫，`starting/stopping` 阶段按钮保持置灰，防止重复触发。

4. Phase 6 - Stage B 路由参数与导航兜底修复
- 详情页状态拉取增加 URL 路径回退解析，避免 `$page.params` 异常时页面一直停留“正在获取实例状态”。
- 详情页返回入口/空状态返回入口切换为原生 `href`，提升 hydration 异常场景下的可用性。
- 空状态增加“立即重试”入口，便于手动恢复状态拉取。

5. Phase 6 - Stage B 交互卡死链路修复（第二轮）
- 实例卡片改为“卡片链接 + 独立动作区”结构，移除 `a > button` 无效交互嵌套，消除按钮事件竞争。
- 实例详情 `loadSummary` 从“单请求门闩”改为“请求序号淘汰旧响应”，避免慢请求导致新请求被长期阻塞。
- 实例详情 Tab 重置改为“仅在实例路由键变更时触发”，避免同一路由下误重置导致“点击无响应”。
- 在 `+layout.svelte` 前置全局状态订阅，首屏与跨页状态更新更快且更稳定。
- 构建验证：`cd ui && npm run build` 通过。

6. Phase 6 - Stage B 全面检查与预防回归（第三轮）
- `ComponentCard` 同步改造为“链接区 + 动作区”结构，清理同类交互嵌套隐患。
- 新增 `ui/scripts/interaction-guard.mjs`，固化交互风险扫描规则：
  - 禁止 `a` 内嵌交互控件
  - 禁止 `button` 内嵌 `a`
  - 全屏 `overlay/backdrop` 必须具备 `onclick` 释放入口
- `ui/package.json` 新增脚本：`npm run guard:interaction`
- 回归脚本 `tests/regression_core_flow.sh` 已接入 guard 检查。
- 本地验证：
  - `node ui/scripts/interaction-guard.mjs` 通过
  - `cd ui && npm run build` 通过
  - `bash tests/regression_core_flow.sh 19814` 通过（15/15）

### 下一步（会话恢复后直接做）

1. 进入 Phase 6 - Stage D：
- 配置分层落地（L1 资源中心、L3 raw/resolved 双视图、L4 保存顺序与冲突提示）
2. 进入 Phase 6 - Stage E：
- 可观测与收口（Logs/Usage/History/Memory/Skills/Integration 最小闭环 + 回归清单）
3. 做“复杂数组对象编辑器”并补齐：
- `agent.tool_filter_groups[*].*`
- `diagnostics.otel_headers[*].*`
- `session.identity_links[*].*`
- `channels.external...transport.env[*].*`
- `reliability.model_fallbacks[*].*`
4. 启动 `memory` 专项分块（112 项，优先 `backend/api/search/lifecycle`）
5. 补齐 `peripherals`（含 `boards[*]`）并完成本阶段收口
