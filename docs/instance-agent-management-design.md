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

它不等于某条 binding，而是实例内 agent 的默认模型偏好。

### 3.3 Agent Binding

Binding 表示“某类消息/渠道/会话路由到哪个 agent”。

当前结构：

- `agent_id`
- `match.channel`
- `match.account_id`
- `match.peer.kind`
- `match.peer.id`

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

### 10.2 没有“有效路由视图”

当前用户只能看到绑定列表，看不到“最终哪些 channel/account/peer 会命中哪个 agent”的汇总视图。

### 10.3 没有“保存后是否建议重启”的明确提示

当前保存成功不等于运行态一定立刻生效，但 UI 还没有按变更类型给出明确提示。

### 10.4 没有跨实例模板能力

如果多个实例要复用同一组 agent profile，目前只能手工复制配置。

---

## 11. 后续演进建议

建议按优先级推进：

### P0

- 明确哪些 agent 相关配置变更需要提示重启
- 在实例详情摘要中展示 `profiles / bindings` 数量与最近变更状态
- 为 bindings 增加更明确的重复/覆盖提示

### P1

- 增加“有效路由预览”或“匹配结果摘要”
- 为常见 channel 提供更结构化的 peer 输入辅助
- 为 profile 增加 provider/model 候选输入

### P2

- 设计可选的 profile 模板导入/导出
- 评估 bindings 是否也需要未知字段合并策略
- 评估是否需要 agent 配置变更的差异预览

---

## 12. 结论

当前最正确的定位是：

“实例级 Agent 管理 = 实例配置系统中的一个专门切面，用来管理 `agents.list`、`agents.defaults.model.primary` 和顶层 `bindings`，而不是新的独立资源系统。”

只要坚持这个边界，后续无论是 UI 收口、API 稳定化还是与 NullClaw 的配置演进对齐，复杂度都会可控。
