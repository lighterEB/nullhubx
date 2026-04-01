const std = @import("std");
const state_mod = @import("state.zig");
const paths_mod = @import("paths.zig");
const component_cli = @import("component_cli.zig");
const helpers = @import("../api/helpers.zig");

pub const ApiResponse = helpers.ApiResponse;

pub const CapturedInstanceCli = union(enum) {
    response: ApiResponse,
    result: component_cli.RunResult,
};

pub fn buildInstanceUrl(allocator: std.mem.Allocator, port: u16, path: []const u8) ?[]const u8 {
    return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}{s}", .{ port, path }) catch null;
}

pub fn fetchJsonValue(allocator: std.mem.Allocator, url: []const u8, bearer_token: ?[]const u8) ?std.json.Value {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    var response_body: std.io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    var auth_header: ?[]const u8 = null;
    defer if (auth_header) |value| allocator.free(value);
    var header_buf: [1]std.http.Header = undefined;
    const extra_headers: []const std.http.Header = if (bearer_token) |token| blk: {
        auth_header = std.fmt.allocPrint(allocator, "Bearer {s}", .{token}) catch return null;
        header_buf[0] = .{ .name = "Authorization", .value = auth_header.? };
        break :blk header_buf[0..1];
    } else &.{};

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &response_body.writer,
        .extra_headers = extra_headers,
    }) catch return null;
    if (@intFromEnum(result.status) < 200 or @intFromEnum(result.status) >= 300) return null;

    const bytes = response_body.toOwnedSlice() catch return null;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    return parsed.value;
}

pub fn isLikelyJsonPayload(bytes: []const u8) bool {
    const trimmed = std.mem.trim(u8, bytes, " \t\r\n");
    if (trimmed.len == 0) return false;
    return switch (trimmed[0]) {
        '{', '[', '"', 'n', 't', 'f', '-', '0'...'9' => true,
        else => false,
    };
}

fn firstMeaningfulLine(text: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return "";
    if (std.mem.indexOfScalar(u8, trimmed, '\n')) |idx| {
        return std.mem.trim(u8, trimmed[0..idx], " \t\r");
    }
    return trimmed;
}

fn buildCliJsonError(
    allocator: std.mem.Allocator,
    code: []const u8,
    message: []const u8,
    stderr: ?[]const u8,
    stdout: ?[]const u8,
) ![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice("{\"error\":\"");
    try helpers.appendEscaped(&buf, code);
    try buf.appendSlice("\",\"message\":\"");
    try helpers.appendEscaped(&buf, message);
    try buf.append('"');

    if (stderr) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len > 0) {
            try buf.appendSlice(",\"stderr\":\"");
            try helpers.appendEscaped(&buf, trimmed);
            try buf.append('"');
        }
    }

    if (stdout) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len > 0) {
            try buf.appendSlice(",\"stdout\":\"");
            try helpers.appendEscaped(&buf, trimmed);
            try buf.append('"');
        }
    }

    try buf.append('}');
    return try buf.toOwnedSlice();
}

fn jsonCliError(
    allocator: std.mem.Allocator,
    code: []const u8,
    message: []const u8,
    stderr: ?[]const u8,
    stdout: ?[]const u8,
) ApiResponse {
    const body = buildCliJsonError(allocator, code, message, stderr, stdout) catch return helpers.serverError();
    return helpers.jsonOk(body);
}

pub fn jsonCliConflict(
    allocator: std.mem.Allocator,
    code: []const u8,
    message: []const u8,
    stderr: ?[]const u8,
    stdout: ?[]const u8,
) ApiResponse {
    const body = buildCliJsonError(allocator, code, message, stderr, stdout) catch return helpers.serverError();
    return .{
        .status = "409 Conflict",
        .content_type = "application/json",
        .body = body,
    };
}

pub fn runInstanceCliCaptured(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    args: []const []const u8,
) CapturedInstanceCli {
    const entry = s.getInstance(component, name) orelse return .{ .response = helpers.notFound() };

    const bin_path = paths.binary(allocator, component, entry.version) catch return .{ .response = helpers.serverError() };
    defer allocator.free(bin_path);
    std.fs.accessAbsolute(bin_path, .{}) catch {
        return .{ .response = jsonCliError(
            allocator,
            "component_binary_missing",
            "Component binary is missing for this instance version",
            null,
            null,
        ) };
    };

    const inst_dir = paths.instanceDir(allocator, component, name) catch return .{ .response = helpers.serverError() };
    defer allocator.free(inst_dir);

    const result = component_cli.runWithComponentHome(
        allocator,
        component,
        bin_path,
        args,
        null,
        inst_dir,
    ) catch {
        return .{ .response = jsonCliError(
            allocator,
            "cli_exec_failed",
            "Failed to execute component CLI",
            null,
            null,
        ) };
    };

    return .{ .result = result };
}

pub fn runInstanceCliJson(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    args: []const []const u8,
) ApiResponse {
    const captured = runInstanceCliCaptured(allocator, s, paths, component, name, args);
    const result = switch (captured) {
        .response => |resp| return resp,
        .result => |value| value,
    };
    defer allocator.free(result.stderr);

    if (result.success and isLikelyJsonPayload(result.stdout)) {
        return helpers.jsonOk(result.stdout);
    }
    if (!result.success and isLikelyJsonPayload(result.stdout)) {
        return helpers.jsonOk(result.stdout);
    }

    defer allocator.free(result.stdout);

    const stderr_line = firstMeaningfulLine(result.stderr);
    const stdout_line = firstMeaningfulLine(result.stdout);
    const message = if (stderr_line.len > 0)
        stderr_line
    else if (stdout_line.len > 0)
        stdout_line
    else if (result.success)
        "CLI returned a non-JSON response"
    else
        "CLI command failed";

    return jsonCliError(
        allocator,
        if (result.success) "invalid_cli_response" else "cli_command_failed",
        message,
        result.stderr,
        result.stdout,
    );
}

test "isLikelyJsonPayload recognizes common JSON starts" {
    try std.testing.expect(isLikelyJsonPayload("{\"ok\":true}"));
    try std.testing.expect(isLikelyJsonPayload("[1,2,3]"));
    try std.testing.expect(isLikelyJsonPayload("  null"));
    try std.testing.expect(!isLikelyJsonPayload("plain text"));
}

test "jsonCliConflict returns 409 with structured error body" {
    const resp = jsonCliConflict(std.testing.allocator, "cli_failed", "command failed", "stderr line", null);
    defer std.testing.allocator.free(resp.body);

    try std.testing.expectEqualStrings("409 Conflict", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"error\":\"cli_failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"stderr\":\"stderr line\"") != null);
}
