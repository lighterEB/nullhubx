# Phase 2 - 字段目录生成（Catalog v1）

## 目标

先建立可自动更新的字段目录，作为后续 UI 覆盖统计与任务拆分基础。

## 实施

- 新增脚本：`tools/nullclaw_config_catalog.py`
- 输入：
  - `/home/huspc/projects/nullclaw/config.example.json`
  - `/home/huspc/projects/nullclaw/src/config.zig`
  - `ui/src/lib/components/configSchemas.ts`
- 输出：`docs/nullclaw-config-catalog.json`

## 当前结果

- 叶子字段：143
- 顶层块（来自 `config.zig`）：24

## 限制（v1）

1. v1 以 `config.example.json` 为字段基线，可能漏掉仅在源码默认值中定义但示例未出现的字段
2. 尚未结构化提取 `config_types.zig/config_parse.zig` 的枚举、默认值、严格类型

## 下一阶段输入

- 在 v2 中接入源码级解析，提升字段完整性与类型精度
