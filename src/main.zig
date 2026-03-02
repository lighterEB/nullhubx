const std = @import("std");
pub const root = @import("root.zig");

const version = "0.1.0";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name

    const command = args.next();
    if (command) |cmd| {
        if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "version")) {
            std.debug.print("nullhub v{s}\n", .{version});
            return;
        }
    }

    std.debug.print("nullhub v{s}\n", .{version});
    std.debug.print("usage: nullhub [serve|install|start|stop|status|version]\n", .{});
}
