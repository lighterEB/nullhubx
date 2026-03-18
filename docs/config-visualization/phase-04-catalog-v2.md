# Phase 4 - Catalog v2 精度升级

## 目标

把字段目录从“示例配置驱动”升级为“源码结构化驱动”，提升完整性和可维护性。

## 实施

脚本：`tools/nullclaw_config_catalog.py`（v2）

新增能力：

1. 解析 `config_types.zig` 的 `struct/enum` 定义
2. 从 `config.zig` 提取顶层 section 到类型映射
3. 递归展开 schema 字段路径（含默认值、枚举值）
4. 从 `config_parse.zig` 抽取实际解析叶子路径（真实可接收键）
5. 与 `config.example.json` 字段合并，生成统一 catalog
6. 自动输出 v2 覆盖差异报告

## 产出

1. `docs/nullclaw-config-catalog.json`
- `version: 2`
- `struct_count: 92`
- `enum_count: 14`

2. `docs/nullclaw-ui-coverage-report.md`
- 覆盖率更新为 `19.86%`（`142/715`）

## 结果解读

1. v2 比 v1 更接近真实配置面（引入了源码结构与解析逻辑）
2. 仍存在大量未覆盖字段，尤其是：
- `memory.*`
- `channels.*`（多账号 + 高级字段）
- `security.*`
- `runtime/tools/session/http_request/gateway/tunnel` 等块

## 限制

1. 目前是轻量解析器，复杂动态键仍可能需要运行时样本补齐
2. `channels` 同时存在 `accounts.<account>` 与 `[*]` 路径形态，后续在 Phase 5 统一为 UI 目标形态

## 下一阶段输入

以 v2 报告为基线，进入 Phase 5 的 P0 可视化实现。
