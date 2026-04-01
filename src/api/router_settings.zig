const std = @import("std");
const access = @import("../access.zig");
const settings_api = @import("settings.zig");
const route_catalog = @import("route_catalog.zig");
const router_common = @import("router_common.zig");

const Response = router_common.Response;
const jsonResponse = router_common.jsonResponse;

pub fn handle(
    allocator: std.mem.Allocator,
    method: []const u8,
    target: []const u8,
    body: []const u8,
    host: []const u8,
    port: u16,
    access_options: access.Options,
) ?Response {
    if (std.mem.eql(u8, target, route_catalog.settings_path)) {
        if (std.mem.eql(u8, method, "GET")) {
            if (settings_api.handleGetSettings(allocator, host, port, access_options)) |json| {
                return jsonResponse(json);
            } else |_| {
                return router_common.internalServerError();
            }
        }
        if (std.mem.eql(u8, method, "PUT")) {
            if (settings_api.handlePutSettings(allocator, body)) |json| {
                return jsonResponse(json);
            } else |_| {
                return router_common.internalServerError();
            }
        }
        return router_common.methodNotAllowed();
    }

    if (std.mem.eql(u8, target, route_catalog.service_install_path)) {
        if (std.mem.eql(u8, method, "POST")) {
            if (settings_api.handleServiceInstall(allocator)) |json| {
                return jsonResponse(json);
            } else |_| {
                return router_common.internalServerError();
            }
        }
        return router_common.methodNotAllowed();
    }

    if (std.mem.eql(u8, target, route_catalog.service_uninstall_path)) {
        if (std.mem.eql(u8, method, "POST")) {
            if (settings_api.handleServiceUninstall(allocator)) |json| {
                return jsonResponse(json);
            } else |_| {
                return router_common.internalServerError();
            }
        }
        return router_common.methodNotAllowed();
    }

    if (std.mem.eql(u8, target, route_catalog.service_status_path)) {
        if (std.mem.eql(u8, method, "GET")) {
            if (settings_api.handleServiceStatus(allocator)) |json| {
                return jsonResponse(json);
            } else |_| {
                return router_common.internalServerError();
            }
        }
        return router_common.methodNotAllowed();
    }

    return null;
}
