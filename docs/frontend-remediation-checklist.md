# NullHubX 前端修复任务清单

更新时间：2026-03-29

目标：把本轮前端 review 发现的问题整理成可持续执行的修复文档，按阶段推进，并为后续开发保留明确的文件范围、待办项、验收标准和验证命令。

适用范围：
- `ui/` 下前端代码、构建配置、lint/check 规则
- `.github/workflows/` 中与前端构建直接相关的配置
- 少量配套文档修订

不在本清单范围内：
- 当前工作区中其它未提交的业务功能开发
- 后端 API 语义变更
- 纯视觉重设计

## 当前基线

执行 review 时的现状：

- `bun run lint`：失败
- `bun run check`：失败
- `bun run build`：通过

已确认的主要问题：

1. 导航和首页入口链接指向了不存在的 `/resources`
2. 底层 API 客户端默认 toast，后台轮询失败会反复打扰用户
3. `LogViewer` 的 SSE 与 fallback polling 存在并发风险
4. ESLint / typed lint / svelte-check 门禁本身失效
5. i18n 迁移不完整，仍存在大量硬编码中文和双语混杂

## 执行规则

1. 严格按阶段顺序推进，前一阶段未达到验收标准，不进入下一阶段。
2. 每个阶段单独提交，避免把不相关 WIP 混入修复提交。
3. 修复规则问题时，不降低质量门槛来绕过错误；优先修配置，其次修代码。
4. 页面级提示和全局 toast 的职责必须拆开，不允许同一错误同时出现多份 UI 反馈。
5. 所有阶段都应以 `bun run lint`、`bun run check`、`bun run build` 作为最终门禁。

## 阶段总览

| 阶段 | 编号 | 主题 | 依赖 | 状态 |
| --- | --- | --- | --- | --- |
| Phase 0 | FE-00 | 隔离修复范围 | 无 | in_progress |
| Phase 1 | FE-01 | 恢复 lint / check 门禁 | FE-00 | done |
| Phase 2 | FE-02 | 修正路由与导航回归 | FE-01 | done |
| Phase 3 | FE-03 | 重构错误处理职责 | FE-01 | done |
| Phase 4 | FE-04 | 稳定 SSE 日志链路 | FE-03 | done |
| Phase 5 | FE-05 | 补齐 i18n 与文案一致性 | FE-02 | in_progress |
| Phase 6 | FE-06 | 类型与风格收口 | FE-01, FE-05 | in_progress |
| Phase 7 | FE-07 | 回归验证与交付 | FE-02 ~ FE-06 | todo |

---

## Phase 0 / FE-00 隔离修复范围

目的：把“前端修复”与当前其它前端功能开发拆开，保证修复任务可以独立推进和提交。

### 相关文件

- `ui/src/lib/api/client.ts`
- `ui/src/lib/statusStore.ts`
- `ui/src/lib/sseClient.ts`
- `ui/src/lib/toastStore.svelte.ts`
- `ui/src/lib/components/ToastContainer.svelte`
- `ui/src/lib/components/TopBar.svelte`
- `ui/src/routes/+layout.svelte`
- `ui/src/routes/+layout.ts`
- `ui/src/routes/+page.svelte`
- `ui/src/routes/connections/+page.svelte`
- `ui/src/routes/settings/+page.svelte`
- `ui/src/routes/instances/[component]/[name]/+page.svelte`
- `ui/src/lib/i18n/en-US.ts`
- `ui/src/lib/i18n/zh-CN.ts`
- `ui/.eslintrc.json`
- `ui/tsconfig.json`

### 待办

- [ ] 确认本次修复提交不混入当前工作区中与 toast / i18n / routing 无关的业务功能
- [ ] 记录需要保留的现有 WIP 文件，避免误修或误提交
- [ ] 确定本轮修复使用独立提交策略

### 验收标准

- [ ] 可以清晰区分“修复文件”和“其它正在开发文件”
- [ ] 本清单内每一阶段都能单独形成提交

---

## Phase 1 / FE-01 恢复 lint / check 门禁

目的：先把自动化质量门禁修回可用状态，否则后续修复无法靠工具验证。

### 相关文件

- `ui/.eslintrc.json`
- `ui/tsconfig.json`
- `ui/package.json`
- `ui/src/routes/instances/[component]/[name]/+page.svelte`
- `ui/src/routes/settings/+page.svelte`
- `ui/src/lib/components/TopBar.svelte`

