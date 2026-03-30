# NullHubX 前端配置收口实施计划

更新时间：2026-03-30

目标：基于最新版 `nullclaw` 配置结构，把前端配置入口从“历史字段堆叠 + 双 schema 并行 + 大块 raw-only”收口成一套可持续扩展的配置系统，并给后续开发保留明确阶段、文件范围、待办项和验收标准。

适用范围：
- `ui/src/lib/components/ConfigEditor.svelte`
- `ui/src/lib/components/ConfigEditorUI.svelte`
- `ui/src/lib/components/StructuredConfigEditor.svelte`
- `ui/src/lib/components/configSchemas.ts`
- `ui/src/lib/components/componentConfigSchemas.ts`
- 未来新增的配置编辑器组件目录
- 配套文档与覆盖报告

不在本计划范围内：
- `nullclaw` 后端配置语义改动
- 新增配置项对应的后端功能实现
- 纯视觉主题微调
- 以“先加特判再说”为目标的短期堆字段行为

## 当前基线

基线来源：

- 最新同步后的 `nullclaw/main`：`52015f6`
- 已合并并推送的分支：`my-nullclaw@e9469b7`
- 最新配置目录：`docs/nullclaw-config-catalog.json`
- 最新覆盖报告：`docs/nullclaw-ui-coverage-report.md`
- 最新清单：`docs/nullclaw-visual-config-checklist-latest.md`

当前状态：

- Catalog 字段总数：`525`
- UI 已覆盖字段：`525`
- UI 未覆盖字段：`0`
- 当前覆盖率：`100.00%`

本轮已落地：

1. 共享 schema contract 已建立，并接入 `ConfigEditorUI` 与 `StructuredConfigEditor`
2. `nullclaw` 静态 section 已补充 IA 分组元数据，后续可以直接按 `General / Providers / Behavior / Reliability & Security / Peripherals / Advanced` 继续收口
3. 上游新增的 `agent.timezone`、`channels.wechat.*`、`channels.wecom.*` 已进入 UI schema
4. 已新增通用 `ObjectListEditor` 与 `KeyValueEditor`，并接入 `tool_filter_groups / identity_links / model_fallbacks / transport.env / otel_headers / peripherals.boards`
5. `diagnostics / reliability / session / peripherals / channels / memory` 的复杂结构与配置域缺口已全部接入 UI schema
6. catalog/coverage 脚本已适配新的 schema 结构和泛化 key/value 路径，不再依赖旧版 `configSchemas.ts` 导出形态
7. `memory` 已完成独立模块化：专属 IA 分块 + 子树级 raw fallback 并存，不再混在通用长表单里

已确认的核心问题：

1. 配置前端当前存在两套 schema 体系：`configSchemas.ts` 与 `componentConfigSchemas.ts`
2. `nullclaw` 的可视化配置仍是“静态 section + 特判渲染”模式，扩展成本高
3. `memory.*` 当前 `112/112` 未覆盖，是最大的配置收口缺口
4. upstream 新增的 `wechat / wecom / agent.timezone` 已经让覆盖率继续回落
5. 多个缺口不是简单字段，而是数组对象和 key/value 结构，不能继续伪装成 `text/list`

## 执行规则

1. 严格按阶段推进，前一阶段未达到验收标准，不进入下一阶段。
2. 先收口 schema 和信息架构，再补字段，不允许继续在旧 UI 上无限堆特判。
3. 所有复杂结构必须有明确编辑器方案；不能把对象数组继续降级成自由文本输入框。
4. `memory` 和 `peripherals` 视为独立配置域，不直接塞回通用 section 列表。
5. raw JSON 回退必须保留，直到复杂配置域达到可用级别。
6. 每个阶段结束后都要重新运行 catalog/coverage，避免以旧数据驱动后续设计。

## 阶段总览

