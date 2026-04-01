const std = @import("std");

pub const health_path = "/health";
pub const status_path = "/api/status";
pub const settings_path = "/api/settings";
pub const service_install_path = "/api/service/install";
pub const service_uninstall_path = "/api/service/uninstall";
pub const service_status_path = "/api/service/status";
pub const instances_prefix = "/api/instances";
pub const orchestration_prefix = "/api/orchestration";

pub fn isInstancesPath(target: []const u8) bool {
    return std.mem.startsWith(u8, target, instances_prefix);
}

pub fn isOrchestrationPath(target: []const u8) bool {
    return std.mem.eql(u8, target, orchestration_prefix) or
        std.mem.startsWith(u8, target, orchestration_prefix ++ "/");
}
