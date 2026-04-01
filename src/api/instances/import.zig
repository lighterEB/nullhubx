const std = @import("std");
const builtin = @import("builtin");
const helpers = @import("../helpers.zig");
const local_binary = @import("../../core/local_binary.zig");
const legacy = @import("../instances.zig");
const state_mod = @import("../../core/state.zig");
const paths_mod = @import("../../core/paths.zig");

pub const ApiResponse = helpers.ApiResponse;

pub fn handleImport(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8) ApiResponse {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch blk: {
        if (builtin.os.tag == .windows) {
            break :blk std.process.getEnvVarOwned(allocator, "USERPROFILE") catch return helpers.serverError();
        }
        return helpers.serverError();
    };
    defer allocator.free(home);

    const dot_dir = std.fmt.allocPrint(allocator, "{s}/.{s}", .{ home, component }) catch return helpers.serverError();
    defer allocator.free(dot_dir);
    std.fs.accessAbsolute(dot_dir, .{}) catch return helpers.notFound();

    const inst_dir = paths.instanceDir(allocator, component, "default") catch return helpers.serverError();
    defer allocator.free(inst_dir);

    const comp_dir = std.fs.path.join(allocator, &.{ paths.root, "instances", component }) catch return helpers.serverError();
    defer allocator.free(comp_dir);
    std.fs.makeDirAbsolute(comp_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return helpers.serverError(),
    };

    std.fs.deleteFileAbsolute(inst_dir) catch {};
    std.fs.deleteTreeAbsolute(inst_dir) catch {};
    std.fs.symLinkAbsolute(dot_dir, inst_dir, .{ .is_directory = true }) catch return helpers.serverError();

    const version = blk: {
        if (local_binary.find(allocator, component)) |src_bin| {
            defer allocator.free(src_bin);
            const ver = "dev-local";
            const dest_bin = paths.binary(allocator, component, ver) catch break :blk "standalone";
            defer allocator.free(dest_bin);
            std.fs.deleteFileAbsolute(dest_bin) catch {};
            std.fs.copyFileAbsolute(src_bin, dest_bin, .{}) catch break :blk "standalone";
            if (comptime std.fs.has_executable_bit) {
                if (std.fs.openFileAbsolute(dest_bin, .{ .mode = .read_only })) |f| {
                    defer f.close();
                    f.chmod(0o755) catch {};
                } else |_| {}
            }
            break :blk ver;
        }
        break :blk "standalone";
    };

    s.addInstance(component, "default", .{
        .version = version,
        .auto_start = false,
        .verbose = false,
    }) catch return helpers.serverError();
    s.save() catch return helpers.serverError();

    return helpers.jsonOk("{\"status\":\"imported\",\"instance\":\"default\"}");
}
