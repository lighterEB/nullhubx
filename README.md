# NullHubX

NullClaw 生态系统管理中心 - 安装、配置、监控、更新，一站式管理。

> 🇺🇸 [English](#english) | 🇨🇳 中文

---

## 关于本项目

**NullHubX** 是 [NullHub](https://github.com/nullclaw/nullhub) 的中文增强版，是一个单一 Zig 二进制文件，内嵌 Svelte Web UI，用于安装、配置、监控和更新 NullClaw 生态系统组件（NullClaw、NullBoiler、NullTickets）。

### 致谢

本项目 Fork 自 [nullclaw/nullhub](https://github.com/nullclaw/nullhub)，感谢原作者的杰出工作。

## 为什么创建 NullHubX

NullHub 是一个优秀的 NullClaw 生态管理工具，但为了更好地服务中文用户和探索更多可能性，我们创建了 NullHubX：

### 🎯 主要目标

| 方向 | 说明 |
|------|------|
| **中文本地化** | 界面、文档、错误信息全面中文化，降低使用门槛 |
| **UI/UX 改进** | 优化用户界面和交互体验，更符合中文用户习惯 |
| **功能增强** | 修复 bug、提升性能、增强稳定性 |
| **实验性功能** | 探索新功能方向，为社区提供更多可能性 |

### 📋 开发计划

- [ ] 中文化所有界面文本
- [ ] 中文化所有文档
- [ ] 中文化错误提示和日志信息
- [ ] 优化仪表盘布局
- [ ] 改进移动端适配
- [ ] 添加深色/浅色主题切换
- [ ] 增强日志搜索和过滤功能
- [ ] 添加配置备份/恢复功能
- [ ] 改进错误处理和用户反馈
- [ ] 性能优化和内存使用改进

## 功能特性

- **安装向导** - 基于 manifest 的引导式安装，支持组件感知流程
- **进程监控** - 启动/停止/重启，崩溃恢复与退避策略
- **健康检查** - 周期性 HTTP 健康检查，仪表盘状态卡片
- **跨组件链接** - 自动连接 `NullTickets -> NullBoiler`
- **配置管理** - 结构化编辑器，支持原生 JSON 回退
- **日志查看** - 实时 SSE 流式日志
- **一键更新** - 下载、迁移配置、失败回滚
- **多实例** - 同一组件可运行多个实例
- **Web UI + CLI** - 浏览器仪表盘 + 命令行自动化

## 快速开始

```bash
zig build
./zig-out/bin/nullhubx
```

浏览器将自动打开 [http://nullhubx.localhost:19800](http://nullhubx.localhost:19800)。

本地访问地址：

- `http://nullhubx.local:19800` (mDNS/Bonjour)
- `http://nullhubx.localhost:19800`
- `http://127.0.0.1:19800`

### 运行依赖

- `curl` - 获取发布版本和二进制文件
- `tar` - 解压 UI 模块包

### 构建依赖

- `bun` - 构建 Svelte UI

当缺少依赖时，nullhubx 会尝试通过系统包管理器自动安装。

## 命令行使用

```
nullhubx                          # 启动服务器并打开浏览器
nullhubx serve [--port N]         # 启动服务器（不打开浏览器）
nullhubx version | -v | --version # 显示版本号

nullhubx install <component>      # 终端安装向导
nullhubx uninstall <c>/<n>        # 卸载实例

nullhubx start <c>/<n>            # 启动实例
nullhubx stop <c>/<n>             # 停止实例
nullhubx restart <c>/<n>          # 重启实例
nullhubx start-all / stop-all     # 批量启动/停止

nullhubx status                   # 显示所有实例状态表
nullhubx status <c>/<n>           # 显示单个实例详情
nullhubx logs <c>/<n> [-f]        # 查看日志（-f 实时追踪）

nullhubx check-updates            # 检查新版本
nullhubx update <c>/<n>           # 更新单个实例
nullhubx update-all               # 更新所有实例

nullhubx config <c>/<n> [--edit]  # 查看/编辑配置
nullhubx service install          # 注册并启动系统服务
nullhubx service uninstall        # 移除系统服务
nullhubx service status           # 显示系统服务状态
```

实例地址格式：`{组件名}/{实例名}`

## 架构设计

**Zig 后端** - HTTP 服务器、进程监控器、安装器、manifest 引擎。两种模式：服务器模式（HTTP + 监控线程）或 CLI 模式（直接调用）。

**Svelte 前端** - SvelteKit + static adapter，通过 `@embedFile` 嵌入二进制。组件 UI 模块通过 Svelte 5 `mount()` 动态加载。

**Manifest 驱动** - 每个组件发布 `nullhub-manifest.json`，描述安装、配置、启动、健康检查、向导步骤和 UI 模块。NullHubX 是解析 manifests 的通用引擎。

**存储** - 所有状态存储在 `~/.nullhubx/`（配置、实例、二进制、日志、缓存 manifests）。

## 开发指南

后端测试：

```bash
zig build test
```

前端开发：

```bash
cd ui && bun install
cd ui && bun run dev
```

端到端测试：

```bash
./tests/test_e2e.sh
```

核心回归（推荐）：

```bash
./tests/regression_core_flow.sh
```

## 技术栈

- Zig 0.15.2
- Svelte 5 + SvelteKit (static adapter)
- HTTP/1.1 + JSON
- SSE 实例日志流

## 项目结构

```
src/
  main.zig              # 入口：CLI 分发或服务器启动
  cli.zig               # CLI 命令解析器
  server.zig            # HTTP 服务器 (API + 静态 UI)
  auth.zig              # 可选的 bearer token 认证
  api/                  # REST 端点
  core/                 # Manifest 解析、状态、平台、路径
  installer/            # 下载、构建、UI 模块获取
  supervisor/           # 进程生成、健康检查、管理器
ui/src/
  routes/               # SvelteKit 页面
  lib/components/       # 可复用 Svelte 组件
  lib/api/              # 类型化 API 客户端
tests/
  test_e2e.sh           # 端到端测试脚本
  regression_core_flow.sh # 核心链路回归脚本
```

## 贡献

欢迎贡献！请查看 [Issues](https://github.com/lighterEB/nullhubx/issues) 了解当前任务。

## 许可证

本项目继承原项目许可证，详见 [LICENSE](LICENSE)。

---

## English

NullHubX is a Chinese-enhanced fork of [NullHub](https://github.com/nullclaw/nullhub), a single Zig binary with an embedded Svelte web UI for managing the NullClaw ecosystem.

### Why NullHubX

| Goal | Description |
|------|-------------|
| **Chinese Localization** | Full localization of UI, docs, and error messages |
| **UI/UX Improvements** | Better interface and user experience |
| **Feature Enhancements** | Bug fixes, performance improvements |
| **Experimental Features** | Exploring new possibilities |

### Quick Start

```bash
zig build
./zig-out/bin/nullhubx
```

Opens browser to [http://nullhubx.localhost:19800](http://nullhubx.localhost:19800).

### License

Inherits the original project license. See [LICENSE](LICENSE).
