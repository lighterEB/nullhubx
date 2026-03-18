# NullClaw 可视化配置工程（分阶段索引）

本目录用于保证“会话重启可快速衔接”。

## 阶段状态

| 阶段 | 目标 | 状态 | 文档 |
| --- | --- | --- | --- |
| Phase 1 | 定义配置真相源策略 | done | `phase-01-truth-source.md` |
| Phase 2 | 生成配置字段目录（catalog） | done | `phase-02-catalog.md` |
| Phase 3 | 输出 UI 覆盖差异报告 | done | `phase-03-coverage.md` |
| Phase 4 | 从 config_types/config_parse 提升 catalog 精度 | done | `phase-04-catalog-v2.md` |
| Phase 5 | Schema 渲染器与 P0/P1 扩展落地 | in_progress | `phase-05-p0-iteration-2.md` |

## 快速续接

1. 先看：`phase-progress.md`（最后完成阶段 + 下一个动作）
2. 再看：当前进行中阶段文档
3. 复现命令：

```bash
python3 tools/nullclaw_config_catalog.py
```

产物：
- `docs/nullclaw-config-catalog.json`
- `docs/nullclaw-ui-coverage-report.md`
