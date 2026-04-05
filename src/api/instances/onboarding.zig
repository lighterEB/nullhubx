const std = @import("std");
const component_cli = @import("../../core/component_cli.zig");
const command_service = @import("../../core/component_command_service.zig");
const helpers = @import("../helpers.zig");
const legacy = @import("../instances.zig");
const state_mod = @import("../../core/state.zig");
const paths_mod = @import("../../core/paths.zig");

pub const ApiResponse = helpers.ApiResponse;

const NullclawOnboardingStatus = struct {
    supported: bool = false,
    pending: bool = false,
    completed: bool = false,
    bootstrap_exists: bool = false,
    bootstrap_seeded_at: ?[]u8 = null,
    onboarding_completed_at: ?[]u8 = null,

    fn deinit(self: *NullclawOnboardingStatus, allocator: std.mem.Allocator) void {
        if (self.bootstrap_seeded_at) |value| allocator.free(value);
        if (self.onboarding_completed_at) |value| allocator.free(value);
        self.* = .{};
    }
};

const NullclawBootstrapMemoryProbe = struct {
    exists: bool = false,
    timestamp: ?[]u8 = null,

    fn deinit(self: *NullclawBootstrapMemoryProbe, allocator: std.mem.Allocator) void {
        if (self.timestamp) |value| allocator.free(value);
        self.* = .{};
    }

    fn takeTimestamp(self: *NullclawBootstrapMemoryProbe) ?[]u8 {
        const value = self.timestamp;
        self.timestamp = null;
        return value;
    }
};

const nullclaw_bootstrap_memory_key = "__bootstrap.prompt.BOOTSTRAP.md";

fn fileExistsAbsolute(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn nullclawWorkspaceStatePath(allocator: std.mem.Allocator, workspace_dir: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ workspace_dir, ".nullclaw", "workspace-state.json" });
}

fn probeNullclawBootstrapInMemory(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) NullclawBootstrapMemoryProbe {
    const entry = s.getInstance(component, name) orelse return .{};

    const bin_path = paths.binary(allocator, component, entry.version) catch return .{};
    defer allocator.free(bin_path);
    std.fs.accessAbsolute(bin_path, .{}) catch return .{};

    const inst_dir = paths.instanceDir(allocator, component, name) catch return .{};
    defer allocator.free(inst_dir);

    const args = [_][]const u8{
        "memory",
        "get",
        nullclaw_bootstrap_memory_key,
        "--json",
    };
    const result = component_cli.runWithComponentHome(
        allocator,
        component,
        bin_path,
        &args,
        null,
        inst_dir,
    ) catch return .{};
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (!result.success or !command_service.isLikelyJsonPayload(result.stdout)) return .{};

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{
        .allocate = .alloc_if_needed,
        .ignore_unknown_fields = true,
    }) catch return .{};
    defer parsed.deinit();

    switch (parsed.value) {
        .null => return .{},
        .object => |obj| {
            var probe = NullclawBootstrapMemoryProbe{ .exists = true };
            if (obj.get("timestamp")) |timestamp_value| {
                if (timestamp_value == .string and timestamp_value.string.len > 0) {
                    probe.timestamp = allocator.dupe(u8, timestamp_value.string) catch null;
                }
            }
            return probe;
        },
        else => return .{},
    }
}

fn readNullclawOnboardingStatus(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) !NullclawOnboardingStatus {
    var status = NullclawOnboardingStatus{};
    errdefer status.deinit(allocator);

    if (!std.mem.eql(u8, component, "nullclaw")) return status;
    status.supported = true;

    const inst_dir = try paths.instanceDir(allocator, component, name);
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);

    const bootstrap_path = try std.fs.path.join(allocator, &.{ workspace_dir, "BOOTSTRAP.md" });
    defer allocator.free(bootstrap_path);
    status.bootstrap_exists = fileExistsAbsolute(bootstrap_path);

    const state_path = try nullclawWorkspaceStatePath(allocator, workspace_dir);
    defer allocator.free(state_path);

    const state_file = std.fs.openFileAbsolute(state_path, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (state_file) |file| {
        defer file.close();
        const raw = file.readToEndAlloc(allocator, 64 * 1024) catch null;
        if (raw) |state_raw| {
            defer allocator.free(state_raw);
            const parsed = std.json.parseFromSlice(struct {
                bootstrap_seeded_at: ?[]const u8 = null,
                bootstrapSeededAt: ?[]const u8 = null,
                onboarding_completed_at: ?[]const u8 = null,
                onboardingCompletedAt: ?[]const u8 = null,
            }, allocator, state_raw, .{
                .allocate = .alloc_if_needed,
                .ignore_unknown_fields = true,
            }) catch null;
            if (parsed) |state_parsed| {
                defer state_parsed.deinit();
                if (state_parsed.value.bootstrap_seeded_at orelse state_parsed.value.bootstrapSeededAt) |seeded| {
                    status.bootstrap_seeded_at = try allocator.dupe(u8, seeded);
                }
                if (state_parsed.value.onboarding_completed_at orelse state_parsed.value.onboardingCompletedAt) |completed| {
                    status.onboarding_completed_at = try allocator.dupe(u8, completed);
                }
            }
        }
    }

    status.completed = status.onboarding_completed_at != null and !status.bootstrap_exists;

    var bootstrap_probe = NullclawBootstrapMemoryProbe{};
    if (!status.completed and !status.bootstrap_exists) {
        bootstrap_probe = probeNullclawBootstrapInMemory(allocator, s, paths, component, name);
        if (status.bootstrap_seeded_at == null) {
            status.bootstrap_seeded_at = bootstrap_probe.takeTimestamp();
        }
    }
    defer bootstrap_probe.deinit(allocator);

    status.pending = !status.completed and (status.bootstrap_exists or status.bootstrap_seeded_at != null or bootstrap_probe.exists);
    return status;
}

