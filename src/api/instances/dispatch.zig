const std = @import("std");
const helpers = @import("../helpers.zig");
const state_mod = @import("../../core/state.zig");
const manager_mod = @import("../../supervisor/manager.zig");
const paths_mod = @import("../../core/paths.zig");
const common = @import("common.zig");
const lifecycle = @import("lifecycle.zig");
const onboarding = @import("onboarding.zig");
const bridge = @import("bridge.zig");
const integration = @import("integration.zig");
const usage = @import("usage.zig");
const import_instance = @import("import.zig");

pub const ApiResponse = helpers.ApiResponse;

pub fn dispatch(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    manager: *manager_mod.Manager,
    mutex: *std.Thread.Mutex,
    paths: paths_mod.Paths,
    method: []const u8,
    target: []const u8,
    body: []const u8,
) ?ApiResponse {
    if (std.mem.eql(u8, common.stripQuery(target), "/api/instances")) {
        if (std.mem.eql(u8, method, "GET")) return lifecycle.handleList(allocator, s, manager);
        return helpers.methodNotAllowed();
    }

    const parsed = common.parsePath(target) orelse return null;

    if (parsed.action) |action| {
        if (std.mem.eql(u8, action, "provider-health")) {
            if (!std.mem.eql(u8, method, "GET")) return helpers.methodNotAllowed();
            return bridge.handleProviderHealth(allocator, s, manager, paths, parsed.component, parsed.name);
        }
        if (std.mem.eql(u8, action, "usage")) {
            if (!std.mem.eql(u8, method, "GET")) return helpers.methodNotAllowed();
            return usage.handleUsage(allocator, s, paths, parsed.component, parsed.name, target);
        }
        if (std.mem.eql(u8, action, "history")) {
            if (!std.mem.eql(u8, method, "GET")) return helpers.methodNotAllowed();
            return bridge.handleHistory(allocator, s, paths, parsed.component, parsed.name, target);
        }
        if (std.mem.eql(u8, action, "onboarding")) {
            if (!std.mem.eql(u8, method, "GET")) return helpers.methodNotAllowed();
            return onboarding.handleOnboarding(allocator, s, paths, parsed.component, parsed.name);
        }
        if (std.mem.eql(u8, action, "memory")) {
            if (!std.mem.eql(u8, method, "GET")) return helpers.methodNotAllowed();
            return bridge.handleMemory(allocator, s, paths, parsed.component, parsed.name, target);
        }
        if (std.mem.eql(u8, action, "skills")) {
            if (std.mem.eql(u8, method, "GET")) return bridge.handleSkills(allocator, s, paths, parsed.component, parsed.name, target);
            if (std.mem.eql(u8, method, "POST")) return bridge.handleSkillsInstall(allocator, s, paths, parsed.component, parsed.name, body);
            if (std.mem.eql(u8, method, "DELETE")) return bridge.handleSkillsRemove(allocator, s, paths, parsed.component, parsed.name, target);
            return helpers.methodNotAllowed();
        }
        if (std.mem.eql(u8, action, "integration")) {
            if (std.mem.eql(u8, method, "GET")) return integration.handleGet(allocator, s, manager, mutex, paths, parsed.component, parsed.name);
            if (std.mem.eql(u8, method, "POST")) return integration.handlePost(allocator, s, manager, mutex, paths, parsed.component, parsed.name, body);
            return helpers.methodNotAllowed();
        }

        if (!std.mem.eql(u8, method, "POST")) return helpers.methodNotAllowed();
        if (std.mem.eql(u8, action, "start")) return lifecycle.handleStart(allocator, s, manager, paths, parsed.component, parsed.name, body);
        if (std.mem.eql(u8, action, "stop")) return lifecycle.handleStop(s, manager, parsed.component, parsed.name);
        if (std.mem.eql(u8, action, "restart")) return lifecycle.handleRestart(allocator, s, manager, paths, parsed.component, parsed.name, body);
        return helpers.notFound();
    }

    if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, parsed.name, "import")) {
        return import_instance.handleImport(allocator, s, paths, parsed.component);
    }

    if (std.mem.eql(u8, method, "GET")) return lifecycle.handleGet(allocator, s, manager, parsed.component, parsed.name);
    if (std.mem.eql(u8, method, "DELETE")) return lifecycle.handleDelete(allocator, s, manager, paths, parsed.component, parsed.name);
    if (std.mem.eql(u8, method, "PATCH")) return lifecycle.handlePatch(s, parsed.component, parsed.name, body);
    return helpers.methodNotAllowed();
}