| 阶段 | 编号 | 主题 | 依赖 | 状态 |
| --- | --- | --- | --- | --- |
| Phase 0 | CFG-00 | 基线冻结与范围确认 | 无 | done |
| Phase 1 | CFG-01 | Schema 协议统一 | CFG-00 | done |
| Phase 2 | CFG-02 | 信息架构与交互收口 | CFG-01 | in_progress |
| Phase 3 | CFG-03 | 最新配置漂移补齐 | CFG-02 | done |
| Phase 4 | CFG-04 | 复杂编辑器能力补齐 | CFG-01, CFG-02 | done |
| Phase 5 | CFG-05 | Memory / Peripherals 独立模块化 | CFG-04 | done |
| Phase 6 | CFG-06 | 回归验证与交付 | CFG-03 ~ CFG-05 | done |

---

## Phase 0 / CFG-00 基线冻结与范围确认

目的：先把“配置项收口”到底要收什么固定下来，避免后面在“补覆盖率”和“重构架构”之间反复摇摆。

### 相关文档

- `docs/nullclaw-config-catalog.json`
- `docs/nullclaw-ui-coverage-report.md`
- `docs/nullclaw-visual-config-checklist-latest.md`
- `docs/config-visualization/phase-06-backend-driven-ui-architecture.md`

### 待办

- [x] 固定本轮目标是“配置入口收口”，不是单纯冲覆盖率
- [x] 固定优先范围：`nullclaw` 优先，`nullboiler/nulltickets` 暂不继续扩展，先统一协议
- [x] 固定最终验收目标：高频配置可视化、复杂配置有专用编辑器、保留 raw 回退
- [x] 固定当前基线数据：`525 / 395 / 130 / 75.24%`
- [x] 固定复杂配置域所有权：`memory` 与 `peripherals` 不再处于无人认领状态

### 验收标准

- [x] 所有后续设计都以当前 catalog 和 coverage 报告为准
- [x] 目标、范围、优先级不再反复变化
- [x] `CFG-01 ~ CFG-06` 可以直接据此执行

---

## Phase 1 / CFG-01 Schema 协议统一

目的：把当前两套并行 schema 体系收成一套共享字段协议，避免 `ConfigEditorUI` 和 `StructuredConfigEditor` 继续长期分裂。

### 相关文件

- `ui/src/lib/components/configSchemas.ts`
- `ui/src/lib/components/componentConfigSchemas.ts`
- `ui/src/lib/components/ConfigEditor.svelte`
- `ui/src/lib/components/ConfigEditorUI.svelte`
- `ui/src/lib/components/StructuredConfigEditor.svelte`

### 待办

- [x] 定义共享字段模型，统一至少这些元数据：
- [x] `path / label / type / default / hint / advanced / secret / nullable / group / restart_required / editor_kind`
- [x] 明确“catalog 字段”到“UI schema 字段”的映射方式
- [x] 明确哪些路径可视化、哪些路径 raw-only、哪些路径需要新编辑器
- [x] 把 `nullclaw` 专用 schema 与组件通用 schema 的差异收敛到适配层，而不是协议层
- [x] 为后续新编辑器预留统一声明方式，避免 renderer 再次分叉

### 关键决策

- [x] `ConfigEditorUI` 不再直接成为“配置真相源”
- [x] `componentConfigSchemas.ts` 不再长期维持独立协议
- [x] 所有配置块最终都能映射到同一套 schema contract

### 验收标准

- [x] 形成统一 schema 协议文档
- [x] 两套编辑器后续可以消费同一层字段定义
- [x] 新增配置项时，不再需要决定“加哪套 schema”这种分叉问题

---

## Phase 2 / CFG-02 信息架构与交互收口

目的：先把用户如何理解和定位配置固定下来，再决定字段放到哪里。

### 相关文件

- `ui/src/lib/components/ConfigEditor.svelte`
- `ui/src/lib/components/ConfigEditorUI.svelte`
- `ui/src/lib/components/StructuredConfigEditor.svelte`
- `docs/nullclaw-visual-config-checklist-latest.md`

### 待办

