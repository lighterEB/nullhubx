const std = @import("std");

pub fn backoffDelayMs(restart_count: u32) i64 {
    return if (restart_count == 0)
        0
    else
        @as(i64, 1000) * (@as(i64, 1) << @intCast(@min(restart_count, 4)));
}
