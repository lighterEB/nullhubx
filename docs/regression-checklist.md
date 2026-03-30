# NullHubX 核心链路回归清单

目标：在一次执行中覆盖健康检查、状态、组件、设置、更新、实例配置、日志与 agents profiles/bindings 核心链路。

当前回归脚本会自动创建一个临时 HOME，并预置 `nullclaw/demo` fixture，因此不再依赖开发机上已有实例。

## 一键回归（推荐）

```bash
./tests/regression_core_flow.sh
```

可选：自定义端口（默认 `19812`）：

```bash
./tests/regression_core_flow.sh 19820
```

## 覆盖范围

脚本会自动完成：

1. `zig build` 构建
2. 启动 `nullhubx serve --port <PORT>`（使用临时 HOME）
3. 基础 API 回归
- `GET /health`
- `GET /api/status`（校验版本号与二进制一致）
- `GET /api/components`
- `POST /api/components/refresh`
- `GET /api/instances`
- `GET /api/settings`
- `GET /api/updates`
- `GET /api/service/status`
- `GET /api/nonexistent`（404 分支）
4. 实例链路回归（脚本会自动预置实例）
- `GET /api/instances/{c}/{n}/config`
- `GET /api/instances/{c}/{n}/logs`
- 运行 `tests/smoke_agents_api.py`（profiles/bindings roundtrip + 冲突/格式错误分支 + topic id 规范化）
- 可选：运行 `tests/agents_ui_smoke.cjs`（新增 profile/binding、`Save Profiles`、`Save Bindings`、`Save All`、路由预览）

## 前置条件

1. 本机具备 `zig`、`curl`、`python3`
2. 如需覆盖 UI 烟测，需具备 `npx`，并能取得 Playwright 与 Chromium

## 可选：启用 Agents UI 烟测

在一键回归里启用：

```bash
RUN_UI_SMOKE=1 ./tests/regression_core_flow.sh
```

单独执行：

```bash
NPM_CONFIG_CACHE=/tmp/npm-cache PLAYWRIGHT_BROWSERS_PATH=/tmp/pw-browsers \
NPM_CONFIG_CACHE=/tmp/npm-cache PLAYWRIGHT_BROWSERS_PATH=/tmp/pw-browsers \
npx -y -p playwright@1.52.0 node tests/agents_ui_smoke.cjs http://127.0.0.1:19812
```

## 结果判定

- `FAILED > 0`：脚本返回非 0，视为回归失败
- 若脚本自身创建的临时 fixture 失败，实例链路会一并失败，不再依赖开发机已有实例
- 未设置 `RUN_UI_SMOKE=1` 时，浏览器烟测会显示为 `SKIP`
