# NullHubX 前端视觉改造实施清单

日期：2026-03-30

基线文档：
- `docs/frontend-visual-rules.md`
- `docs/config-visualization/phase-06-backend-driven-ui-architecture.md`

## 目标

把 `Industrial Console x Soft Cyberpunk` 主题从规则文档落地为前端实现，并保持：

1. 不破坏既有信息架构
2. 不混入业务逻辑改造
3. 分阶段可验证、可回滚

## 阶段总览

| 阶段 | 编号 | 主题 | 目标 | 状态 |
| --- | --- | --- | --- | --- |
| Phase V0 | V-00 | 视觉基线冻结 | 固化主题、字体、命名和 Tab 规则 | done |
| Phase V1 | V-01 | 全局 Token 与字体基础设施 | 重建颜色、字体、阴影、背景和兼容 token | done |
| Phase V2 | V-02 | 全局壳层改造 | TopBar / StatusBar / ToastContainer 切入新主题 | done |
| Phase V3 | V-03 | 基础组件收口 | 卡片、按钮、表单、状态徽标统一 | done |
| Phase V4 | V-04 | 一般页面主题化 | Dashboard / Resources / Settings / Hub 收口 | done |
| Phase V5 | V-05 | 工作区与详情页强化 | Instances 与实例详情成为主题中心 | done |
| Phase V6 | V-06 | 编排与动态模块专项 | Orchestration / Logs / Chat 强化未来感 | done |
| Phase V7 | V-07 | 回归与交付 | lint/check/build 与手工视觉回归 | done |

## Phase V0 / V-00 视觉基线冻结

相关文档：

- `docs/frontend-visual-rules.md`
- `docs/phase-task-plan.md`

待办：

- [x] 正式主题固定为 `Industrial Console x Soft Cyberpunk`
- [x] 字体优先级固定为 `IBM Plex Sans SC / IBM Plex Sans / IBM Plex Mono`
- [x] 固定主强调色角色：`cyan` 主、`violet` 辅、`rose/red` 危险
- [x] 固定 Tab 放置规则：一级导航顶部、实例详情顶部、复杂子分组必要时侧边
- [x] 固定中文字体策略，禁止依赖英文显示字体承担中文正文

验收标准：

- [x] 视觉方向和字体策略已写成正式文档
- [x] 后续实现不再需要重复讨论主题基线

## Phase V1 / V-01 全局 Token 与字体基础设施

相关文件：

- `ui/src/app.css`
- `ui/src/app.html`

待办：

- [x] 重建全局字体变量和默认字体栈
- [x] 把标题系统从 `mono` 收回到中文可用的 `sans`
- [x] 重建深色背景、面板层、边框层和语义色 token
- [x] 明确 `cyan / violet / rose-red` 的角色分工
- [x] 建立发光、阴影、focus ring 的统一规则
- [x] 保留旧 token 的兼容映射，避免现有页面立刻失真
- [x] 收紧滚动条、选中态、body 背景纹理

验收标准：

- [x] 所有页面已经继承新的字体和颜色基线
- [x] 组件内无需再新增随意 hex 颜色来达成主题效果
- [x] 当前前端仍可正常构建

## Phase V2 / V-02 全局壳层改造

相关文件：

- `ui/src/routes/+layout.svelte`
- `ui/src/lib/components/TopBar.svelte`
- `ui/src/lib/components/StatusBar.svelte`
- `ui/src/lib/components/ToastContainer.svelte`

待办：

- [x] TopBar 改成深色控制台风格
- [x] 收口导航激活态、hover、连接状态点和语言切换器
- [x] StatusBar 改成更克制的信息条
- [x] ToastContainer 接入统一深色面板和语义状态色
- [x] 调整壳层边距、层级和背景分层

验收标准：

- [x] 首页、实例页、设置页切换时壳层观感一致
- [x] TopBar / StatusBar / Toast 的语言风格与新主题一致
- [x] 不引入新的导航层级混乱

## Phase V3 / V-03 基础组件收口

相关文件：

- `ui/src/lib/components/InstanceCard.svelte`
- `ui/src/lib/components/ComponentCard.svelte`
- `ui/src/lib/components/StatusBadge.svelte`
- `ui/src/lib/components/ConfigEditor.svelte`
- `ui/src/lib/components/ConfigEditorUI.svelte`
- `ui/src/lib/components/StructuredConfigEditor.svelte`

待办：

- [x] 统一卡片边框、圆角、hover 和阴影
- [x] 统一主按钮、次按钮、危险按钮
- [x] 统一状态徽标样式和语义映射
- [x] 统一表单控件高度、背景、边框和错误样式
- [x] 统一空状态与错误 banner

验收标准：

