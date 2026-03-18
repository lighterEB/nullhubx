# NullHubX 核心链路回归清单

目标：在一次执行中覆盖健康检查、状态、组件、设置、更新、实例配置、日志与 agents profiles/bindings 核心链路。

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
2. 启动 `nullhubx serve --port <PORT>`
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
4. 实例链路回归（若存在实例）
- `GET /api/instances/{c}/{n}/config`
- `GET /api/instances/{c}/{n}/logs`
- 运行 `tests/smoke_agents_api.py`（profiles/bindings roundtrip + 错误分支 + topic id 规范化）

## 前置条件

1. 本机具备 `zig`、`curl`、`python3`
2. 如需覆盖 agents/config/logs 实例链路，需至少存在一个实例

## 结果判定

- `FAILED > 0`：脚本返回非 0，视为回归失败
- 无实例时实例链路为 `SKIP`，基础 API 回归仍可判定通过

