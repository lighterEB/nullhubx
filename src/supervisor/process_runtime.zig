const std = @import("std");

pub fn encodeLaunchArgsJson(allocator: std.mem.Allocator, launch_args: []const []const u8) ![]const u8 {
    if (launch_args.len == 0) return "";
    return std.json.Stringify.valueAlloc(allocator, launch_args, .{
        .emit_null_optional_fields = false,
    });
}

pub fn decodeLaunchArgsJson(
    allocator: std.mem.Allocator,
    launch_args_json: []const u8,
) !std.array_list.Managed([]const u8) {
    var argv_list = std.array_list.Managed([]const u8).init(allocator);
    if (launch_args_json.len == 0) return argv_list;

    const parsed = try std.json.parseFromSlice([]const []const u8, allocator, launch_args_json, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    for (parsed.value) |arg| {
        try argv_list.append(try allocator.dupe(u8, arg));
    }
    return argv_list;
}

pub fn freeDecodedLaunchArgs(allocator: std.mem.Allocator, argv_list: *std.array_list.Managed([]const u8)) void {
    for (argv_list.items) |arg| allocator.free(arg);
    argv_list.deinit();
}
