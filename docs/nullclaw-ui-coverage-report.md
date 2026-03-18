# NullClaw 配置可视化覆盖差异报告 (v2)

- Catalog 字段总数: **511**
- UI 已覆盖字段: **381**
- UI 未覆盖字段: **130**
- 覆盖率: **74.56%**

## 数据来源占比

- `config.example.json`: 140
- `config_parse.zig`: 155
- `config_types.zig`: 471

## 按顶层块统计（未覆盖优先）

| Top-level | Total | Missing |
| --- | ---: | ---: |
| `a2a` | 5 | 0 |
| `agent` | 18 | 4 |
| `agents` | 5 | 0 |
| `autonomy` | 6 | 0 |
| `browser` | 13 | 0 |
| `channels` | 210 | 2 |
| `composio` | 3 | 0 |
| `cost` | 5 | 0 |
| `cron` | 3 | 0 |
| `default_model` | 1 | 0 |
| `default_provider` | 1 | 0 |
| `default_temperature` | 1 | 0 |
| `diagnostics` | 17 | 2 |
| `gateway` | 8 | 0 |
| `hardware` | 6 | 0 |
| `heartbeat` | 2 | 0 |
| `http_request` | 8 | 0 |
| `identity` | 3 | 0 |
| `mcp_servers` | 1 | 0 |
| `memory` | 112 | 112 |
| `model_routes` | 1 | 0 |
| `models` | 8 | 0 |
| `peripherals` | 6 | 6 |
| `reasoning_effort` | 1 | 0 |
| `reliability` | 11 | 2 |
| `runtime` | 7 | 0 |
| `scheduler` | 4 | 0 |
| `secrets` | 1 | 0 |
| `security` | 15 | 0 |
| `session` | 11 | 2 |
| `tools` | 8 | 0 |
| `tunnel` | 9 | 0 |
| `workspace` | 1 | 0 |

## 未覆盖字段（前 160 项）

