# 实例级 Agent 管理设计说明

## 1. 目标

这套能力的目标不是做一个全局 Agent 平台，而是把 “某个实例内部有哪些 agent、它们如何接管不同渠道/会话” 收口成稳定的实例级配置能力。

核心目标：

- 保持“实例是一等资源”不变
- Agent 管理只依附于实例，不引入新的全局持久化格式
- UI 提供可视化编辑与基础防错
- 底层仍然只读写实例 `config.json`
- 高级用户仍可回退到完整配置编辑

非目标：

- 不做跨实例共享的 agent 注册中心
- 不做独立于实例配置之外的 agent 运行态数据库
- 不把 agent 管理扩展成通用编排系统

---

## 2. 当前架构事实

当前实现已经具备实例级 Agent 管理闭环：

- UI 入口：实例详情页 `Agents` tab
- 前端面板：`ui/src/lib/components/InstanceAgentsPanel.svelte`
- API：`GET/PUT /api/instances/{component}/{name}/agents/profiles`
- API：`GET/PUT /api/instances/{component}/{name}/agents/bindings`
- 持久化：实例目录下的 `config.json`
- 契约版本：`agent_contract_version = 1`

这意味着 Agent 管理本质上是“实例配置管理的一个专门切面”，不是额外的资源系统。

---

## 3. 资源边界

### 3.1 Instance

实例是唯一的所有权边界，键为：

- `component`
- `name`

实例负责承载：

- 运行配置
- agent profiles
- binding 路由规则
- workspace / logs / state

同一个 `nullclaw` 组件的不同实例，agent 配置彼此独立，不共享。

### 3.2 Agent Profile

Profile 表示“这个实例里可被选中的 agent 身份/能力描述”。

当前标准字段：

- `id`
- `provider`
- `model`
- `system_prompt`
- `temperature`
- `max_depth`

同时存在一个实例级默认模型：

- `defaults.model_primary`

字段策略：

- `profiles` 的标准字段只覆盖上述字段
- 对同一 `profile.id` 的未知字段，保存时保留
- 因此 `profiles` 的写入语义是“替换标准字段 + 保留未知扩展字段”

它不等于某条 binding，而是实例内 agent 的默认模型偏好。

### 3.3 Agent Binding

Binding 表示“某类消息/渠道/会话路由到哪个 agent”。

当前结构：

- `agent_id`
- `match.channel`
- `match.account_id`
- `match.peer.kind`
- `match.peer.id`

字段策略：

- `bindings` 当前标准字段只覆盖上述路由最小集
- `bindings` 仍为整体替换，不保留未知字段
- 因此它比 `profiles` 更刚性，扩展时需要明确兼容策略

也就是说，binding 是从“外部输入上下文”到“实例内 agent profile”的映射。

---

## 4. 配置映射

实例级 Agent 管理与实例配置的映射关系如下：

### 4.1 Profiles

- `defaults.model_primary` <-> `agents.defaults.model.primary`
- `profiles[].id` <-> `agents.list[].id`
- `profiles[].provider` <-> `agents.list[].provider`
- `profiles[].model` <-> `agents.list[].model`
- `profiles[].system_prompt` <-> `agents.list[].system_prompt`
- `profiles[].temperature` <-> `agents.list[].temperature`
- `profiles[].max_depth` <-> `agents.list[].max_depth`

### 4.2 Bindings

- `bindings[]` <-> 实例配置顶层 `bindings[]`

### 4.3 存储位置

所有数据最终都写回：

- `~/.nullhubx/instances/{component}/{name}/config.json`

因此这套设计天然继承了实例配置的回滚、备份、迁移方式。

---

## 5. 交互模型

### 5.1 页面结构

实例详情页的 `Agents` tab 内部再分两块：

- `Profiles`
- `Bindings`

这个分层是必要的，因为两者有明显依赖方向：

1. 先定义可用的 profile
2. 再让 binding 引用 profile

### 5.2 保存方式

当前 UI 支持三种保存动作：

- `Save Profiles`
- `Save Bindings`
- `Save All`

设计意图：

- profile 编辑可以单独落盘
- binding 编辑可以单独落盘
- 同时修改时允许整页提交

### 5.3 Dirty State

前端分别维护两套 dirty state：

- `profilesDirty`
- `bindingsDirty`

这样用户能清楚知道：

- 哪一部分改过
- 哪一部分还能单独保存
- `Save All` 到底会提交什么

### 5.4 防错规则

前端当前已经做的防错：

