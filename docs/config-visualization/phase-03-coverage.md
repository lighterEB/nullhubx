# Phase 3 - UI 覆盖差异（Report v1）

## 目标

量化“NullClaw 全量配置项”与“NullHubX 当前可视化配置”的差距。

## 实施

- 使用 `tools/nullclaw_config_catalog.py` 生成覆盖报告
- 报告文件：`docs/nullclaw-ui-coverage-report.md`

## 结果（2026-03-18）

- Catalog 字段：143
- UI 已覆盖：15
- UI 未覆盖：128
- 覆盖率：10.49%

## 关键缺口

1. `memory.*`（82 项）几乎全缺失
2. `gateway.*` 全缺失
3. `http_request.*` 全缺失
4. `tunnel.*` 全缺失
5. `security.*` 全缺失
6. `models.providers.*` 动态 provider 字段覆盖不足

## 结论

当前可视化编辑器只覆盖了局部配置；要实现“完整可视化配置”，必须进入 schema 生成和分块渲染阶段。
