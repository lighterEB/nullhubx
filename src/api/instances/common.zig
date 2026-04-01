const std = @import("std");
const legacy = @import("../instances.zig");

pub const ParsedPath = legacy.ParsedPath;

pub fn parsePath(target: []const u8) ?ParsedPath {
    return legacy.parsePath(target);
}

pub fn stripQuery(target: []const u8) []const u8 {
    return legacy.stripQuery(target);
}

pub fn isIntegrationPath(target: []const u8) bool {
    return legacy.isIntegrationPath(target);
}