- profile id 唯一性提示
- provider/model 必填
- `max_depth` 范围校验
- binding 必须引用现有 profile
- 若 binding 引用了“尚未持久化”的 profile，阻止保存 binding
- 同一组 `channel/account/peer` 精确 scope 只能出现一条 binding
- account-scoped exact peer 与 any-account fallback、thread/topic 与群级 fallback 的覆盖关系只做提示，不作为阻塞错误

这套规则保证了“先配 profile，再配 route”的工作流不会被破坏。

---

## 6. API 设计

### 6.1 Profiles API

读取：

- `GET /api/instances/{component}/{name}/agents/profiles`

写入：

- `PUT /api/instances/{component}/{name}/agents/profiles`

语义：

- 幂等
- 整体替换标准字段
- 以 `profile.id` 为锚点保留旧条目中的未知字段
- 读取响应返回：
  - `contract_version`
  - `resource`
  - `ownership`
  - `field_policy`

这一点很重要。它允许：

- UI 只编辑标准字段
- 旧配置中的扩展字段不因 UI 保存而丢失

### 6.2 Bindings API

读取：

- `GET /api/instances/{component}/{name}/agents/bindings`

写入：

- `PUT /api/instances/{component}/{name}/agents/bindings`

语义：

- 幂等
- 整体替换
- 当前不做未知字段语义合并
- 读取响应返回：
  - `contract_version`
  - `resource`
  - `ownership`
  - `field_policy`
- 校验失败时当前仍返回单个阻塞错误：
  - `status = "validation_failed"`
  - `error_code`
  - `error`

这意味着 bindings 目前比 profiles 更“刚性”，后续如果 bindings 结构继续扩展，可能需要补语义合并策略。

### 6.3 为什么不用单个 item API

当前不设计：

- `POST /profiles`
- `PATCH /profiles/{id}`
- `DELETE /bindings/{id}`

原因很直接：

- 底层存储仍是一个 JSON 文件
- 当前前端是整页编辑器，而不是表格型资源管理台
- 整体 PUT 更容易保证一致性和幂等

### 6.4 保存结果语义

当前 `PUT` 成功响应已经补充了结构化语义：

- `status = "saved"`：只表示配置文件保存成功
- `apply_state = "config_saved"`：表示实例配置已落盘
- `runtime_effect = "component_defined"`：是否立即影响运行态，由具体组件决定，当前端点不直接承诺
- `unknown_fields`：显式说明当前资源的未知字段策略

因此这两个端点当前表达的是“配置契约层面的成功”，不是“运行态已经热生效”。

### 6.5 UI 保存反馈语义

前端现在按两层信息反馈 agent 保存结果：

1. `配置层结果`

- 直接展示 `apply_state`
- 直接展示 `runtime_effect`
- 明确这表示“实例配置已写回”，不是“运行态已经热生效”

2. `实例运行态建议`

- 若实例 `stopped`：提示“已保存，将在下次启动时生效”
- 若实例 `failed`：提示“已保存，建议通过重启重新应用”
- 若实例正在运行或切换状态：提示“已保存，但若要立即且确定地应用，建议重启”

同时，保存成功后前端会主动刷新实例摘要中的：

- profile 数量
- binding 数量
- 运行状态卡片

因此实例详情页现在会把“配置已保存”和“实例可能仍在运行旧配置”明确拆开，而不是混成一条“保存成功”提示。

---

## 7. 服务端一致性规则

服务端应继续坚持以下约束：

### 7.1 Profiles

- `id` 必填且实例内唯一
- `provider` 必填
- `model` 必填
- `max_depth` 必须在 `1..8`
- `defaults.model_primary` 若存在，必须满足 `provider/model`

### 7.2 Bindings

- `agent_id` 必须引用现有 profile
- `main` / `default` 允许作为保留值
- `match.channel` 必填
- `match.peer.kind` 必填
- `match.peer.id` 必填
- legacy topic id 在写入前规范成 `:thread:` 格式

### 7.3 写入一致性

必须保持“读 -> 改 -> 一次性写回”的模式：

1. 读取实例 `config.json`
2. 修改 `agents.defaults.model.primary` / `agents.list` / 顶层 `bindings`
3. 一次性写回

这样可以避免部分字段写入成功、部分失败的半完成状态。

### 7.4 错误响应语义

当前 agent 端点的校验失败与找不到配置，都会返回结构化错误：

- `status`
- `error_code`
- `error`
- `resource`
- `contract_version`

约定：

