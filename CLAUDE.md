# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 快速开始

```bash
zig build                    # 构建（自动构建 UI 并嵌入）
./zig-out/bin/nullhubx       # 启动服务器（端口 19800）
zig build test               # 运行所有测试
```

前端开发模式：
```bash
cd ui && npm run dev         # 或 bun run dev
```

## 架构概览

**技术栈**: Zig 0.15.2 + Svelte 5 (Runes) + SvelteKit (static adapter)

**核心设计**: 单一二进制文件，通过 `@embedFile` 嵌入 Svelte UI，提供 HTTP/1.1 + JSON + SSE API。

### 后端结构 (src/)

| 模块 | 文件 | 职责 |
|------|------|------|
| 入口 | `main.zig`, `cli.zig` | CLI 命令分发 / 服务器启动 |
| HTTP 服务器 | `server.zig` | 路由、请求处理、静态资源 |
| 实例管理 | `supervisor/manager.zig` | 进程生命周期、健康检查、重启退避 |
| 状态持久化 | `core/state.zig` | 原子 JSON 存储 (tmp + rename) |
| API 端点 | `api/*.zig` | REST API (instances/config/logs/wizard 等) |
| 安装器 | `installer/*.zig` | 下载、构建、UI 模块管理 |

**关键模式**:
- `Manager` 使用 `StringHashMap` 管理实例，支持动态添加/删除
- 实例状态机：`stopped → starting → running → failed/restarting`
- 健康检查失败自动重启（退避策略：0s, 2s, 4s, 8s, 16s）
- SSE 日志流：`api/logs.zig` 提供快照流式传输

### 前端结构 (ui/src/)

| 模块 | 文件 | 职责 |
|------|------|------|
| API 客户端 | `lib/api/client.ts` | 类型化 API 封装（请求去重、超时处理） |
| 全局状态 | `lib/statusStore.ts` | 轮询状态管理（3s 间隔、重试逻辑） |
| 路由 | `routes/` | SvelteKit 页面（仪表盘/实例/Agents/配置） |
| 组件 | `lib/components/` | 可复用 UI 组件 |
| 国际化 | `lib/i18n/` | zh-CN / en-US |

**API 客户端特点**:
- 统一超时控制（默认 30s，状态请求 8s）
- 错误消息提取（优先 `body.message` / `body.error`）
- 请求去重（并发相同请求共享 Promise）

### 构建系统 (build.zig)

1. 检测包管理器（优先 bun，fallback npm）
2. 安装依赖 + 构建 Svelte UI
3. 扫描 `ui/build/` 生成 `.generated_ui_assets.zig`
4. 使用 `@embedFile` 嵌入所有静态资源
5. 编译单二进制文件

**生成产物**:
- 二进制：`./zig-out/bin/nullhubx`
- 访问：`http://nullhubx.localhost:19800` 或 `http://127.0.0.1:19800`

## 常用命令

### 测试
```bash
zig build test                          # 运行所有单元测试
zig build test -- --filter pattern      # 运行匹配测试
./tests/regression_core_flow.sh         # 核心链路回归测试
./tests/test_e2e.sh                     # 端到端测试
```

### API 调试
```bash
nullhubx api GET /status                # 获取全局状态
nullhubx api GET /instances             # 获取所有实例
nullhubx api POST /instances/nullclaw/default/start
```

### CLI 命令
```bash
nullhubx status                         # 显示实例状态表
nullhubx start nullclaw/default         # 启动实例
nullhubx logs nullclaw/default -f       # 追踪日志
nullhubx config nullclaw/default        # 查看配置
nullhubx service install                # 注册系统服务
```

## 开发注意事项

### Zig 代码风格
- 使用 `std.mem.Allocator` 显式内存管理
- 错误处理使用 `catch` + `try` 组合
- 测试使用 `test` 块，运行 `zig build test`
- 字符串比较用 `std.mem.eql(u8, a, b)`

### Svelte 5 代码风格
- 使用 Runes (`$state`, `$derived`, `$effect`)
- 类型使用 TypeScript
- 组件状态优先本地管理，全局状态用 `statusStore.ts`

### 关键文件引用
- HTTP 路由定义：`src/server.zig` (约 1800 行)
- 实例生命周期：`src/supervisor/manager.zig` (约 900 行)
- API 客户端：`ui/src/lib/api/client.ts`
- 状态轮询：`ui/src/lib/statusStore.ts`

## 文档索引

- 主文档：`README.md`
- 设计文档：`docs/plans/`
- 配置可视化工程：`docs/config-visualization/README.md`
  - 阶段进度：`docs/config-visualization/phase-progress.md`
  - 架构蓝图：`docs/config-visualization/phase-06-backend-driven-ui-architecture.md`

## Tiger Style 规范 (Zig)

本项目遵循 Tiger Style 原则：**正确性 > 可观测性 > 性能**

当前实现差距：
- 缺少 `comptime assert` 验证嵌入资源非空
- SSE 为快照轮询，非真实时 EventSource
- 使用 `HashMap` 而非静态 `[MAX_N]T` 数组（更灵活但偏离规范）
