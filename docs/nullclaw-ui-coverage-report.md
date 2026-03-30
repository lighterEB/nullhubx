# NullClaw 配置可视化覆盖差异报告 (v2)

- Catalog 字段总数: **525**
- UI 已覆盖字段: **525**
- UI 未覆盖字段: **0**
- 覆盖率: **100.00%**

## 数据来源占比

- `config.example.json`: 141
- `config_parse.zig`: 159
- `config_types.zig`: 484

## 按顶层块统计（未覆盖优先）

| Top-level | Total | Missing |
| --- | ---: | ---: |
| `a2a` | 5 | 0 |
| `agent` | 19 | 0 |
| `agents` | 5 | 0 |
| `autonomy` | 6 | 0 |
| `browser` | 13 | 0 |
| `channels` | 222 | 0 |
| `composio` | 3 | 0 |
| `cost` | 5 | 0 |
| `cron` | 3 | 0 |
| `default_model` | 1 | 0 |
| `default_provider` | 1 | 0 |
| `default_temperature` | 1 | 0 |
| `diagnostics` | 18 | 0 |
| `gateway` | 8 | 0 |
| `hardware` | 6 | 0 |
| `heartbeat` | 2 | 0 |
| `http_request` | 8 | 0 |
| `identity` | 3 | 0 |
| `mcp_servers` | 1 | 0 |
| `memory` | 112 | 0 |
| `model_routes` | 1 | 0 |
| `models` | 8 | 0 |
| `peripherals` | 6 | 0 |
| `reasoning_effort` | 1 | 0 |
| `reliability` | 11 | 0 |
| `runtime` | 7 | 0 |
| `scheduler` | 4 | 0 |
| `secrets` | 1 | 0 |
| `security` | 15 | 0 |
| `session` | 11 | 0 |
| `tools` | 8 | 0 |
| `tunnel` | 9 | 0 |
| `workspace` | 1 | 0 |

## 未覆盖字段（前 160 项）


## 说明

- v2 引入了 `config_types.zig` 与 `config_parse.zig`，覆盖完整性高于 v1。
- 仍建议在后续阶段增加运行时样本采集，以补齐动态 map 的键约束。