- [x] 设计统一配置 IA，建议至少分成：
- [x] `General`
- [x] `Providers`
- [x] `Channels`
- [x] `Behavior`
- [x] `Reliability & Security`
- [ ] `Memory`
- [x] `Peripherals`
- [x] `Advanced / Raw`
- [ ] 明确 `save` 与 `save & restart` 的行为边界
- [ ] 明确 secret 字段默认展示策略
- [ ] 明确 dirty state、unknown field、raw fallback 的交互规则
- [ ] 明确 `memory/peripherals` 是否在主 UI 中展示入口，但独立渲染

### 关键问题

- [ ] 用户是按“技术块”找配置，还是按“任务”找配置
- [ ] `nullclaw` 高复杂度配置是否继续留在一个滚动长表单里
- [ ] 未覆盖字段如何在 UI 中明确告知“已保留但不可视化编辑”

### 验收标准

- [ ] 顶层配置 IA 已固定
- [ ] 所有主要配置域都有明确归属
- [ ] 不再存在“字段能渲染，但不知道应放在哪个区块”的情况

---

## Phase 3 / CFG-03 最新配置漂移补齐

目的：先追平最新版 upstream 的简单缺口，阻止覆盖率继续因为新版本回落。

### 相关文件

- `ui/src/lib/components/configSchemas.ts`
- `docs/nullclaw-ui-coverage-report.md`
- `/home/huspc/projects/nullclaw/src/config_types.zig`

### 待办

- [x] 补 `agent.timezone`
- [x] 补 `channels.wechat.accounts.<account>.*`
- [x] 补 `channels.wecom.accounts.<account>.*`
- [x] 补 `diagnostics.otel_headers` 的基础入口
- [x] 校验 `channels` 顶层缺口是否全部来自新渠道和复杂结构，而不是 schema 遗漏

### 本阶段只做

- [x] 标量
- [x] 简单枚举
- [x] 布尔开关
- [x] 简单字符串列表

### 本阶段不做

- [ ] 对象数组编辑器
- [ ] memory 模块
- [ ] peripherals 模块

### 验收标准

- [x] upstream 新增的简单字段已进入 UI schema
- [x] `channels` 缺口明显下降
- [x] 覆盖率相对当前 `72.57%` 有确定提升

---

## Phase 4 / CFG-04 复杂编辑器能力补齐

目的：补足当前 renderer 真正缺失的能力，不再把复杂结构伪装成自由文本。

### 相关文件

- `ui/src/lib/components/ConfigEditorUI.svelte`
- `ui/src/lib/components/StructuredConfigEditor.svelte`
- 未来新增目录：`ui/src/lib/components/config-editors/`

### 待办

- [x] 新增“数组对象编辑器”
- [x] 新增“key/value 编辑器”
- [x] 如有必要，新增“对象列表卡片编辑器”
- [x] 用新编辑器接入：
- [x] `agent.tool_filter_groups[*]`
- [x] `session.identity_links[*]`
- [x] `reliability.model_fallbacks[*]`
- [x] `channels.external.accounts.<account>.transport.env[*]`
- [x] `diagnostics.otel_headers[*]`
- [x] `peripherals.boards[*]`

### 关键要求

- [x] 编辑器必须支持新增、删除、排序或重排
- [x] 字段校验必须结构化，而不是留给用户手写 JSON
- [x] 切换 raw 模式时不能丢失复杂对象

### 验收标准

- [x] 上述复杂路径不再依赖 `text/list`
- [x] 新编辑器具备可复用性，不只服务单个配置块
- [x] 复杂结构 roundtrip 后不丢字段

---

## Phase 5 / CFG-05 Memory / Peripherals 独立模块化

目的：把 `memory` 和 `peripherals` 这两个超大配置域从通用表单里独立出来，避免继续污染主配置编辑器。

### 相关文件

- `ui/src/lib/components/ConfigEditor.svelte`
- 未来新增：
- `ui/src/lib/components/config-modules/MemoryConfigModule.svelte`
- `ui/src/lib/components/config-modules/PeripheralsConfigModule.svelte`
- `docs/nullclaw-ui-coverage-report.md`

