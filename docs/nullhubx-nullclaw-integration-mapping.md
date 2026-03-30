# NullHubX × NullClaw 集成映射（代码真相版）

> 范围与假设
> - 以当前仓库代码为真相源，不按 README 声明推断能力。
> - 文档语言中文，命令/字段保留英文原名。
> - 目标是支持后续重构拆分、回归测试与接口稳定性治理。

## 1. 总览架构

NullHubX 在这个定制场景中是“控制面/管理面”，NullClaw 是“运行面/执行面”。

核心调用链：

1. UI 调用 `nullhubx` HTTP API（`/api/instances/...` 等）。
2. `nullhubx` 在实例层做三类动作：
- 进程控制：`manager.startInstance/stopInstance`。
- 文件控制：读写实例 `config.json`、`workspace`、`logs`、`state`。
- CLI 桥接：通过 `runWithComponentHome` 调 `nullclaw` 子命令（`history`/`memory`/`skills` 等）。
3. `nullclaw` 提供 machine-facing 协议命令用于安装与探测：
- `--export-manifest`
- `--from-json`
- `--probe-provider-health`
4. 结果回流给 NullHubX API，再回流到 UI。

关键源码锚点：
- NullHubX 路由分发：`src/server.zig`（`/api/instances/...` 分支）
- NullHubX 实例动作：`src/api/instances.zig`
- NullClaw 顶层命令：`/home/huspc/projects/nullclaw/src/main.zig:169`
- NullClaw manifest/向导协议：
  - `/home/huspc/projects/nullclaw/src/export_manifest.zig:54`
  - `/home/huspc/projects/nullclaw/src/from_json.zig:1`

## 2. 10 条关键链路

1. 安装向导链路
- `nullhubx` wizard 安装流触发组件安装编排，调用 `nullclaw --from-json` 生成配置并写入托管实例目录。
- 关键：`src/installer/orchestrator.zig`，`/home/huspc/projects/nullclaw/src/from_json.zig:408`

2. 启动链路（start）
- `POST /api/instances/{c}/{n}/start` -> 读取 manifest/配置端口 -> `manager.startInstance`。
- 关键：`src/api/instances.zig:1486`

3. 停止链路（stop）
- `POST /api/instances/{c}/{n}/stop` -> `manager.stopInstance`。
- 关键：`src/api/instances.zig:1570`

4. 重启链路（restart）
- `POST /api/instances/{c}/{n}/restart` -> stop 后复用 start。
- 关键：`src/api/instances.zig:1577`

5. Provider 健康探测链路
- `GET /provider-health` -> 解析实例配置 -> `--probe-provider-health`。
- 关键：`src/api/instances.zig:1585`，`/home/huspc/projects/nullclaw/src/main.zig:177`

6. 历史查询链路
- `GET /history` -> 桥接 `nullclaw history list/show --json`。
- 关键：`src/api/instances.zig:1915`，`/home/huspc/projects/nullclaw/src/main.zig:1528`

7. Memory 查询链路
- `GET /memory` -> 桥接 `nullclaw memory stats|get|search|list --json`。
- 关键：`src/api/instances.zig:1978`，`/home/huspc/projects/nullclaw/src/main.zig:948`

8. Skills 管理链路
- `GET/POST/DELETE /skills` -> bundled 技能安装 + `nullclaw skills` CLI 桥接。
- 关键：`src/api/instances.zig:2052`、`2197`、`2256`，`/home/huspc/projects/nullclaw/src/main.zig:682`

9. Onboarding 状态链路
- `GET /onboarding` -> 读取 `workspace` + `.nullclaw/workspace-state.json`，必要时回退到 `memory get __bootstrap.prompt.BOOTSTRAP.md`。
- 关键：`src/api/instances.zig:1948`、`139`、`146`

10. 集成/导入/更新链路
- integration：`/integration` 负责 nullboiler/nulltickets 联动配置改写与工作流文件同步。
- import：`POST /api/instances/{component}/import` 将 standalone 目录接入托管。
- update：`POST /api/instances/{c}/{n}/update` 运行时更新入口。
- 关键：`src/api/instances.zig:2462`、`2593`、`2360`；`src/api/updates.zig:130`

## 3. API ↔ NullClaw 命令映射矩阵

