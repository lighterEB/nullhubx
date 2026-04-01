const std = @import("std");
const legacy = @import("../instances.zig");
const state_mod = @import("../../core/state.zig");
const paths_mod = @import("../../core/paths.zig");

pub const ApiResponse = @import("../helpers.zig").ApiResponse;

pub fn handleOnboarding(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) ApiResponse {
    return legacy.handleOnboarding(allocator, s, paths, component, name);
}
