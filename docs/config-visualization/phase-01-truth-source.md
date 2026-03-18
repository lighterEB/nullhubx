# Phase 1 - 配置真相源策略

## 目标

定义 NullClaw 配置项的单一真相来源，避免 UI schema 与运行时解析漂移。

## 结论

配置字段与行为的权威优先级：

1. `src/config_types.zig`（类型与默认值）
2. `src/config_parse.zig`（实际解析/兼容/约束）
3. `src/config.zig`（顶层聚合与别名行为）
4. `config.example.json`（可运行样例与常见键）
5. `docs/zh/configuration.md`（用户向说明）

## 当前证据

- NullClaw 顶层配置块（24 个）定义见 `Config`：`src/config.zig`
- 默认值和枚举集中在 `src/config_types.zig`
- 解析兼容与约束在 `src/config_parse.zig`

## 对 NullHubX 的落地要求

1. UI schema 不再手工长期维护为主，改为“生成 + 补充元数据”模式
2. 每次升级 nullclaw 版本时，先刷新 catalog，再判定 UI 差异
3. 差异报告必须纳入回归产物
