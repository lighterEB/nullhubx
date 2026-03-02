pub const main = @import("main.zig");
pub const paths = @import("core/paths.zig");
pub const platform = @import("core/platform.zig");

test {
    _ = main;
    _ = paths;
    _ = platform;
}