### 待办

- [ ] 移除或替换 `ui/.eslintrc.json` 中无效的 `svelte/require-event-dispatcher` 规则
- [ ] 修复 typed lint 的 TSConfig 包含范围问题
- [ ] 如有必要，新增 `ui/tsconfig.eslint.json` 专供 ESLint 使用
- [ ] 修复 `svelte-check` 已知错误
- [ ] 清理明确的未使用导入 / 未使用状态 / 错误事件签名
- [ ] 确认 `lint` 与 `check` 不依赖手工预生成文件才能运行

### 重点检查项

- [ ] `ui/src/routes/instances/[component]/[name]/+page.svelte` 中 `onclick={loadSummary}` 的类型错误
- [ ] `ui/src/routes/settings/+page.svelte` 中未使用的 `serviceAction`
- [ ] `ui/src/lib/components/TopBar.svelte` 中未使用的 `onDestroy`

### 验收标准

- [ ] `bun run lint` 通过
- [ ] `bun run check` 通过
- [ ] `bun run build` 仍然通过
- [ ] 不通过“关闭规则”来掩盖实际类型错误

### 验证命令

```bash
cd ui
bun run lint
bun run check
bun run build
```

---

## Phase 2 / FE-02 修正路由与导航回归

目的：修复当前已经存在的前端死链和入口路径不一致问题。

### 相关文件

- `ui/src/lib/components/TopBar.svelte`
- `ui/src/routes/+page.svelte`
- `ui/src/routes/connections/+page.svelte`
- `ui/src/routes/+layout.ts`

### 待办

- [ ] 把所有错误的 `/resources` 链接统一改为实际存在的 `/connections`
- [ ] 校对 `TopBar`、首页入口卡片、空状态跳转是否一致
- [ ] 检查 `+layout.ts` 中“无实例跳转 `/hub`”逻辑是否仍符合当前产品预期
- [ ] 补一轮手工点击验证，确认不存在 404 或错误激活态

### 明确问题点

- [ ] `ui/src/lib/components/TopBar.svelte`
- [ ] `ui/src/routes/+page.svelte`

### 验收标准

- [ ] 顶栏“资源/Resources”进入正确页面
- [ ] 首页资源入口卡片进入正确页面
- [ ] 当前路径高亮与实际路由一致
- [ ] 不存在导航点击后跳到 404 的情况

### 手工验证

- [ ] `/`
- [ ] `/instances`
- [ ] `/connections`
- [ ] `/orchestration`
- [ ] `/settings`

---

## Phase 3 / FE-03 重构错误处理职责

目的：消除“底层 API 客户端直接驱动 UI 提示”带来的全局副作用。

### 相关文件

- `ui/src/lib/api/client.ts`
- `ui/src/lib/api/errorMessages.ts`
- `ui/src/lib/statusStore.ts`
- `ui/src/routes/settings/+page.svelte`
- `ui/src/routes/connections/+page.svelte`
- `ui/src/routes/instances/[component]/[name]/+page.svelte`
- `ui/src/lib/toastStore.svelte.ts`
- `ui/src/lib/components/ToastContainer.svelte`

### 待办

- [ ] 为 `request()` 设计显式错误展示策略
- [ ] 区分静默请求、交互式请求、调用方自定义处理三类场景
- [ ] 让后台轮询类请求默认不触发 toast
- [ ] 页面级操作保留显式 toast 或内联错误，但避免重复提示
- [ ] 统一网络错误 / 超时错误文案来源，避免硬编码
- [ ] 审核 settings / connections / instance detail 的错误展示是否与全局 toast 冲突

### 重点检查项

- [ ] `ui/src/lib/api/client.ts` 中 timeout / fetch error / HTTP error 的 toast 逻辑
- [ ] `ui/src/lib/statusStore.ts` 中状态轮询调用 `api.getStatus()` 的交互方式
- [ ] 页面内已有 `message` / `error-banner` 的地方，避免再额外弹重复 toast

### 验收标准

- [ ] 后端短暂不可用时，不会每轮轮询都弹一次 toast
- [ ] 用户主动点击的失败操作仍然能收到明确反馈
- [ ] 同一错误不会同时出现 banner + toast +局部 message 三份提示

