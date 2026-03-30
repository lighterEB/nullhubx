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
| Phase 6 | 后端驱动的 UI 架构蓝图（多实例/多 agent/配置分层） | done | `phase-06-backend-driven-ui-architecture.md` |

## 快速续接

1. 先看：`phase-progress.md`（最后完成阶段 + 下一个动作）
2. 再看：`phase-06-backend-driven-ui-architecture.md`（结构基线）
3. 再看：`stage-a-shell-and-routing.md`（壳层与路由落地）
4. 再看：`stage-b-instance-runtime.md`（实例运行态与动作总线落地）
5. 再看：`stage-c-agents-workspace.md`（Agents 子工作区落地）
6. 最后看：当前进行中阶段文档（实现细节）
7. 复现命令：

```bash
python3 tools/nullclaw_config_catalog.py
```

产物：
- `docs/nullclaw-config-catalog.json`
- `docs/nullclaw-ui-coverage-report.md`