pub fn handleOnboarding(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) ApiResponse {
    if (s.getInstance(component, name) == null) return helpers.notFound();

    var status = readNullclawOnboardingStatus(allocator, s, paths, component, name) catch
        return helpers.serverError();
    defer status.deinit(allocator);

    const body = std.json.Stringify.valueAlloc(allocator, .{
        .supported = status.supported,
        .pending = status.pending,
        .completed = status.completed,
        .bootstrap_exists = status.bootstrap_exists,
        .bootstrap_seeded_at = status.bootstrap_seeded_at,
        .onboarding_completed_at = status.onboarding_completed_at,
        .starter_message = if (status.supported) "Wake up, my friend!" else null,
    }, .{}) catch return helpers.serverError();

    return helpers.jsonOk(body);
}

test "handleOnboarding reports pending bootstrap for fresh nullclaw workspace" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = @import("../instances.zig").TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "my-agent");
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);
    try @import("../instances.zig").ensurePath(workspace_dir);

    const bootstrap_path = try std.fs.path.join(allocator, &.{ workspace_dir, "BOOTSTRAP.md" });
    defer allocator.free(bootstrap_path);
    const bootstrap_file = try std.fs.createFileAbsolute(bootstrap_path, .{ .truncate = true });
    defer bootstrap_file.close();
    try bootstrap_file.writeAll("# bootstrap\n");

    const resp = handleOnboarding(allocator, &s, mctx.paths, "nullclaw", "my-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pending\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"starter_message\":\"Wake up, my friend!\"") != null);
}

test "handleOnboarding reports pending bootstrap from workspace state without disk bootstrap file" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = @import("../instances.zig").TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "my-agent");
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);
    try @import("../instances.zig").ensurePath(workspace_dir);

    const state_path = try nullclawWorkspaceStatePath(allocator, workspace_dir);
    defer allocator.free(state_path);
    try @import("../instances.zig").ensurePath(std.fs.path.dirname(state_path).?);
    const state_file = try std.fs.createFileAbsolute(state_path, .{ .truncate = true });
    defer state_file.close();
    try state_file.writeAll(
        "{\n  \"bootstrap_seeded_at\": \"2026-03-13T01:17:17Z\"\n}\n",
    );

    const resp = handleOnboarding(allocator, &s, mctx.paths, "nullclaw", "my-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_exists\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pending\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"completed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_seeded_at\":\"2026-03-13T01:17:17Z\"") != null);
}

test "handleOnboarding falls back to CLI bootstrap memory for legacy sqlite workspace" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = @import("../instances.zig").TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "legacy-agent", .{ .version = "1.0.3" });
    const script =
        \\#!/bin/sh
        \\if [ "$1" = "memory" ] && [ "$2" = "get" ] && [ "$3" = "__bootstrap.prompt.BOOTSTRAP.md" ]; then
        \\  if [ -z "$NULLCLAW_HOME" ]; then
        \\    echo "missing home" >&2
        \\    exit 1
        \\  fi
        \\  printf '%s\n' '{"key":"__bootstrap.prompt.BOOTSTRAP.md","category":"core","timestamp":"2026-03-13T02:37:27Z","content":"# bootstrap","session_id":null}'
        \\  exit 0
        \\fi
        \\echo "unexpected args" >&2
        \\exit 1
        \\
    ;
    try @import("../instances.zig").writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.3", script);

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "legacy-agent");
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);
    try @import("../instances.zig").ensurePath(workspace_dir);

    const resp = handleOnboarding(allocator, &s, mctx.paths, "nullclaw", "legacy-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_exists\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pending\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"completed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_seeded_at\":\"2026-03-13T02:37:27Z\"") != null);
}

test "handleOnboarding stays idle when legacy sqlite bootstrap memory is absent" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = @import("../instances.zig").TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "empty-agent", .{ .version = "1.0.4" });
    const script =
        \\#!/bin/sh
        \\if [ "$1" = "memory" ] && [ "$2" = "get" ] && [ "$3" = "__bootstrap.prompt.BOOTSTRAP.md" ]; then
        \\  printf '%s\n' 'null'
        \\  exit 0
        \\fi
        \\echo "unexpected args" >&2
        \\exit 1
        \\
    ;
    try @import("../instances.zig").writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.4", script);

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "empty-agent");
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);
    try @import("../instances.zig").ensurePath(workspace_dir);

    const resp = handleOnboarding(allocator, &s, mctx.paths, "nullclaw", "empty-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_exists\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pending\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"completed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_seeded_at\":null") != null);
}