| # | NullHubX 入口路由 | 下游命令/协议 | 关键参数映射 | 关键配置键 | 主要失败模式 | 源码依据（NullHubX / NullClaw） |
|---|---|---|---|---|---|---|
| 1 | `POST /api/instances/{c}/{n}/start` / `stop` / `restart` | start/stop 直接进程管理；start 会读 manifest 并启动 binary | `launch_mode`、`verbose`，端口从 manifest + config 推导 | `health.port_from_config`（常见 `gateway.port`） | binary 缺失、配置端口不可读、启动失败 | `src/api/instances.zig:1486`、`1570`、`1577` / `/home/huspc/projects/nullclaw/src/export_manifest.zig:55` |
| 2 | `GET/PUT/PATCH /api/instances/{c}/{n}/config` | 文件读写（非 CLI） | `resolve=true` 控制引用解析，PUT/PATCH 写回完整 JSON | `config.json` 根对象（providers/channels/gateway 等） | JSON 非法、路径不存在、写入失败 | `src/api/config.zig` / `/home/huspc/projects/nullclaw/src/config.zig:129` |
| 3 | `GET /api/instances/{c}/{n}/provider-health` | `nullclaw --probe-provider-health` | provider/model 从实例 config 解析后传入 probe 参数 | `models.providers.*`、`agents.defaults.model.primary` | provider 未检测、实例未运行、CLI 执行失败 | `src/api/instances.zig:1585` / `/home/huspc/projects/nullclaw/src/main.zig:177` |
| 4 | `GET /api/instances/{c}/{n}/history` | `nullclaw history list/show --limit --offset --json` | `session_id` 决定 `list` 或 `show`，带分页 | memory backend 可用性影响 history 能力 | backend 不支持、session store 不可用、CLI 非 JSON | `src/api/instances.zig:1915` / `/home/huspc/projects/nullclaw/src/main.zig:1528`、`/home/huspc/projects/nullclaw/docs/zh/commands.md:113` |
| 5 | `GET /api/instances/{c}/{n}/memory` | `nullclaw memory stats/get/search/list --json` | `stats/key/query/category/limit` 到子命令参数映射 | memory backend 与 category | CLI 执行失败、参数非法、非 JSON 输出 | `src/api/instances.zig:1978` / `/home/huspc/projects/nullclaw/src/main.zig:948`、`/home/huspc/projects/nullclaw/docs/zh/commands.md:122` |
| 6 | `GET/POST/DELETE /api/instances/{c}/{n}/skills` | `nullclaw skills list/info/install/remove`（部分 bundled 走本地安装） | `catalog`、`name`、`bundled`、`clawhub_slug`、`source` | `workspace/skills`，必要时回写运行时配置 | `clawhub` 不存在、技能不存在、CLI 失败 | `src/api/instances.zig:2052`、`2197`、`2256` / `/home/huspc/projects/nullclaw/src/main.zig:682`、`/home/huspc/projects/nullclaw/docs/zh/commands.md:104` |
| 7 | `GET /api/instances/{c}/{n}/onboarding` | 文件状态 + 回退 `nullclaw memory get` | `__bootstrap.prompt.BOOTSTRAP.md` 作为回退 key | `workspace/BOOTSTRAP.md`、`.nullclaw/workspace-state.json` | 状态文件缺失、CLI 不支持 memory get、解析失败 | `src/api/instances.zig:1948`、`139`、`146` / `/home/huspc/projects/nullclaw/src/main.zig:1310`（memory get 分支） |
| 8 | `GET/POST /api/instances/{c}/{n}/integration` | 本地 HTTP + 本地配置改写（nullboiler/nulltickets） | `tracker_instance`、`pipeline_id`、`claim_role`、`success_trigger` | nullboiler `tracker.*`、workflow 文件 | 目标实例不存在、pipeline 校验失败、配置写入失败 | `src/api/instances.zig:2462`、`2593` /（该链路主要是 NullHubX 内部编排，无直接 NullClaw 命令依赖） |
| 9 | `POST /api/instances/{component}/import` | 将 standalone 目录接入托管（符号链接 + state 注册） | `component` -> `default` 实例导入 | `~/.nullclaw` 与 `~/.nullhubx/instances/...` 映射 | standalone 目录不存在、链接创建失败、state 保存失败 | `src/api/instances.zig:2360` / `/home/huspc/projects/nullclaw/src/config.zig:276`（默认 `~/.nullclaw/config.json`） |
| 10 | `POST /api/instances/{c}/{n}/update` | 运行时更新流程（下载/替换/回滚） | 组件名、实例名、版本解析 | binary 路径与实例 state 版本 | 无可用更新、下载失败、应用更新失败 | `src/api/updates.zig:130`、`src/server.zig:1040` / `/home/huspc/projects/nullclaw/src/main.zig:75`（`update` 命令存在） |

