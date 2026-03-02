pub const cli = @import("cli.zig");
pub const config_writer = @import("wizard/config_writer.zig");
pub const health = @import("supervisor/health.zig");
pub const main = @import("main.zig");
pub const manager = @import("supervisor/manager.zig");
pub const manifest = @import("core/manifest.zig");
pub const paths = @import("core/paths.zig");
pub const platform = @import("core/platform.zig");
pub const process = @import("supervisor/process.zig");
pub const registry = @import("installer/registry.zig");
pub const server = @import("server.zig");
pub const state = @import("core/state.zig");
pub const wizard_engine = @import("wizard/engine.zig");

test {
    _ = cli;
    _ = config_writer;
    _ = health;
    _ = main;
    _ = manager;
    _ = manifest;
    _ = paths;
    _ = platform;
    _ = process;
    _ = registry;
    _ = server;
    _ = state;
    _ = wizard_engine;
}