- [x] 不再出现每个组件自带一套按钮与卡片系统
- [x] `mono` 只出现在技术信息位

## Phase V4 / V-04 一般页面主题化

相关文件：

- `ui/src/routes/+page.svelte`
- `ui/src/routes/connections/+page.svelte`
- `ui/src/routes/settings/+page.svelte`
- `ui/src/routes/hub/+page.svelte`

待办：

- [x] Dashboard 的统计卡和入口卡切换到新主题
- [x] Resources 表格与统计头收口
- [x] Settings 表单区块层次重建
- [x] Hub 页面保留安装入口感，但压低营销页气质

验收标准：

- [x] 阅读型页面统一进入新主题
- [x] 赛博感存在，但不影响阅读和表单操作

## Phase V5 / V-05 工作区与详情页强化

相关文件：

- `ui/src/routes/instances/+page.svelte`
- `ui/src/routes/instances/[component]/[name]/+page.svelte`
- `ui/src/lib/components/InstanceAgentsPanel.svelte`
- `ui/src/lib/components/LogViewer.svelte`
- `ui/src/lib/components/InstanceHistoryPanel.svelte`
- `ui/src/lib/components/InstanceMemoryPanel.svelte`
- `ui/src/lib/components/InstanceSkillsPanel.svelte`

待办：

- [x] 实例列表页左侧筛选栏和中区网格统一成控制台结构
- [x] 实例详情头部、摘要卡、操作按钮和顶部 Tab 收口
- [x] `Logs / Agents` 强化未来感
- [x] `Config / History / Memory` 保持克制和高可读性
- [x] 评估并补齐实例快速预览抽屉

实施结果：

- [x] `Instances` 列表页新增右侧快速预览面板，统一左侧筛选、中区卡片网格与右侧摘要的控制台工作区结构
- [x] 实例详情页统一为 hero + summary + top tabs 的主工作区布局，按钮层级收口到主/次/危险三层
- [x] `LogViewer` 与 `InstanceAgentsPanel` 切到深色未来感面板；`History / Memory / Skills` 保持亮面板高可读性

验收标准：

- [x] `Instances` 成为全站视觉中心
- [x] 实例详情页顶部 Tab 不需要改成侧边

## Phase V6 / V-06 编排与动态模块专项

相关文件：

- `ui/src/routes/orchestration/+page.svelte`
- `ui/src/lib/components/ChatPanel.svelte`
- `ui/src/lib/components/ModuleFrame.svelte`
- `ui/src/lib/components/orchestration/*`

待办：

- [x] 编排页强化节点、状态和时间线视觉
- [x] Chat 与动态模块容器接入主主题边框和背景
- [x] 模块失败态、等待态、未安装态统一
- [x] 限制局部发光，避免模块脱离主应用体系

实施结果：

- [x] 编排页改为深色 hero + 图谱预览 + 运行时间线 + 工作流库的控制平面结构
- [x] `ChatPanel` 与 `ModuleFrame` 建立统一的模块容器头部、状态徽标和不可用态表现
- [x] `GraphViewer / RunEventLog / StateInspector / WorkflowJsonEditor / InterruptPanel / CheckpointTimeline` 切入同一套暗色未来感面板
- [x] 局部辉光仅保留在图谱节点、状态点和关键交互上，未扩散到全部卡片

验收标准：

- [x] 编排和日志页面拥有更强未来感
- [x] 与主应用其余页面仍保持同一产品气质

## Phase V7 / V-07 回归与交付

相关范围：

- 全前端

待办：

- [x] 执行 `cd ui && bun run lint`
- [x] 执行 `cd ui && bun run check`
- [x] 执行 `cd ui && bun run build`
- [x] 手工检查桌面与移动端断点
- [x] 手工检查中文字体回退和中英混排
- [x] 手工检查导航、Tab、表单、表格、空状态、错误态统一性

回归结果：

- [x] 已执行桌面与移动端 Playwright 回归，产出截图与摘要
- [x] 三条前端命令均恢复为通过状态
- [x] 已清理实例详情页 `instanceDetail.*` 原始 key、Agents 页 en-US 残留中文、ConfigEditorUI en-US 下“渠道”文案
- [x] 最新一轮回归结果为 `22 passed / 0 failed / 0 findings`
- [x] 回归摘要与截图产物位于 `/tmp/nullhubx-browser-regression/summary.json` 与 `/tmp/nullhubx-browser-regression/`

验收标准：

- [x] 三条命令全绿
- [x] 没有新的导航层级混乱
- [x] 没有中文字体断层或过强发光导致的可读性问题

## 建议提交拆分

1. 提交 1：`V-01 + V-02`
2. 提交 2：`V-03 + V-04`
3. 提交 3：`V-05`
4. 提交 4：`V-06 + V-07`