说明：
- 表中第 8 行（integration）是 NullHubX 侧强编排能力，非 NullClaw CLI 直连路径。
- 表中第 10 行（update）当前由 NullHubX 运行时更新逻辑主导，NullClaw 顶层也有 `update` 命令但不是这条 API 的直接下游。

## 4. 配置/路径映射

### 4.1 配置键映射（高频）

| 语义 | NullHubX 侧读取/写入点 | NullClaw 对应键/协议 |
|---|---|---|
| 网关端口 | 启动时从实例 `config.json` + manifest 推导 | `gateway.port`（manifest 的 `health.port_from_config` 指向该键） |
| 启动探活 | 读取组件 manifest `health.endpoint` | `--export-manifest` 导出的 `health.endpoint` |
| Provider 探测 | 从实例配置读取 provider/model + key | `models.providers.*`，`agents.defaults.model.primary` |
| 历史能力 | history API 仅桥接，不自行解释历史格式 | `nullclaw history list/show --json` 输出契约 |
| memory 能力 | memory API 仅桥接，不自行解释业务语义 | `nullclaw memory stats/get/search/list --json` |
| skills 能力 | 部分 bundled 管理 + CLI 桥接 | `nullclaw skills list/info/install/remove` |
| onboarding 状态 | 文件态 + memory 回退探测 | `workspace/BOOTSTRAP.md` + `memory get __bootstrap.prompt.BOOTSTRAP.md` |

### 4.2 文件路径映射

NullHubX 路径规范（`Paths`）：
- root: `~/.nullhubx`
- state: `~/.nullhubx/state.json`
- binary: `~/.nullhubx/bin/{component}-{version}`
- instance dir: `~/.nullhubx/instances/{component}/{name}`
- instance config: `~/.nullhubx/instances/{component}/{name}/config.json`
- instance data/logs: `.../data`、`.../logs`

源码依据：`src/core/paths.zig:33`、`51`、`65`、`74`、`79`、`84`、`89`

NullClaw 默认路径规范：
- config: `~/.nullclaw/config.json`
- workspace: `~/.nullclaw/workspace`

源码依据：`/home/huspc/projects/nullclaw/src/config.zig:276`

### 4.3 托管/导入边界

1. 托管安装（wizard/install）
- NullHubX 在 `~/.nullhubx/instances/...` 下维护隔离实例目录。
- `--from-json` 可通过 `home` 参数把 NullClaw 配置/工作区定向到实例目录。

2. standalone 导入（import）
- `POST /api/instances/{component}/import` 将 `~/.nullclaw`（或 `~/.{component}`）通过符号链接接入 `~/.nullhubx/instances/{component}/default`。
- 该模式保留原数据位置，NullHubX 增加 state 与生命周期托管。

源码依据：`src/api/instances.zig:2360`，`/home/huspc/projects/nullclaw/src/from_json.zig:20`

## 5. 风险与优先级

### P0（强耦合/易漂移）

1. CLI JSON 契约耦合
- NullHubX 的 history/memory/skills/provider-health 依赖 NullClaw CLI 输出 JSON；一旦输出结构变化，管理面即失效。
- 证据：`runInstanceCliJson` 依赖 `isLikelyJsonPayload` 与命令桥接。

2. 子命令参数契约耦合
- NullHubX 固定拼接 `history list/show`、`memory search/list/get/stats`、`skills list/info/install/remove` 参数。
- NullClaw 参数若调整，NullHubX 无编译期保障。

3. machine-facing 协议兼容性风险
- `--export-manifest` 与 `--from-json` 是安装链路核心协议，字段变更影响安装成功率与端口/健康检查推导。

### P1（可维护性热点）

