const std = @import("std");
const orchestration_api = @import("orchestration.zig");
const route_catalog = @import("route_catalog.zig");
const router_common = @import("router_common.zig");

const Response = router_common.Response;

pub fn handle(
    allocator: std.mem.Allocator,
    method: []const u8,
    target: []const u8,
    body: []const u8,
    cfg: orchestration_api.Config,
) ?Response {
    if (!route_catalog.isOrchestrationPath(target)) return null;

    const resp = orchestration_api.handle(allocator, method, target, body, cfg);
    return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
}
