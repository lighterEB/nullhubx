# 实例级 Agent 管理实施清单

参考设计说明：[docs/instance-agent-management-design.md](/home/huspc/projects/nullhubx/docs/instance-agent-management-design.md)

## 当前基线

- 当前模型已经固定为：`instance` 持有 `channels`，`instance` 持有 `agents`，`bindings` 在实例内部负责路由
- 当前 UI 入口位于实例详情页 `Agents` tab
- 当前后端已支持：
  - `GET/PUT /api/instances/{component}/{name}/agents/profiles`
  - `GET/PUT /api/instances/{component}/{name}/agents/bindings`
- 当前底层仍只读写实例 `config.json`
- 当前 `profiles` 支持按 `id` 保留未知字段；`bindings` 仍为整体替换

---

## 阶段总览

| 阶段 | 编号 | 主题 | 依赖 | 状态 |
| --- | --- | --- | --- | --- |
| Phase 0 | AG-00 | 范围冻结 | 无 | done |
| Phase 1 | AG-01 | API 契约补强 | AG-00 | done |
| Phase 2 | AG-02 | 路由规则可视化 | AG-00, AG-01 | in_progress |
| Phase 3 | AG-03 | 保存与重启语义收口 | AG-01 | done |
| Phase 4 | AG-04 | 表单能力增强 | AG-02 | done |
| Phase 5 | AG-05 | 规则校验增强 | AG-01, AG-04 | done |
| Phase 6 | AG-06 | 路由预览与调试 | AG-02, AG-05 | done |
| Phase 7 | AG-07 | 回归与文档 | AG-01 ~ AG-06 | done |

---

## Phase 0 / AG-00 范围冻结

目的：先把实例级 Agent 管理的边界和术语固定下来，避免后续设计再次混成“agent 直接接 channel”。

### 相关文件

- `docs/instance-agent-management-design.md`
- `docs/nullhubx-nullclaw-integration-mapping.md`
- `ui/src/lib/components/InstanceAgentsPanel.svelte`
- `src/api/config.zig`

### 待办

- [x] 固定边界：实例接 `channel`，agent 不直接持有 `channel`
- [x] 固定模型：`profiles` 负责角色配置，`bindings` 负责路由
- [x] 固定术语：`profile / binding / route / default model`
- [x] 固定非目标：不做全局 agent 注册中心，不做独立运行态数据库
- [x] 固定后续文档表述，避免继续把 `binding` 误写成“渠道配置”

### 验收标准

- [x] 设计文档、接口说明、前端文案使用同一套术语
- [x] 后续任务都以“实例配置切面”而非“独立资源系统”为前提

---

## Phase 1 / AG-01 API 契约补强

目的：把现有 `profiles / bindings` API 从“能用”收口成稳定契约。

### 相关文件

- `src/api/config.zig`
- `src/server.zig`
- `src/api/meta.zig`
- `docs/nullhubx-nullclaw-integration-mapping.md`

### 待办

- [x] 列清 `profiles` 的标准字段白名单
- [x] 列清 `bindings` 的标准字段白名单
- [x] 明确 `profiles` 未知字段保留策略是否继续按 `id` 合并
- [x] 明确 `bindings` 当前整体替换的兼容边界
- [x] 明确保存成功、校验失败、运行态未生效等返回语义
- [x] 收口错误消息格式，避免前端只能显示原始字符串
- [x] 评估是否需要增加“是否建议重启”的响应字段

### 验收标准

- [x] `profiles / bindings` 的请求与响应契约固定
- [x] 错误分支和兼容策略有明确文档
- [x] 前端不再需要猜测接口行为

### 当前进展

- [x] `AG-00` 已完成：设计说明、清单和集成映射文档已统一采用“实例持有 channel / bindings 负责路由”的术语
- [x] `AG-01` 已完成：agent API 读取响应新增 `contract_version / resource / ownership / field_policy`
- [x] `AG-01` 已完成：agent API 保存响应新增 `apply_state / runtime_effect / unknown_fields`
- [x] `AG-01` 已完成：校验失败与找不到配置现在返回结构化 `error_code`
- [x] “是否建议重启”的评估结论已固定：本阶段先返回 `apply_state = config_saved` 与 `runtime_effect = component_defined`，具体重启提示延后到 `AG-03`

---

## Phase 2 / AG-02 路由规则可视化

目的：让用户看懂 binding 真正在匹配什么，而不是把它当成普通表单行。

### 相关文件

- `ui/src/lib/components/InstanceAgentsPanel.svelte`
- `ui/src/lib/i18n/en-US.ts`
- `ui/src/lib/i18n/zh-CN.ts`

### 待办

