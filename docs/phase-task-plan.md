# NullHubX 阶段性任务表

执行顺序：

1. 历史交付阶段：Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4
2. 当前前端修复阶段：FE-00 -> FE-01 -> FE-02 -> FE-03 -> FE-04 -> FE-05 -> FE-06 -> FE-07

| 阶段 | 目标 | 任务 | 状态 |
| --- | --- | --- | --- |
| Phase 0 | CLI 与实例页最小闭环 | CLI 安装与启动链路接通；实例详情页修复 404 | done |
| Phase 1 | Agent 管理后端与基础 UI | 后端 `agents/profiles` + `agents/bindings` API；前端 Agents 页基础表单 | done |
| Phase 2 | UI 可用性与防错 | 前端表单校验；下拉/建议输入；实例页汇总指标 | done |
| Phase 3 | 配置合并与运行态验证 | Profiles 合并保留未知字段；真实服务冒烟与 curl 回归脚本 | done |
| Phase 4 | 体验收尾与回归 | UI 细节优化；核心链路回归用例整理 | done |

## 前端修复阶段摘要

参考文档：[docs/frontend-remediation-checklist.md](/home/huspc/projects/nullhubx/docs/frontend-remediation-checklist.md)

视觉规范基线：[docs/frontend-visual-rules.md](/home/huspc/projects/nullhubx/docs/frontend-visual-rules.md)
视觉实施清单：[docs/frontend-visual-implementation-checklist.md](/home/huspc/projects/nullhubx/docs/frontend-visual-implementation-checklist.md)

| 阶段 | 目标 | 任务 | 状态 |
| --- | --- | --- | --- |
| FE-00 | 隔离修复范围 | 拆分当前前端修复与其它 WIP，确保后续提交可独立推进 | in_progress |
| FE-01 | 恢复 lint / check 门禁 | 修 ESLint 规则失效、typed lint 范围和当前 `svelte-check` 错误 | done |
| FE-02 | 修正路由与导航回归 | 修复 `/resources` 死链，统一导航与入口路由 | done |
| FE-03 | 重构错误处理职责 | 拆分底层请求错误和页面级 UI 提示职责 | done |
| FE-04 | 稳定 SSE 日志链路 | 收敛 SSE 与 fallback polling 状态机 | done |
| FE-05 | 补齐 i18n 与文案一致性 | 清理硬编码文案和双语混杂页面；剩余主要在 Agents / ConfigEditorUI | in_progress |
| FE-06 | 类型与风格收口 | 收紧新增 `any`、无用状态和风格漂移；`check/build` 已恢复通过 | in_progress |
| FE-07 | 回归验证与交付 | 执行 lint/check/build 与关键手工回归 | todo |

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

实例级 Agent 设计说明：[docs/instance-agent-management-design.md](/home/huspc/projects/nullhubx/docs/instance-agent-management-design.md)
实例级 Agent 实施清单：[docs/instance-agent-management-checklist.md](/home/huspc/projects/nullhubx/docs/instance-agent-management-checklist.md)

## 实例级 Agent 管理阶段
1. `AG-00`：done
2. `AG-01`：done
3. `AG-02`：in_progress
4. `AG-03`：done
5. `AG-04`：done
6. `AG-05`：done
7. `AG-06`：done
8. `AG-07`：done

## 前端视觉基线
1. 通用视觉与排版规则已固化到 `docs/frontend-visual-rules.md`
2. 后续 FE-06 与页面样式收口默认按该文档执行

## 前端视觉改造阶段
1. `V-00`：done
2. `V-01`：done
3. `V-02`：done
4. `V-03`：done
5. `V-04`：done
6. `V-05`：done
7. `V-06`：done
8. `V-07`：done

## 前端配置收口阶段
参考文档：[docs/frontend-config-convergence-plan.md](/home/huspc/projects/nullhubx/docs/frontend-config-convergence-plan.md)

1. `CFG-00`：done
2. `CFG-01`：done
3. `CFG-02`：in_progress
4. `CFG-03`：done
5. `CFG-04`：done
6. `CFG-05`：done
7. `CFG-06`：done