1. `src/api/instances.zig` 超大（4000+ 行）
- 生命周期、CLI 桥接、integration、onboarding、usage cache 聚集在单文件，测试与回归成本高。

2. 运行时动作分层不清
- 部分逻辑走 manager，部分走 CLI，部分直读写文件；出现问题时定位链路长。

3. integration 特殊逻辑复杂
- nullboiler/nulltickets 的耦合策略在实例 API 文件内，扩展新组件时复用成本高。

### P2（体验与文档一致性）

1. README 与 CLI 完整性存在认知落差
- README 命令列表较完整，CLI 已补齐 install/start/stop/restart/config/check-updates/update 的 API 对接，但仍有部分命令未落地（如 start-all/stop-all/update-all/logs/wizard/add-source）。

2. API 能力与 CLI 能力不对称
- 实际可用能力更多在 HTTP API，非 `nullhubx` 顶层 CLI。

## 6. 阶段进展（2026-03-17）

已落地（CLI -> API）：
- `install <component>` -> `POST /api/wizard/{component}`（支持 `--name --version --provider --api-key --model --memory --build-from-source`）
- `start|stop|restart <component>/<name>` -> `POST /api/instances/{c}/{n}/{action}`
- `config <component>/<name>` -> `GET /api/instances/{c}/{n}/config`（`--edit` 暂仅提示并回退到只读输出）
- `check-updates` -> `GET /api/updates`
- `update <component>/<name>` -> `POST /api/instances/{c}/{n}/update`

仍待落地（顶层 CLI）：
- `start-all`
- `stop-all`
- `update-all`
- `logs`（当前仍是占位输出）
- `wizard`
- `add-source`

## 7. Phase 1 API 契约草案（实例内 Agent 管理）

实现状态（2026-03-17）：
- 后端首版已落地到 `src/api/config.zig`、`src/server.zig`、`src/api/meta.zig`。
- 当前已支持 `GET/PUT /api/instances/{component}/{name}/agents/profiles` 与 `GET/PUT /api/instances/{component}/{name}/agents/bindings`。
- 已实现基础校验：profile 唯一性、`defaults.model_primary` 格式、binding 的 `agent_id` 引用校验、legacy topic id 规范化。
- profiles 已支持“保留未知字段并覆盖标准字段”的合并写入（按 id 匹配旧条目）；bindings 仍为整体替换。

目标：
- 保持“实例是一等资源”不变。
- 新增 Agent 管理 API，但底层仍只读写实例 `config.json`。
- 不引入新的持久化文件格式，降低回滚风险。

### 7.1 Profiles API

1. `GET /api/instances/{component}/{name}/agents/profiles`
- 用途：读取实例内 agent profiles（对应 `agents.list`）与默认模型（`agents.defaults.model.primary`）。
- 响应示例：

```json
{
  "defaults": {
    "model_primary": "openrouter/anthropic/claude-sonnet-4"
  },
  "profiles": [
    {
      "id": "orchestrator",
      "provider": "openrouter",
      "model": "anthropic/claude-sonnet-4",
      "system_prompt": "Coordinate tasks and delegate to specialists.",
      "temperature": 0.7,
      "max_depth": 3
    },
    {
      "id": "coder",
      "provider": "openrouter",
      "model": "qwen/qwen3-coder",
      "system_prompt": "Focus on implementation and tests.",
      "temperature": 0.3,
      "max_depth": 2
    }
  ]
}
```

2. `PUT /api/instances/{component}/{name}/agents/profiles`
- 用途：整体替换 profiles（幂等，便于前端整页提交）。
- 标准字段白名单：`id`、`provider`、`model`、`system_prompt`、`temperature`、`max_depth`
- 默认模型字段白名单：`defaults.model_primary`
- 未知字段策略：按 `profile.id` 保留旧条目中的未知字段
- 请求体示例：

```json
{
  "defaults": {
    "model_primary": "openrouter/anthropic/claude-sonnet-4"
  },
  "profiles": [
    {
      "id": "orchestrator",
      "provider": "openrouter",
      "model": "anthropic/claude-sonnet-4",
      "system_prompt": "Coordinate tasks and delegate to specialists.",
      "temperature": 0.7,
      "max_depth": 3
    }
  ]
}
```

- 成功响应：

