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

### 下一步（会话恢复后直接做）

1. 做“复杂数组对象编辑器”并补齐：
- `agent.tool_filter_groups[*].*`
- `diagnostics.otel_headers[*].*`
- `session.identity_links[*].*`
- `channels.external...transport.env[*].*`
- `reliability.model_fallbacks[*].*`
2. 启动 `memory` 专项分块（112 项，优先 `backend/api/search/lifecycle`）
3. 补齐 `peripherals`（含 `boards[*]`）并完成本阶段收口
