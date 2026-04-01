const std = @import("std");
const access = @import("../access.zig");
const state_mod = @import("../core/state.zig");
const manager_mod = @import("../supervisor/manager.zig");
const status_api = @import("status.zig");
const route_catalog = @import("route_catalog.zig");
const router_common = @import("router_common.zig");

const Response = router_common.Response;

pub fn handle(
    allocator: std.mem.Allocator,
    method: []const u8,
    target: []const u8,
    state: *state_mod.State,
    manager: *manager_mod.Manager,
    start_time: i64,
    host: []const u8,
    port: u16,
    access_options: access.Options,
) ?Response {
    if (!std.mem.eql(u8, method, "GET")) return null;

    if (std.mem.eql(u8, target, route_catalog.health_path)) {
        return .{
            .status = "200 OK",
            .content_type = "application/json",
            .body = "{\"status\":\"ok\"}",
        };
    }

    if (std.mem.eql(u8, target, route_catalog.status_path)) {
        const now = std.time.timestamp();
        const uptime: u64 = @intCast(@max(0, now - start_time));
        const resp = status_api.handleStatus(allocator, state, manager, uptime, host, port, access_options);
        return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
    }

    return null;
}
