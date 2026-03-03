const std = @import("std");

pub const CliError = error{
    CommandFailed,
};

pub const RunResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    success: bool,
};

/// Run a component binary with the given arguments and capture stdout.
/// Caller owns the returned stdout and stderr slices.
pub fn run(allocator: std.mem.Allocator, binary_path: []const u8, args: []const []const u8, cwd: ?[]const u8) !RunResult {
    return runWithNullclawHome(allocator, binary_path, args, cwd, null);
}

/// Run a component binary with optional NULLCLAW_HOME override for instance-scoped commands.
/// Caller owns the returned stdout and stderr slices.
pub fn runWithNullclawHome(
    allocator: std.mem.Allocator,
    binary_path: []const u8,
    args: []const []const u8,
    cwd: ?[]const u8,
    nullclaw_home: ?[]const u8,
) !RunResult {
    // Build argv: binary + args
    var argv = std.array_list.Managed([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append(binary_path);
    for (args) |arg| try argv.append(arg);

    var env_map_opt: ?std.process.EnvMap = null;
    defer {
        if (env_map_opt) |*env_map| env_map.deinit();
    }
    if (nullclaw_home) |home| {
        var env_map = try std.process.getEnvMap(allocator);
        try env_map.put("NULLCLAW_HOME", home);
        env_map_opt = env_map;
    }

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
        .cwd = cwd,
        .env_map = if (env_map_opt) |*env_map| env_map else null,
    }) catch return error.CommandFailed;

    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .success = switch (result.term) {
            .Exited => |code| code == 0,
            else => false,
        },
    };
}

/// Run --export-manifest on a component binary and return the raw JSON.
pub fn exportManifest(allocator: std.mem.Allocator, binary_path: []const u8) ![]const u8 {
    const result = try run(allocator, binary_path, &.{"--export-manifest"}, null);
    defer allocator.free(result.stderr);
    if (!result.success) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }
    return result.stdout;
}

/// Run --list-models on a component binary and return the raw JSON array.
pub fn listModels(allocator: std.mem.Allocator, binary_path: []const u8, provider: []const u8, api_key: []const u8) ![]const u8 {
    const result = try run(allocator, binary_path, &.{ "--list-models", "--provider", provider, "--api-key", api_key }, null);
    defer allocator.free(result.stderr);
    if (!result.success) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }
    return result.stdout;
}

pub const FromJsonResult = struct {
    stdout: []const u8,
    stderr: []const u8,
    success: bool,
};

/// Run --from-json on a component binary with the given JSON answers.
/// The JSON should include a "home" field for instance isolation (injected by orchestrator).
pub fn fromJson(allocator: std.mem.Allocator, binary_path: []const u8, json_answers: []const u8, cwd: ?[]const u8) !FromJsonResult {
    const result = try run(allocator, binary_path, &.{ "--from-json", json_answers }, cwd);
    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .success = result.success,
    };
}
