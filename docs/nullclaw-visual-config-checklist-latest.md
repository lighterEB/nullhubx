# NullClaw 最新版可视化配置清单

日期：2026-03-30

基线来源：
- 最新同步后的 `nullclaw/main`：`52015f6`
- 已合并并推送的工作分支：`my-nullclaw@e9469b7`
- 最新 catalog：`docs/nullclaw-config-catalog.json`
- 最新覆盖报告：`docs/nullclaw-ui-coverage-report.md`

## 当前结论

- Catalog 字段总数：`525`
- UI 已覆盖字段：`525`
- UI 未覆盖字段：`0`
- 当前覆盖率：`100.00%`

配置收口的重点已经从“补零散字段”转成“最终回归与交付验证”。最新版 catalog 字段当前都已有可视化入口。

## 现有前端能力边界

当前前端可视化能力分成两类：

- `nullclaw`：`ConfigEditorUI.svelte` + `configSchemas.ts`
- `nullboiler/nulltickets`：`StructuredConfigEditor.svelte` + `componentConfigSchemas.ts`

对 `nullclaw` 来说，现有 renderer 适合直接承接：

- `text`
- `password`
- `number`
- `toggle`
- `select`
- `list`

现有 renderer 不适合直接承接：

- 数组对象
- key/value 映射
- 复杂嵌套对象数组
- 需要按子系统拆分的超大配置块

## 可视化配置清单

### A. 已覆盖且可继续沿用现有 renderer

- [x] `models / providers`
- [x] `agent` 主体基础项
- [x] `autonomy`
- [x] `browser`
- [x] `gateway`
- [x] `reliability` 基础项
- [x] `security`
- [x] `runtime`
- [x] `tools`
- [x] `http_request`
- [x] `scheduler / cron / cost / identity / heartbeat / tunnel / a2a / composio / hardware`
- [x] 大部分既有 `channels.*`

### B. 可用现有 renderer 快速补齐

这部分主要是新增标量、枚举、布尔或简单列表，不需要先造新组件。

- [x] `agent.timezone`
- [x] `channels.wechat.accounts.<account>.account_id`
- [x] `channels.wechat.accounts.<account>.allow_from`
- [x] `channels.wechat.accounts.<account>.app_id`
- [x] `channels.wechat.accounts.<account>.app_secret`
- [x] `channels.wechat.accounts.<account>.callback_token`
- [x] `channels.wechat.accounts.<account>.encoding_aes_key`
- [x] `channels.wecom.accounts.<account>.account_id`
- [x] `channels.wecom.accounts.<account>.allow_from`
- [x] `channels.wecom.accounts.<account>.callback_token`
- [x] `channels.wecom.accounts.<account>.corp_id`
- [x] `channels.wecom.accounts.<account>.encoding_aes_key`
- [x] `channels.wecom.accounts.<account>.webhook_url`
- [x] `diagnostics.otel_headers`

这一组的目标不是“新设计”，而是把 upstream 新增的渠道和字段先补进 schema，避免最新版源码出来后 UI 立刻掉队。

### C. 需要新编辑器能力后才能接入

这部分不建议继续硬塞进 `text/list`。

#### C1. 数组对象编辑器

- [x] `agent.tool_filter_groups[*].keywords`
- [x] `agent.tool_filter_groups[*].mode`
- [x] `agent.tool_filter_groups[*].tools`
- [x] `session.identity_links[*].canonical`
- [x] `session.identity_links[*].peers`
- [x] `reliability.model_fallbacks[*].model`
- [x] `reliability.model_fallbacks[*].fallbacks`
- [ ] `memory.qmd.paths[*].name`
- [ ] `memory.qmd.paths[*].path`
- [ ] `memory.qmd.paths[*].pattern`
- [x] `peripherals.boards[*].board`
- [x] `peripherals.boards[*].path`
- [x] `peripherals.boards[*].transport`
- [x] `peripherals.boards[*].baud`

#### C2. Key/Value 编辑器

- [x] `channels.external.accounts.<account>.transport.env[*].key`
- [x] `channels.external.accounts.<account>.transport.env[*].value`
- [x] `diagnostics.otel_headers[*].key`
- [x] `diagnostics.otel_headers[*].value`

### D. 需要单独分块接入的大配置域

#### D1. Memory

`memory.*` 已完成独立模块化，不再塞进通用折叠表单。

- [x] `memory.backend / profile / auto_save / citations / instance_id`
- [x] `memory.api.*`
- [x] `memory.postgres.*`
- [x] `memory.redis.*`
- [x] `memory.clickhouse.*`
- [x] `memory.lifecycle.*`
- [x] `memory.qmd.*`
- [x] `memory.search.*`
- [x] `memory.retrieval_stages.*`
- [x] `memory.response_cache.*`
- [x] `memory.reliability.*`
- [x] `memory.summarizer.*`

#### D2. Peripherals

- [x] `peripherals.enabled`
- [x] `peripherals.datasheet_dir`
- [x] `peripherals.boards[*].*`

## 实施优先级建议

### P0

- [x] 先补 `agent.timezone`
- [x] 先补 `wechat / wecom` 渠道 schema
- [x] 先补 `diagnostics.otel_headers` 的基础可视化入口

### P1

- [x] 新增“数组对象编辑器”
- [x] 新增“key/value 映射编辑器”
- [x] 接入 `tool_filter_groups`
- [x] 接入 `session.identity_links`
- [x] 接入 `reliability.model_fallbacks`
- [x] 接入 `external.transport.env`
- [x] 接入 `peripherals.boards`

### P2

- [x] 为 `peripherals` 建独立可视化分块
- [x] 给 `memory` 建专属配置入口和子树级 raw fallback
- [x] 为 `memory` 建独立可视化分块
- [x] 定义 `memory` 的 IA：Backend / Search / QMD / Lifecycle / Reliability / Cache / Summarizer
- [x] 保留 raw JSON 回退，直到 `memory.*` 收口完成

## 不建议本轮做的事

- [ ] 不建议继续在 `ConfigEditorUI.svelte` 里堆更多针对单个字段的特判
- [ ] 不建议把 `memory.*` 直接塞进现有通用 section 列表
- [ ] 不建议在 schema 未统一前同时大规模扩展 `ConfigEditorUI` 和 `StructuredConfigEditor`

## 验收标准

- [x] 新版 `nullclaw` upstream 新增的 `wechat / wecom / agent.timezone` 已进入 UI
- [x] 复杂结构不再伪装成 `text/list` 输入框
- [x] `memory` 至少完成模块拆分设计，而不是继续挂在 raw-only 状态里无人认领
- [x] 重新运行 `python3 tools/nullclaw_config_catalog.py` 后，覆盖率相对当前 `72.57%` 明显提升