```json
{
  "contract_version": 1,
  "resource": "agent_profiles",
  "status": "saved",
  "apply_state": "config_saved",
  "runtime_effect": "component_defined",
  "unknown_fields": "preserve_by_id",
  "profiles_count": 1
}
```

### 7.2 Bindings API

1. `GET /api/instances/{component}/{name}/agents/bindings`
- 用途：读取实例内 routing 规则（对应顶层 `bindings`）。
- 响应示例：

```json
{
  "bindings": [
    {
      "agent_id": "coder",
      "match": {
        "channel": "telegram",
        "account_id": "main",
        "peer": { "kind": "group", "id": "-1001234567890:thread:42" }
      }
    },
    {
      "agent_id": "orchestrator",
      "match": {
        "channel": "telegram",
        "account_id": "main",
        "peer": { "kind": "group", "id": "-1001234567890" }
      }
    }
  ]
}
```

2. `PUT /api/instances/{component}/{name}/agents/bindings`
- 用途：整体替换 bindings（幂等）。
- 标准字段白名单：`agent_id`、`match.channel`、`match.account_id`、`match.peer.kind`、`match.peer.id`
- 未知字段策略：整体替换，不保留未知字段
- 请求体示例：

```json
{
  "bindings": [
    {
      "agent_id": "coder",
      "match": {
        "channel": "telegram",
        "account_id": "main",
        "peer": { "kind": "group", "id": "-1001234567890:thread:42" }
      }
    }
  ]
}
```

- 成功响应：

```json
{
  "contract_version": 1,
  "resource": "agent_bindings",
  "status": "saved",
  "apply_state": "config_saved",
  "runtime_effect": "component_defined",
  "unknown_fields": "replace_all",
  "bindings_count": 1
}
```

### 7.3 校验规则（服务端）

1. profiles 校验：
- `id` 必填且在实例内唯一。
- `provider`、`model` 必填。
- `max_depth >= 1`，建议上限 `8`（防止递归链失控）。
- 若设置 `defaults.model_primary`，必须满足 `provider/model` 格式。

2. bindings 校验：
- `agent_id` 必须存在于 `profiles.id`（或允许保留值 `main/default`，按 NullClaw 行为）。
- `match.channel` 必填，`match.peer.kind/id` 必填；空白值会在服务端按 trim 后判空。
- 同一组 `channel/account/peer` 精确 scope 只能对应一条 binding；同 agent 重复写入会报 `binding_route_duplicate`，不同 agent 抢占同 scope 会报 `binding_scope_conflict`。
- peer id 如使用 topic，统一规范为 `:thread:` 形式。

3. 原子写入：
- 读实例 `config.json` -> 修改 `agents.list` / `agents.defaults.model.primary` / 顶层 `bindings` -> 一次性写回。
- 写入失败返回 `500`，不更新任何部分字段。

4. 响应语义：
- `status = "saved"` 只表示配置已保存，不承诺运行态已经热生效。
- `apply_state = "config_saved"` 表示本次变更已落盘。
- `runtime_effect = "component_defined"` 表示运行态是否立即应用由组件决定。
- 校验失败响应包含单个阻塞 `error_code`，前端不必再依赖纯文本错误猜测类型；当前 contract v1 仍不返回整批结构化校验列表。

### 7.4 与 NullClaw 配置映射

1. `GET/PUT .../agents/profiles`
- `defaults.model_primary` <-> `agents.defaults.model.primary`
- `profiles[].id` <-> `agents.list[].id`（兼容 `name`）
- `profiles[].provider/model/system_prompt/temperature/max_depth` <-> `agents.list[]` 同名字段

2. `GET/PUT .../agents/bindings`
- `bindings` <-> 顶层 `bindings`

3. 兼容策略：
- profiles PUT 会保留未知字段（按 id 匹配旧条目）；bindings 仍不做语义合并。
- 仍允许高级用户通过现有 `PUT /config` 手工编辑完整配置。

### 验收检查（对应本次文档目标）

- [x] 至少 10 条链路可从入口追溯到源码落点。
- [x] 矩阵每行包含 NullHubX 与 NullClaw 依据（integration 行已明确说明主要为 NullHubX 内部编排）。
- [x] 文档可直接用于后续拆分任务：可按矩阵逐行生成回归用例与契约测试。
