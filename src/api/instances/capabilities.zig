const std = @import("std");
const helpers = @import("../helpers.zig");
const command_service = @import("../../core/component_command_service.zig");
const paths_mod = @import("../../core/paths.zig");
const state_mod = @import("../../core/state.zig");

pub const ApiResponse = helpers.ApiResponse;

pub fn handleGet(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) ApiResponse {
    if (!std.mem.eql(u8, component, "nullclaw")) {
        const body = std.fmt.allocPrint(
            allocator,
            "{{\"error\":\"capabilities_unavailable\",\"message\":\"Runtime capability probe is only supported for {s} instances\"}}",
            .{component},
        ) catch return helpers.serverError();
        return helpers.jsonOk(body);
    }

    return command_service.runInstanceCliJson(
        allocator,
        s,
        paths,
        component,
        name,
        &.{ "capabilities", "--json" },
    );
}