### 手工验证

- [ ] 启动后端正常时刷新页面
- [ ] 临时关闭后端，观察总览页 / 设置页 / 实例页的错误反馈
- [ ] 恢复后端后再次操作，确认页面状态恢复正常

---

## Phase 4 / FE-04 稳定 SSE 日志链路

目的：把日志实时流和 fallback polling 收敛成单一、可推理的状态机。

### 相关文件

- `ui/src/lib/components/LogViewer.svelte`
- `ui/src/lib/sseClient.ts`
- `ui/src/lib/api/client.ts`

### 待办

- [ ] 梳理 `LogViewer` 当前连接状态机
- [ ] 显式管理 SSE 连接、重连、超时和 fallback polling 的切换
- [ ] 确保任意时刻只有一种日志获取通路处于激活状态
- [ ] 成功建立 SSE 连接后，显式停止 fallback polling
- [ ] 组件卸载时，保证不会因 `onClose` 或定时器回调重新拉起 polling
- [ ] source 切换和实例切换时，确保旧连接彻底清理
- [ ] 复核 `SseClient` 中 `console.error` 与错误上报策略是否符合现有规范

### 重点检查项

- [ ] `LogViewer.svelte` 中 3 秒 fallback 定时器
- [ ] `LogViewer.svelte` 中 `onError` / `onClose` / `end` 分支
- [ ] `SseClient.close()` 后是否还会触发重连或 polling

### 验收标准

- [ ] SSE 正常时，不存在额外 polling 请求
- [ ] SSE 失败时，能自动回落到 polling
- [ ] SSE 恢复后，polling 会被停止
- [ ] 切换日志来源或离开页面后，不会残留多余请求

### 手工验证

- [ ] 正常进入实例日志页
- [ ] 切换 `instance` / `nullhubx` 日志源
- [ ] 模拟后端重启或 SSE 中断
- [ ] 页面跳转离开日志页

---

## Phase 5 / FE-05 补齐 i18n 与文案一致性

目的：消除混合语言界面，统一前端文案来源。

### 当前进展

- [x] 已收口 `connections`、`settings`、实例详情主页面、`ToastContainer` 的硬编码文案
- [x] 已收口 `InstanceHistoryPanel`、`InstanceMemoryPanel`、`InstanceSkillsPanel`、`ComponentCard`、Hub 安装页主框架的主要可见文案
- [x] 已统一 `resources / connections` 路径命名，避免导航与页面文案漂移
- [ ] 剩余硬编码文案主要集中在 `InstanceAgentsPanel.svelte`、`ConfigEditorUI.svelte`
- [ ] 语言切换器自身的中英显示文案仍需统一检查

### 相关文件

- `ui/src/lib/i18n/en-US.ts`
- `ui/src/lib/i18n/zh-CN.ts`
- `ui/src/lib/i18n/index.svelte.ts`
- `ui/src/routes/connections/+page.svelte`
- `ui/src/routes/settings/+page.svelte`
- `ui/src/routes/instances/[component]/[name]/+page.svelte`
- `ui/src/lib/components/ToastContainer.svelte`
- `ui/src/lib/components/TopBar.svelte`
- `ui/src/routes/+page.svelte`

### 待办

- [ ] 把剩余硬编码中文文案迁移到 i18n 字典
- [ ] 补齐表格表头、按钮、错误提示、确认框、aria-label 等遗漏文案
- [ ] 统一 `dashboard / overview`、`resources / connections` 等命名
- [ ] 清理只翻译了一半的页面，避免标题已翻译但表格仍是中文
- [ ] 确认 locale 切换后 API 错误消息模板同步更新

### 重点检查页

- [ ] 总览页 `/`
- [ ] 资源页 `/connections`
- [ ] 设置页 `/settings`
- [ ] 实例详情页 `/instances/[component]/[name]`
- [ ] Toast 关闭按钮和状态文案

### 验收标准

- [ ] `zh-CN` 下无明显英文漏出
- [ ] `en-US` 下无明显中文漏出
- [ ] 导航、页面标题、按钮和错误提示命名统一
- [ ] aria-label 与可见文本语言一致

### 手工验证

- [ ] 切换到 `zh-CN`
- [ ] 切换到 `en-US`
- [ ] 刷新页面后 locale 持久化仍生效