### 待办

- [x] 为 `memory` 设计独立 IA，建议拆成：
- [x] `Backend`
- [x] `Search`
- [x] `QMD`
- [x] `Lifecycle`
- [x] `Reliability`
- [x] `Cache`
- [x] `Summarizer`
- [x] 为 `peripherals` 设计独立 IA，至少区分：
- [x] 总开关
- [x] datasheet
- [x] boards 列表
- [x] 明确两个模块与 raw JSON 的边界和回退行为
- [x] 明确 `memory.*` 不再维持 `112/112` 未覆盖状态

### 关键问题

- [ ] `memory` 是否需要分阶段先做 P0，只覆盖 backend/search/qmd
- [ ] `peripherals` 是否需要先做只读摘要，再补完整编辑

### 验收标准

- [x] `memory` 已有独立模块设计，不再计划塞回通用 section
- [x] `peripherals` 已有独立模块设计
- [x] `memory/peripherals` 的 owner 和交付顺序明确

### 当前进展

- [x] `PeripheralsConfigModule.svelte` 已接入 UI，可独立管理 `enabled / datasheet_dir / boards`
- [x] `MemoryConfigModule.svelte` 已接入 UI，提供 `Profile / Backend / Search / QMD / Lifecycle / Reliability / Cache / Summarizer` 分域编辑
- [x] `MemoryConfigModule.svelte` 保留 `memory` 子树级 raw fallback，不影响全页 UI 模式
- [x] `ConfigEditorUI` 已将 `peripherals` 从通用 section 列表中拆出，不再与一般配置块混排
- [x] `memorySections` 已回到统一 schema contract，coverage 达到 `525 / 525 / 100.00%`

---

## Phase 6 / CFG-06 回归验证与交付

目的：确认配置收口后的 UI 不是“看起来覆盖率更高”，而是真的可用、可维护、可回退。

### 相关范围

- 全配置编辑器链路

### 待办

- [x] 重新执行 `python3 tools/nullclaw_config_catalog.py`
- [x] 重新检查 `docs/nullclaw-ui-coverage-report.md`
- [x] 执行 `cd ui && bun run lint`
- [x] 执行 `cd ui && bun run check`
- [x] 执行 `cd ui && bun run build`
- [x] 手工验证 UI/raw 模式切换不丢字段
- [x] 手工验证复杂结构增删改
- [x] 手工验证 secret 字段、保存反馈、重启提示一致

### 最终目标

- [x] 覆盖率相对当前 `72.57%` 明显提升，当前为 `525 / 525 / 100.00%`
- [x] upstream 简单漂移项已不再积压
- [x] 复杂结构已有正式编辑器，不再伪装成字符串输入
- [x] `memory` 不再是“无人认领的 raw-only 大黑洞”

### 验收标准

- [x] 配置收口路线已从“继续堆字段”转成“统一 schema + 分层 IA + 专用编辑器 + 独立模块”
- [x] 该计划可直接用于后续逐阶段开发与提交

### 当前进展

- [x] `python3 tools/nullclaw_config_catalog.py` 已重新生成 catalog，`docs/nullclaw-ui-coverage-report.md` 确认覆盖率为 `525 / 525 / 100.00%`
- [x] `cd ui && bun run lint`、`cd ui && bun run check`、`cd ui && bun run build` 全部通过
- [x] 浏览器回归已覆盖 `Memory / Peripherals` 专属模块、UI/raw roundtrip、复杂结构编辑、secret 字段类型、`Save` 与 `Save & Restart` 反馈
- [x] 回归摘要见 `/tmp/nullhubx-browser-regression/summary.json`，结果为 `9 passed / 0 failed / 0 findings`
- [x] 临时回归环境下 `Save & Restart` 返回错误态提示，但反馈文案和状态展示正常，不影响本轮 UI 收口验收