const TestManagerCtx = struct {
    manager: manager_mod.Manager,
    mutex: std.Thread.Mutex = .{},
    paths: paths_mod.Paths,

    fn init(allocator: std.mem.Allocator) TestManagerCtx {
        const root = std.fmt.allocPrint(
            allocator,
            "/tmp/nullhubx-test-instances-dispatch-{d}-{x}",
            .{ std.time.nanoTimestamp(), std.crypto.random.int(u64) },
        ) catch @panic("alloc test root failed");
        defer allocator.free(root);

        var p = paths_mod.Paths.init(allocator, root) catch @panic("Paths.init failed");
        std.fs.deleteTreeAbsolute(p.root) catch {};
        p.ensureDirs() catch @panic("ensureDirs failed");
        return .{
            .paths = p,
            .manager = manager_mod.Manager.init(allocator, p),
            .mutex = .{},
        };
    }

    fn deinit(self: *TestManagerCtx, allocator: std.mem.Allocator) void {
        self.manager.deinit();
        std.fs.deleteTreeAbsolute(self.paths.root) catch {};
        self.paths.deinit(allocator);
    }
};

fn ensureTestPath(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn writeTestBinary(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    version: []const u8,
    script: []const u8,
) !void {
    try paths.ensureDirs();
    const bin_path = try paths.binary(allocator, component, version);
    defer allocator.free(bin_path);

    const file = try std.fs.createFileAbsolute(bin_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(script);
    if (comptime std.fs.has_executable_bit) {
        try file.chmod(0o755);
    }
}

test "dispatch routes skills catalog through seam" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-dispatch.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/instances/nullclaw/my-agent/skills?catalog=1", "").?;
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"name\":\"nullhubx-admin\"") != null);
}

test "dispatch routes provider-health through seam" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-dispatch.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/instances/nullclaw/my-agent/provider-health", "").?;
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
}

test "dispatch routes history through seam" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-dispatch.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });
    const script =
        \\#!/bin/sh
        \\if [ "$1" = "history" ] && [ "$2" = "list" ]; then
        \\  printf '%s\n' '{"sessions":[{"session_id":"s-1"}],"total":1}'
        \\  exit 0
        \\fi
        \\exit 1
        \\
    ;
    try writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.0", script);

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/instances/nullclaw/my-agent/history", "").?;
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"session_id\":\"s-1\"") != null);
}

test "dispatch routes memory through seam" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-dispatch.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.1" });
    const script =
        \\#!/bin/sh
        \\if [ "$1" = "memory" ] && [ "$2" = "stats" ]; then
        \\  printf '%s\n' '{"total":5}'
        \\  exit 0
        \\fi
        \\exit 1
        \\
    ;
    try writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.1", script);

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/instances/nullclaw/my-agent/memory?stats=1", "").?;
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"total\":5") != null);
}

test "dispatch routes import through seam" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-dispatch.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return error.SkipZigTest;
    defer allocator.free(home);
    const standalone_dir = try std.fmt.allocPrint(allocator, "{s}/.{s}", .{ home, "nullclaw" });
    defer allocator.free(standalone_dir);
    try ensureTestPath(standalone_dir);
    defer std.fs.deleteTreeAbsolute(standalone_dir) catch {};

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "POST", "/api/instances/nullclaw/import", "").?;
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"imported\"") != null);
}