- [ ] 明确展示 binding 的匹配维度：`channel / account / guild / team / peer / roles`
- [x] 明确提示“最终一次只会命中一个 agent”
- [x] 增加匹配优先级说明：精确匹配优先于宽泛匹配
- [x] 为“群级兜底 / topic 精确命中”提供更直观文案
- [x] 给重复或潜在冲突的 binding 增加可视化提示
- [x] 明确 `main/default` 的保留语义

### 验收标准

- [x] 用户能看懂一条 binding 会影响哪类消息
- [x] 用户不会再把 binding 误解为“给 channel 绑定多个 agent”

### 当前进展

- [x] `Bindings` 标签页已新增路由说明卡，明确“单次只会命中一个 agent”“Bindings 是实例内路由规则，不是 channel 所有权”
- [x] 每条 binding 现在都会展示优先级标签、匹配摘要、账户作用域和 peer 范围
- [x] UI 已新增同 scope 重叠提示、account-scoped peer 优先级提示、thread/topic 覆盖 group fallback 提示
- [x] `main/default` 的保留语义已直接写入界面说明和单条 binding 提示
- [ ] `guild / team / roles` 维度仍未在当前面板暴露：`AG-01` 的 `contract_version = 1` 目前只开放 `channel / account / peer`

---

## Phase 3 / AG-03 保存与重启语义收口

目的：明确“保存成功”和“运行态已生效”不是一回事。

### 相关文件

- `ui/src/lib/components/InstanceAgentsPanel.svelte`
- `ui/src/routes/instances/[component]/[name]/+page.svelte`
- `src/api/config.zig`

### 待办

- [x] 区分 `Save Profiles`、`Save Bindings`、`Save All`
- [x] 明确哪些改动只需保存配置
- [x] 明确哪些改动需要提示重启或刷新运行态
- [x] 统一成功、失败、部分成功的 banner / toast 反馈
- [x] 明确保存后实例摘要页是否需要刷新计数与状态

### 验收标准

- [x] 用户能明确知道“配置已保存”与“实例已应用”之间的关系
- [x] 不再出现保存成功但用户不知道是否生效的状态

### 当前进展

- [x] `InstanceAgentsPanel` 已改成结构化保存反馈：标题区分 `Save Profiles`、`Save Bindings`、`Save All`
- [x] 成功 banner 会直接展示 `apply_state` 与 `runtime_effect`，不再把“配置已落盘”和“运行态已应用”混为一谈
- [x] 前端会根据实例当前状态区分提示：
- [x] `stopped` -> 下次启动生效
- [x] `running/starting/restarting/stopping` -> 建议重启以确保立即应用
- [x] `failed` -> 建议通过重启重新应用
- [x] 保存成功后实例详情页摘要会主动刷新 agent 计数和状态卡片
- [x] 若当前状态允许重启，`Agents` 面板会直接提供“重启实例”入口

---

## Phase 4 / AG-04 表单能力增强

目的：减少手输错误，让高频配置不再依赖自由文本。

### 相关文件

- `ui/src/lib/components/InstanceAgentsPanel.svelte`
- `ui/src/lib/api/client.ts`
- `ui/src/lib/components/configSchemas.ts`

### 待办

- [x] `provider` 提供候选输入或引用现有 provider 列表
- [x] `model` 提供基础候选/格式提示
- [x] `channel` 改成受控建议输入，而不是纯文本
- [x] `peer.kind` / `peer.id` 的输入提示按 channel 区分
- [x] `account_id` 给出现有账号提示
- [x] 为常见 binding 模式提供快速模板，例如：
- [x] 群兜底
- [x] topic 精确绑定
- [x] DM 绑定

### 验收标准

- [x] 高频路径不再依赖全手输
- [x] 无效输入和格式错误明显下降

### 当前进展

- [x] `Profiles` 表单已接入 provider / model datalist，并直接复用实例配置中的 `models.providers.*` 与现有 agent 配置作为候选来源
- [x] `model` 字段现在会提示“Profile 里填 model id、默认主模型仍用 provider/model”的格式边界
- [x] `Bindings` 的 `channel` 已从自由文本切换为受控 `select`
- [x] `account_id` 现在会根据实例配置里的 `channels.*` 自动给出已有账号提示
- [x] `peer.id` 的 placeholder 与说明会按 `channel + peer.kind` 变化
- [x] 已新增三种常用模板：群组兜底、topic/thread 精确绑定、DM/direct 绑定

---

## Phase 5 / AG-05 规则校验增强

目的：把当前“能拦一部分错”提升到“能稳定拦住高风险配置问题”。

### 相关文件

- `ui/src/lib/components/InstanceAgentsPanel.svelte`
- `src/api/config.zig`
- 需要时：`/home/huspc/projects/nullclaw/src/agent_routing.zig`

### 待办

