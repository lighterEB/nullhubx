# Phase 5 - P0/P1 扩展（Iteration 2）

## 目标

在已完成 P0 基础块的前提下，快速扩大可视化覆盖面，优先补齐：

1. 高频通用静态区块（`browser/cost/cron/scheduler/identity/...`）
2. 渠道账号缺失字段（尤其是 `account_id` 与平台特有项）
3. 渲染器能力缺口（`Models` 区仅支持 `text/number` 的问题）

## 本次改动

1. `configSchemas.ts` 扩展
- 新增/补齐静态区块字段：
  - `agent/autonomy/diagnostics/gateway/reliability/security/runtime/tools/session/models`
  - 新增区块：`browser/cost/cron/scheduler/identity/heartbeat/a2a/composio/hardware/tunnel/advanced_maps`
- 渠道 schema 大规模补齐：
  - 已有渠道增加 `account_id` 及平台特有字段（如 `telegram`、`slack`、`web`、`nostr`、`webhook` 等）
  - 新增渠道：`external`、`max`、`teams`

2. `ConfigEditorUI.svelte` 改造
- `Models` 区渲染器补齐类型支持：
  - 从仅支持 `number/text` 扩展到 `toggle/number/text/password/select/list`
- 去除 `Models` 区重复的 fallback 专用块，统一纳入 schema 渲染

3. catalog/coverage 同步
- 重新执行 `python3 tools/nullclaw_config_catalog.py`
- 产物：
  - `docs/nullclaw-config-catalog.json`
  - `docs/nullclaw-ui-coverage-report.md`

## 验证

执行：

```bash
python3 tools/nullclaw_config_catalog.py
cd ui && npm run build
```

结果：
- catalog 统计：`catalog_paths=511`
- UI 覆盖：`381`
- 覆盖率：`74.56%`
- 前端构建：通过

## 覆盖率变化

- 迭代前：`37.57%`（`192/511`）
- 迭代后：`74.56%`（`381/511`）
- 提升：`+36.99pp`

## 仍未覆盖（本轮后）

1. 复杂数组对象路径（需要结构化数组编辑器）
- `agent.tool_filter_groups[*].*`
- `diagnostics.otel_headers[*].*`
- `session.identity_links[*].*`
- `channels.external.accounts.<account>.transport.env[*].*`
- `reliability.model_fallbacks[*].*`

2. 大块功能未接入
- `memory.*`（112 项）
- `peripherals.*`（6 项）

## 下一轮建议

1. 增加“数组对象编辑器”组件（key/value、对象列表）
2. 专项接入 `memory` 分块（按后端类型分页：`redis/postgres/search/lifecycle/qmd`）
3. 补齐 `peripherals`（含 `boards[*]`）