- `agent.tool_filter_groups`
- `agent.tool_filter_groups[*].keywords`
- `agent.tool_filter_groups[*].mode`
- `agent.tool_filter_groups[*].tools`
- `channels.external.accounts.<account>.transport.env[*].key`
- `channels.external.accounts.<account>.transport.env[*].value`
- `diagnostics.otel_headers[*].key`
- `diagnostics.otel_headers[*].value`
- `memory.api.api_key`
- `memory.api.namespace`
- `memory.api.timeout_ms`
- `memory.api.url`
- `memory.auto_save`
- `memory.backend`
- `memory.citations`
- `memory.clickhouse.database`
- `memory.clickhouse.host`
- `memory.clickhouse.password`
- `memory.clickhouse.port`
- `memory.clickhouse.table`
- `memory.clickhouse.use_https`
- `memory.clickhouse.user`
- `memory.instance_id`
- `memory.lifecycle.archive_after_days`
- `memory.lifecycle.auto_hydrate`
- `memory.lifecycle.conversation_retention_days`
- `memory.lifecycle.hygiene_enabled`
- `memory.lifecycle.preserve_before_purge`
- `memory.lifecycle.purge_after_days`
- `memory.lifecycle.snapshot_enabled`
- `memory.lifecycle.snapshot_on_hygiene`
- `memory.postgres.connect_timeout_secs`
- `memory.postgres.schema`
- `memory.postgres.table`
- `memory.postgres.url`
- `memory.profile`
- `memory.qmd.command`
- `memory.qmd.enabled`
- `memory.qmd.include_default_memory`
- `memory.qmd.limits.max_injected_chars`
- `memory.qmd.limits.max_results`
- `memory.qmd.limits.max_snippet_chars`
- `memory.qmd.limits.timeout_ms`
- `memory.qmd.mcporter.enabled`
- `memory.qmd.mcporter.server_name`
- `memory.qmd.mcporter.start_daemon`
- `memory.qmd.paths[*].name`
- `memory.qmd.paths[*].path`
- `memory.qmd.paths[*].pattern`
- `memory.qmd.search_mode`
- `memory.qmd.sessions.enabled`
- `memory.qmd.sessions.export_dir`
- `memory.qmd.sessions.retention_days`
- `memory.qmd.update.command_timeout_ms`
- `memory.qmd.update.debounce_ms`
- `memory.qmd.update.embed_interval_ms`
- `memory.qmd.update.embed_timeout_ms`
- `memory.qmd.update.interval_ms`
- `memory.qmd.update.on_boot`
- `memory.qmd.update.update_timeout_ms`
- `memory.qmd.update.wait_for_boot_sync`
- `memory.redis.db_index`
- `memory.redis.host`
- `memory.redis.key_prefix`
- `memory.redis.password`
- `memory.redis.port`
- `memory.redis.ttl_seconds`
- `memory.reliability.canary_hybrid_percent`
- `memory.reliability.circuit_breaker_cooldown_ms`
- `memory.reliability.circuit_breaker_failures`
- `memory.reliability.fallback_policy`
- `memory.reliability.rollout_mode`
- `memory.reliability.shadow_hybrid_percent`
- `memory.response_cache.enabled`
- `memory.response_cache.max_entries`
- `memory.response_cache.ttl_minutes`
- `memory.retrieval_stages.adaptive_keyword_max_tokens`
- `memory.retrieval_stages.adaptive_retrieval_enabled`
- `memory.retrieval_stages.adaptive_vector_min_tokens`
- `memory.retrieval_stages.llm_reranker_enabled`
- `memory.retrieval_stages.llm_reranker_max_candidates`
- `memory.retrieval_stages.llm_reranker_timeout_ms`
- `memory.retrieval_stages.query_expansion_enabled`
- `memory.search.cache.enabled`
- `memory.search.cache.max_entries`
- `memory.search.chunking.overlap`
- `memory.search.dimensions`
- `memory.search.enabled`
- `memory.search.fallback_provider`
- `memory.search.model`
- `memory.search.provider`
- `memory.search.query.hybrid.candidate_multiplier`
- `memory.search.query.hybrid.enabled`
- `memory.search.query.hybrid.mmr.enabled`
- `memory.search.query.hybrid.mmr.lambda`
- `memory.search.query.hybrid.temporal_decay.enabled`
- `memory.search.query.hybrid.temporal_decay.half_life_days`
- `memory.search.query.hybrid.text_weight`
- `memory.search.query.hybrid.vector_weight`
- `memory.search.query.max_results`
- `memory.search.query.merge_strategy`
- `memory.search.query.min_score`
- `memory.search.query.rrf_k`
- `memory.search.store.ann_candidate_multiplier`
- `memory.search.store.ann_min_candidates`
- `memory.search.store.kind`
- `memory.search.store.pgvector_table`
- `memory.search.store.qdrant_api_key`
- `memory.search.store.qdrant_collection`
- `memory.search.store.qdrant_url`
- `memory.search.store.sidecar_path`
- `memory.search.sync.embed_max_retries`
- `memory.search.sync.embed_timeout_ms`
- `memory.search.sync.mode`
- `memory.search.sync.vector_max_retries`
- `memory.search.sync.vector_timeout_ms`
- `memory.summarizer.auto_extract_semantic`
- `memory.summarizer.enabled`
- `memory.summarizer.summary_max_tokens`
- `memory.summarizer.window_size_tokens`
- `peripherals.boards[*].baud`
- `peripherals.boards[*].board`
- `peripherals.boards[*].path`
- `peripherals.boards[*].transport`
- `peripherals.datasheet_dir`
- `peripherals.enabled`
- `reliability.model_fallbacks[*].fallbacks`
- `reliability.model_fallbacks[*].model`
- `session.identity_links[*].canonical`
- `session.identity_links[*].peers`

## 说明

- v2 引入了 `config_types.zig` 与 `config_parse.zig`，覆盖完整性高于 v1。
- 仍建议在后续阶段增加运行时样本采集，以补齐动态 map 的键约束。
