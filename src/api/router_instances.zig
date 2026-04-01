const std = @import("std");
const state_mod = @import("../core/state.zig");
const paths_mod = @import("../core/paths.zig");
const manager_mod = @import("../supervisor/manager.zig");
const config_api = @import("config.zig");
const instances_api = @import("instances.zig");
const instances_dispatch = @import("instances/dispatch.zig");
const logs_api = @import("logs.zig");
const route_catalog = @import("route_catalog.zig");
const router_common = @import("router_common.zig");
const updates_api = @import("updates.zig");

const Response = router_common.Response;

pub fn handle(
    allocator: std.mem.Allocator,
    method: []const u8,
    target: []const u8,
    body: []const u8,
    state: *state_mod.State,
    manager: *manager_mod.Manager,
    mutex: *std.Thread.Mutex,
    paths: paths_mod.Paths,
) ?Response {
    if (!route_catalog.isInstancesPath(target)) return null;

    // Agent config API — /api/instances/{c}/{n}/agents/profiles|bindings
    if (config_api.isAgentProfilesPath(target)) {
        const parsed = config_api.parseAgentProfilesPath(target) orelse return .{
            .status = "500 Internal Server Error",
            .content_type = "application/json",
            .body = "{\"error\":\"invalid agent profiles path\"}",
        };

        if (std.mem.eql(u8, method, "GET")) {
            const resp = config_api.handleGetAgentProfiles(allocator, paths, parsed.component, parsed.name);
            return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
        }
        if (std.mem.eql(u8, method, "PUT")) {
            const resp = config_api.handlePutAgentProfiles(allocator, paths, parsed.component, parsed.name, body);
            return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
        }
        return router_common.methodNotAllowed();
    }

    if (config_api.isAgentBindingsPath(target)) {
        const parsed = config_api.parseAgentBindingsPath(target) orelse return .{
            .status = "500 Internal Server Error",
            .content_type = "application/json",
            .body = "{\"error\":\"invalid agent bindings path\"}",
        };

        if (std.mem.eql(u8, method, "GET")) {
            const resp = config_api.handleGetAgentBindings(allocator, paths, parsed.component, parsed.name);
            return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
        }
        if (std.mem.eql(u8, method, "PUT")) {
            const resp = config_api.handlePutAgentBindings(allocator, paths, parsed.component, parsed.name, body);
            return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
        }
        return router_common.methodNotAllowed();
    }

    // Config API — /api/instances/{c}/{n}/config
    if (config_api.isConfigPath(target)) {
        const parsed = config_api.parseConfigPath(target) orelse return .{
            .status = "500 Internal Server Error",
            .content_type = "application/json",
            .body = "{\"error\":\"invalid config path\"}",
        };

        if (std.mem.eql(u8, method, "GET")) {
            const resolve = config_api.shouldResolve(target);
            const resp = config_api.handleGet(allocator, paths, state, parsed.component, parsed.name, resolve);
            return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
        }
        if (std.mem.eql(u8, method, "PUT")) {
            const resp = config_api.handlePut(allocator, paths, parsed.component, parsed.name, body);
            return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
        }
        if (std.mem.eql(u8, method, "PATCH")) {
            const resp = config_api.handlePatch(allocator, paths, parsed.component, parsed.name, body);
            return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
        }
        return router_common.methodNotAllowed();
    }

    // Logs API — /api/instances/{c}/{n}/logs and /api/instances/{c}/{n}/logs/stream
    if (logs_api.isLogsPath(target)) {
        if (logs_api.parseLogsPath(target)) |parsed| {
            if (std.mem.eql(u8, method, "DELETE")) {
                const source = logs_api.parseSource(target);
                const resp = logs_api.handleDelete(allocator, paths, parsed.component, parsed.name, source);
                return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
            }
            if (!std.mem.eql(u8, method, "GET")) {
                return router_common.methodNotAllowed();
            }
            if (parsed.is_stream) {
                const max_lines = logs_api.parseLines(target);
                const source = logs_api.parseSource(target);
                const resp = logs_api.handleStream(allocator, paths, parsed.component, parsed.name, max_lines, source);
                return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
            }
            const max_lines = logs_api.parseLines(target);
            const source = logs_api.parseSource(target);
            const resp = logs_api.handleGet(allocator, paths, parsed.component, parsed.name, max_lines, source);
            return .{ .status = resp.status, .content_type = resp.content_type, .body = resp.body };
        }
    }

    // Updates API — POST /api/instances/{c}/{n}/update
    if (updates_api.parseUpdatePath(target)) |up| {
        if (std.mem.eql(u8, method, "POST")) {
            const ur = updates_api.handleApplyUpdateRuntime(
                allocator,
                state,
                manager,
                paths,
                up.component,
                up.name,
            );
            return .{ .status = ur.status, .content_type = ur.content_type, .body = ur.body };
        }
        return router_common.methodNotAllowed();
    }

    if (instances_dispatch.dispatch(allocator, state, manager, mutex, paths, method, target, body)) |api_resp| {
        return .{ .status = api_resp.status, .content_type = api_resp.content_type, .body = api_resp.body };
    }

    return router_common.notFound();
}
