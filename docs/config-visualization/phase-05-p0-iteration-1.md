# Phase 5 - P0 落地（Iteration 1）

## 目标

启动可视化配置 P0 实施，并先解决“扩展成本高、模板重复”问题。

## 本次改动

1. `ConfigEditorUI` 结构改造
- 将原来的 `Agent/Autonomy/Diagnostics` 三段重复模板改为通用循环渲染：
  - `staticSections.slice(1)` 逐节渲染
  - 统一支持 `toggle/number/text/select/list`

2. 新增 P0 配置区块（`configSchemas.ts`）
- `Gateway`
  - `gateway.host`
  - `gateway.port`
  - `gateway.require_pairing`
  - `gateway.allow_public_bind`
  - `gateway.pair_rate_limit_per_minute`
  - `gateway.webhook_rate_limit_per_minute`
- `Reliability`
  - `reliability.provider_retries`
  - `reliability.provider_backoff_ms`
  - `reliability.channel_initial_backoff_secs`
  - `reliability.channel_max_backoff_secs`
  - `reliability.scheduler_poll_secs`
  - `reliability.scheduler_retries`
- `Security`
  - `security.sandbox.backend`
  - `security.audit.enabled`
  - `security.audit.retention_days`
  - `security.resources.max_memory_mb`
  - `security.resources.max_cpu_percent`
  - `security.resources.max_disk_mb`
  - `security.resources.max_subprocesses`

## 验证

执行：

```bash
cd ui && bun run build
```

结果：通过。

覆盖报告同步刷新：

- `docs/nullclaw-ui-coverage-report.md`
- 覆盖率由 `19.86%` 提升到 `22.52%`（`161/715`）

## 当前状态

Phase 5 进入 `in_progress`，已完成首轮 P0 基础块与渲染框架改造。

## 下一轮计划

1. `models.providers` 高级字段（`base_url/native_tools/user_agent`）可视化
2. `agents.list` 可视化编辑（与现有 agents 面板衔接）
3. `session/tools/http_request/runtime` 分块接入