- [x] 细化重复 binding 检测，而不是只做粗粒度重复提示
- [x] 检测同优先级重叠规则
- [x] 检测悬空 `agent_id`
- [x] 检测潜在兜底规则遮蔽
- [x] 明确 bindings 扩展字段未来是否支持未知字段保留
- [x] 明确服务端是否需要返回结构化校验结果

### 验收标准

- [x] 重复、悬空、歧义 binding 能被稳定识别
- [x] 前后端校验口径一致

### 当前进展

- [x] 前端现在把“同 agent + 同 scope 重复”和“不同 agent 抢占同一精确 scope”区分成两个阻塞错误
- [x] 后端 `PUT /agents/bindings` 已与前端对齐：同 scope 冲突会直接拒绝保存
- [x] 服务端现在会按 trim 后再校验 `agent_id/channel/account_id/peer`，避免空白值绕过规则
- [x] account-scoped exact peer 与 any-account fallback、thread/topic 与群级 fallback 继续作为非阻塞提示保留在 UI
- [x] bindings 仍沿用 `replace_all` / `unknown_fields = replace_all`，本阶段只在文档里明确“当前不做未知字段保留”
- [x] contract v1 继续返回单个阻塞 `error_code`，尚未扩展为整批结构化校验结果列表

---

## Phase 6 / AG-06 路由预览与调试

目的：提供“配置完成后，实际会命中哪个 agent”的直观验证能力。

### 相关文件

- `ui/src/lib/components/InstanceAgentsPanel.svelte`
- `src/api/config.zig`
- 需要时新增调试 API

### 待办

- [x] 增加最小路由预览面板
- [x] 支持输入 `channel / account / peer / roles`
- [x] 展示命中的 `agent_id`
- [x] 展示命中依据，例如 `peer > guild > account > default`
- [x] 若无命中，展示回退到 `main/default` 的结果
- [x] 将实例摘要里的 `profiles / bindings` 计数与异常状态接入

### 验收标准

- [x] 用户无需真实发消息也能验证路由结果
- [x] 路由优先级和回退路径可解释

### 当前进展

- [x] `Bindings` 标签页已新增本地路由预览面板，直接基于当前草稿计算命中结果，无需真实发消息
- [x] 预览支持输入 `channel / account / peer / roles`，并明确提示 contract v1 仍只会评估 `channel/account/peer`
- [x] 预览结果会展示命中的 `agent_id`、命中的 binding 摘要、以及逐层命中路径
- [x] 线程消息会按 `精确 peer -> any-account peer -> 父 chat scoped -> 父 chat any-account -> main/default` 解释回退路径
- [x] 实例详情摘要里的 `Agent 路由` 卡现在会同时展示 `profiles / bindings` 计数和当前路由健康状态

---

## Phase 7 / AG-07 回归与文档

目的：把这条线从一次性开发收口成可长期维护的能力。

### 相关文件

- `tests/`
- `docs/instance-agent-management-design.md`
- `docs/nullhubx-nullclaw-integration-mapping.md`
- 本文档

### 待办

- [x] 增加 `profiles` GET/PUT roundtrip 回归
- [x] 增加 `bindings` GET/PUT roundtrip 回归
- [x] 增加冲突/悬空引用/格式错误回归
- [x] 增加 UI 冒烟：
- [x] 新增 profile
- [x] 新增 binding
- [x] `Save Profiles`
- [x] `Save Bindings`
- [x] `Save All`
- [x] 重启提示
- [x] 同步更新设计说明与操作文档
- [x] 在总计划文档中同步阶段状态

### 验收标准

- [x] 接口、UI、文档、回归脚本保持一致
- [x] 后续继续扩展 agent 管理时有明确落点和回归保护

### 当前进展

- [x] `tests/smoke_agents_api.py` 现已覆盖 `profiles/bindings` roundtrip、`defaults.model_primary` 格式校验、悬空 `agent_id`、重复 route、同 scope 冲突、空白字段与 topic/thread 规范化
- [x] `tests/agents_ui_smoke.cjs` 现已覆盖新增 profile、新增 binding、`Save Profiles`、`Save Bindings`、`Save All` 与路由预览
- [x] `tests/regression_core_flow.sh` 现会自动创建临时 HOME 和 `nullclaw/demo` fixture，避免依赖开发者本地现有实例
- [x] 已实际执行：`RUN_UI_SMOKE=1 bash tests/regression_core_flow.sh 19812` -> `15 passed / 0 failed / 0 skipped`

---

## 建议执行顺序

1. `AG-00`
2. `AG-01`
3. `AG-02`
4. `AG-03`
5. `AG-04`
6. `AG-05`
7. `AG-06`
8. `AG-07`

## 建议提交拆分

1. `AG-01`
2. `AG-02 + AG-03`
3. `AG-04 + AG-05`
4. `AG-06 + AG-07`
