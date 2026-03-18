# NullHubX 阶段性任务表

执行顺序：Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4

| 阶段 | 目标 | 任务 | 状态 |
| --- | --- | --- | --- |
| Phase 0 | CLI 与实例页最小闭环 | CLI 安装与启动链路接通；实例详情页修复 404 | done |
| Phase 1 | Agent 管理后端与基础 UI | 后端 `agents/profiles` + `agents/bindings` API；前端 Agents 页基础表单 | done |
| Phase 2 | UI 可用性与防错 | 前端表单校验；下拉/建议输入；实例页汇总指标 | done |
| Phase 3 | 配置合并与运行态验证 | Profiles 合并保留未知字段；真实服务冒烟与 curl 回归脚本 | done |
| Phase 4 | 体验收尾与回归 | UI 细节优化；核心链路回归用例整理 | done |

## Phase 2 执行记录
1. 前端表单校验（完成）
2. Channel/PeerKind 建议输入（完成）
3. 实例页 Profiles/Bindings 汇总（完成）

## Phase 3 执行记录
1. Profiles 合并保留未知字段（完成）
2. 新增并执行 `tests/smoke_agents_api.py`（完成）
3. 冒烟覆盖：profiles/bindings GET+PUT roundtrip、错误分支校验、legacy topic id 规范化与配置恢复（完成）

## Phase 4 执行记录
1. 全局样式与核心组件视觉统一（首轮完成）
2. 新增 `InstanceAgentsPanel` 并接入实例详情页（完成）
3. 新增 `tests/regression_core_flow.sh`，统一覆盖核心 API + 实例 config/logs + agents 冒烟（完成）
4. 新增 `docs/regression-checklist.md`，固化执行方式与判定标准（完成）
