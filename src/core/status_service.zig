const std = @import("std");
const access = @import("../access.zig");
const state_mod = @import("state.zig");
const manager_mod = @import("../supervisor/manager.zig");

pub const HubAccessView = struct {
    browser_open_url: []u8,
    direct_url: []u8,
    canonical_url: []u8,
    fallback_url: []u8,
    local_alias_chain: bool,
    public_alias_active: bool,
    public_alias_provider: []u8,
    public_alias_url: ?[]u8,

    pub fn deinit(self: *HubAccessView, allocator: std.mem.Allocator) void {
        allocator.free(self.browser_open_url);
        allocator.free(self.direct_url);
        allocator.free(self.canonical_url);
        allocator.free(self.fallback_url);
        allocator.free(self.public_alias_provider);
        if (self.public_alias_url) |value| allocator.free(value);
        self.* = undefined;
    }
};

pub const InstanceRuntimeView = struct {
    status: []const u8,
    pid: ?std.process.Child.Id,
    uptime_seconds: ?u64,
    restart_count: u32,
    port: u16,
    health_consecutive_failures: u32,
};

pub fn buildHubAccessView(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    access_options: access.Options,
) !HubAccessView {
    var urls = try access.buildAccessUrlsWithOptions(allocator, host, port, access_options);
    defer urls.deinit(allocator);

    return .{
        .browser_open_url = try allocator.dupe(u8, urls.browser_open_url),
        .direct_url = try allocator.dupe(u8, urls.direct_url),
        .canonical_url = try allocator.dupe(u8, urls.canonical_url),
        .fallback_url = try allocator.dupe(u8, urls.fallback_url),
        .local_alias_chain = urls.local_alias_chain,
        .public_alias_active = urls.public_alias_active,
        .public_alias_provider = try allocator.dupe(u8, urls.public_alias_provider),
        .public_alias_url = if (urls.public_alias_url) |value| try allocator.dupe(u8, value) else null,
    };
}

pub fn buildInstanceRuntimeView(
    manager: *manager_mod.Manager,
    component: []const u8,
    name: []const u8,
) InstanceRuntimeView {
    const mgr_status = manager.getStatus(component, name);
    return .{
        .status = if (mgr_status) |st| @tagName(st.status) else "stopped",
        .pid = if (mgr_status) |st| st.pid else null,
        .uptime_seconds = if (mgr_status) |st| st.uptime_seconds else null,
        .restart_count = if (mgr_status) |st| st.restart_count else 0,
        .port = if (mgr_status) |st| st.port else 0,
        .health_consecutive_failures = if (mgr_status) |st| st.health_consecutive_failures else 0,
    };
}

pub fn buildInstanceRuntimeViewFromEntry(
    manager: *manager_mod.Manager,
    component: []const u8,
    name: []const u8,
    _: state_mod.InstanceEntry,
) InstanceRuntimeView {
    return buildInstanceRuntimeView(manager, component, name);
}

test "buildInstanceRuntimeView uses manager status when present" {
    const allocator = std.testing.allocator;
    var paths = try @import("paths.zig").Paths.init(allocator, "/tmp/nullhubx-status-service-test");
    defer paths.deinit(allocator);

    var manager = manager_mod.Manager.init(allocator, paths);
    defer manager.deinit();

    const key = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ "nullclaw", "demo" });
    try manager.instances.put(key, .{
        .component = "nullclaw",
        .name = "demo",
        .status = .running,
        .pid = null,
        .port = 4317,
        .restart_count = 2,
        .health_consecutive_failures = 1,
        .started_at = std.time.milliTimestamp() - 10_000,
    });

    const view = buildInstanceRuntimeView(&manager, "nullclaw", "demo");
    try std.testing.expectEqualStrings("running", view.status);
    try std.testing.expectEqual(@as(u16, 4317), view.port);
    try std.testing.expectEqual(@as(u32, 2), view.restart_count);
    try std.testing.expectEqual(@as(u32, 1), view.health_consecutive_failures);
}

test "buildHubAccessView returns canonical urls" {
    var view = try buildHubAccessView(std.testing.allocator, access.default_bind_host, access.default_port, .{});
    defer view.deinit(std.testing.allocator);

    try std.testing.expect(std.mem.indexOf(u8, view.browser_open_url, "nullhubx.localhost") != null);
    try std.testing.expect(std.mem.indexOf(u8, view.direct_url, "127.0.0.1") != null);
}