- `validation_failed`：请求体或字段校验失败
- `not_found`：实例配置不存在
- `apply_state = "unchanged"`：表示本次失败没有落盘任何 agent 配置改动

---

## 8. 运行态边界

这是当前设计里最容易被误解的地方。

实例级 Agent 管理当前管理的是：

- 配置
- 路由
- 默认模型

它当前不直接管理：

- agent 进程生命周期
- agent 运行中会话
- agent 的热更新编排

也就是说，保存 `Profiles/Bindings` 本质上只是修改实例配置。是否立即生效，取决于：

- NullClaw 对相关配置是否支持热加载
- 或是否需要实例重启/刷新运行态

从控制面设计上，应该把它视为“配置变更”，而不是“运行态调度命令”。

---

## 9. 推荐的用户工作流

建议前端和文档都围绕这个顺序组织：

1. 在实例详情页打开 `Agents`
2. 在 `Profiles` 中定义默认模型和各个 agent profile
3. 先保存 `Profiles`
4. 切到 `Bindings`，将 channel/account/peer 路由到指定 agent
5. 保存 `Bindings`
6. 如涉及运行态敏感项，再由用户决定是否重启实例

这个顺序符合当前数据依赖，也最容易解释。

---

## 10. 当前已知边界与风险

### 10.1 Profiles 与 Bindings 的合并能力不对称

- profiles：已支持保留未知字段
- bindings：仍为整体替换

这会导致 bindings 扩展时更脆弱。

### 10.2 只有“最小有效路由视图”

当前已经有本地路由预览，可以直接验证 `channel/account/peer` 在 contract v1 下会命中哪个 agent，也会解释回退到 `main/default` 的路径。

但它仍有明确边界：

- 仍不覆盖 guild / team / roles 维度
- 仍基于前端本地求值，而不是统一的后端调试 API
- 只能解释当前 contract v1 的优先级，不等于未来完整路由引擎的全部视图

### 10.3 运行态提示仍是实例级，而不是字段级

当前 UI 已经能区分“已保存、下次启动生效”和“建议重启以立即应用”，但提示粒度仍是实例级：

- 还没有细分到“哪一类 agent 字段一定需要重启”
- 还没有把 NullClaw 未来可能支持的热加载能力映射到具体字段
- 当前仍以 `apply_state / runtime_effect + 实例运行状态` 为主做提示

### 10.4 没有跨实例模板能力

如果多个实例要复用同一组 agent profile，目前只能手工复制配置。

---

## 11. 回归与文档基线

当前这条能力已经有固定的回归与文档落点：

- `tests/smoke_agents_api.py`
  - 覆盖 `profiles / bindings` GET/PUT roundtrip
  - 覆盖 `defaults.model_primary` 格式错误
  - 覆盖悬空 `agent_id`
  - 覆盖重复 route、同 scope 冲突、空白字段
  - 覆盖 legacy topic id -> `:thread:` 规范化
- `tests/agents_ui_smoke.cjs`
  - 覆盖新增 profile / binding
  - 覆盖 `Save Profiles` / `Save Bindings` / `Save All`
  - 覆盖路由预览命中
- `tests/regression_core_flow.sh`
  - 统一拉起临时 `HOME`
  - 自动创建 `nullclaw/demo` fixture
  - 可用 `RUN_UI_SMOKE=1` 打开浏览器烟测
- `docs/regression-checklist.md`
  - 固化执行方式、前置条件与判定标准

这意味着后续继续扩 agent 管理时，不应该再只补实现，还要同步补到这 3 类回归资产和对应文档。

---

## 12. 后续演进建议

建议按优先级推进：

### P0

- 明确哪些 agent 相关配置变更需要提示重启
- 在实例详情摘要中继续扩展 agent 相关最近变更状态
- 为 bindings 增加更完整的调试和诊断输出

### P1

- 将当前本地路由预览提升为统一调试能力或 API
- 为常见 channel 提供更结构化的 peer 输入辅助
- 为 profile 增加 provider/model 候选输入

### P2

- 设计可选的 profile 模板导入/导出
- 评估 bindings 是否也需要未知字段合并策略
- 评估是否需要 agent 配置变更的差异预览

---

## 13. 结论

当前最正确的定位是：

“实例级 Agent 管理 = 实例配置系统中的一个专门切面，用来管理 `agents.list`、`agents.defaults.model.primary` 和顶层 `bindings`，而不是新的独立资源系统。”

只要坚持这个边界，后续无论是 UI 收口、API 稳定化还是与 NullClaw 的配置演进对齐，复杂度都会可控。