---

## Phase 6 / FE-06 类型与风格收口

目的：收紧新增基础设施和新页面逻辑里的类型边界，减少 `any` 扩散和风格漂移。

### 当前进展

- [x] `ui/src/lib/api/client.ts` 已新增共享响应类型，覆盖 `instances / history / logs / wizard / service / agents`
- [x] `ui/src/lib/statusStore.ts`、`ui/src/lib/sseClient.ts` 已去除新增路径上的核心 `any`
- [x] `bun run check` 已恢复通过
- [x] `bun run build` 已恢复通过
- [x] `bun run lint` 仍通过，warning 已从 149 降到 101
- [ ] 剩余 `any` 主要集中在 `api/orchestration.ts`、`ChannelList.svelte`、`ProviderList.svelte`、`ConfigEditorUI.svelte`、`InstanceAgentsPanel` 与编排相关组件

### 相关文件

- `ui/src/lib/api/client.ts`
- `ui/src/lib/statusStore.ts`
- `ui/src/lib/sseClient.ts`
- `ui/src/routes/+layout.ts`
- `ui/src/routes/connections/+page.svelte`
- `ui/src/routes/settings/+page.svelte`
- `ui/src/routes/+page.svelte`

### 待办

- [ ] 为状态、资源列表、SSE 事件等新增共享接口，替代明显的 `any`
- [ ] 收紧 `Record<string, any>` 的使用范围，优先替换新增部分
- [ ] 删除明确无用的状态、导入、分支和重复逻辑
- [ ] 统一页面内 loading / error / empty 状态写法
- [ ] 审核是否有不必要的 `console.error`、重复 message、重复格式化逻辑

### 重点检查项

- [ ] `ui/src/lib/api/client.ts` 的 `AnyRecord`
- [ ] `ui/src/lib/statusStore.ts` 的 `pendingRequest: Promise<any>`
- [ ] `ui/src/lib/sseClient.ts` 的 `data: any`
- [ ] `ui/src/routes/+layout.ts` 的 `hasAnyInstances(payload: any)`

### 验收标准

- [ ] 新增代码中的 `any` 使用面积明显下降
- [ ] 明确无用状态和未使用导入被清理
- [ ] 类型收紧后，`bun run check` 仍然通过

---

## Phase 7 / FE-07 回归验证与交付

目的：把上述修复收口成可交付状态，并形成稳定的回归流程。

### 相关文件

- `ui/` 全量前端代码
- 必要时补充到 `docs/` 的执行记录

### 待办

- [ ] 执行最终静态检查
- [ ] 执行最终构建
- [ ] 执行关键路径手工回归
- [ ] 记录本轮修复结果和剩余风险
- [ ] 如需要，补充一份简短的交接说明

### 自动化验收

- [ ] `bun run lint`
- [ ] `bun run check`
- [ ] `bun run build`

### 手工回归清单

- [ ] 顶栏导航点击正常
- [ ] 首页入口卡片跳转正常
- [ ] 语言切换与持久化正常
- [ ] 设置页保存、服务状态刷新、启停操作正常
- [ ] 实例详情空状态、删除确认、启动参数弹窗正常
- [ ] 日志页 SSE 正常连接
- [ ] 日志页弱网或后端中断时 fallback 正常
- [ ] 后端离线时无重复 toast 轰炸

### 交付标准

- [ ] 三条自动化命令全部通过
- [ ] 不存在已知死链
- [ ] 不存在双语混杂的核心页面
- [ ] 不存在明显的重复错误提示
- [ ] 日志流链路行为稳定

---

## 建议提交拆分

建议按下面 3 个提交推进，避免单个提交过大：

1. `fix(ui): restore lint gates and repair broken routes`
- 包含：Phase 1 + Phase 2

2. `fix(ui): separate request errors from global toasts`
- 包含：Phase 3 + Phase 4

3. `refactor(ui): finish i18n cleanup and frontend regression pass`
- 包含：Phase 5 + Phase 6 + Phase 7

## 备注

1. 本文档是执行清单，不是设计稿。
2. 每完成一个阶段，应同步更新对应阶段状态和执行结果。
3. 若修复过程中发现后端接口行为与前端假设不一致，应新增小节记录，而不是直接覆盖原问题定义。
