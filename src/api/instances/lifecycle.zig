const std = @import("std");
const component_cli = @import("../../core/component_cli.zig");
const helpers = @import("../helpers.zig");
const launch_args_mod = @import("../../core/launch_args.zig");
const legacy = @import("../instances.zig");
const managed_skills = @import("../../managed_skills.zig");
const manifest_mod = @import("../../core/manifest.zig");
const nullclaw_web_channel = @import("../../core/nullclaw_web_channel.zig");
const state_mod = @import("../../core/state.zig");
const manager_mod = @import("../../supervisor/manager.zig");
const paths_mod = @import("../../core/paths.zig");

pub const ApiResponse = helpers.ApiResponse;

pub fn handleList(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager) ApiResponse {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    buildListJson(&buf, s, manager) catch return .{
        .status = "500 Internal Server Error",
        .content_type = "application/json",
        .body = "{\"error\":\"internal error\"}",
    };

    const body = buf.toOwnedSlice() catch return helpers.serverError();
    return helpers.jsonOk(body);
}

pub fn handleGet(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, component: []const u8, name: []const u8) ApiResponse {
    const entry = s.getInstance(component, name) orelse return helpers.notFound();

    const status_str = if (manager.getStatus(component, name)) |st| @tagName(st.status) else "stopped";

    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    appendInstanceJson(&buf, entry, status_str) catch return .{
        .status = "500 Internal Server Error",
        .content_type = "application/json",
        .body = "{\"error\":\"internal error\"}",
    };
    const body = buf.toOwnedSlice() catch return helpers.serverError();
    return helpers.jsonOk(body);
}

pub fn handleStart(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, paths: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    const entry = s.getInstance(component, name) orelse return helpers.notFound();

    _ = nullclaw_web_channel.ensureNullclawWebChannelConfig(
        allocator,
        paths,
        s,
        component,
        name,
    ) catch return helpers.serverError();

    if (std.mem.eql(u8, component, "nullclaw")) {
        const workspace_dir = instanceWorkspaceDir(allocator, paths, component, name) catch return helpers.serverError();
        defer allocator.free(workspace_dir);
        const config_path = paths.instanceConfig(allocator, component, name) catch return helpers.serverError();
        defer allocator.free(config_path);
        _ = managed_skills.installAlwaysBundledSkills(allocator, component, workspace_dir, config_path) catch return helpers.serverError();
    }

    const StartBody = struct {
        launch_mode: ?[]const u8 = null,
        verbose: ?bool = null,
    };
    var launch_cmd: []const u8 = entry.launch_mode;
    var launch_verbose = entry.verbose;
    var parsed_body: ?std.json.Parsed(StartBody) = null;
    defer if (parsed_body) |*pb| pb.deinit();
    if (body.len > 0) {
        parsed_body = std.json.parseFromSlice(
            StartBody,
            allocator,
            body,
            .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
        ) catch null;
        if (parsed_body) |pb| {
            if (pb.value.launch_mode) |mode| launch_cmd = mode;
            if (pb.value.verbose) |verbose| launch_verbose = verbose;
        }
    }

    const bin_path = paths.binary(allocator, component, entry.version) catch return helpers.serverError();
    defer allocator.free(bin_path);
    std.fs.accessAbsolute(bin_path, .{}) catch return helpers.serverError();

    var health_endpoint: []const u8 = "/health";
    var port: u16 = 0;
    var port_from_config: []const u8 = "";
    const manifest_json = component_cli.exportManifest(allocator, bin_path) catch null;
    var parsed_manifest: ?std.json.Parsed(manifest_mod.Manifest) = null;
    if (manifest_json) |mj| {
        parsed_manifest = manifest_mod.parseManifest(allocator, mj) catch null;
        if (parsed_manifest) |pm| {
            health_endpoint = pm.value.health.endpoint;
            port_from_config = pm.value.health.port_from_config;
            if (pm.value.ports.len > 0) port = pm.value.ports[0].default;
        }
    }
    defer if (manifest_json) |mj| allocator.free(mj);
    defer if (parsed_manifest) |*pm| pm.deinit();

    if (port_from_config.len > 0) {
        if (readPortFromConfig(allocator, paths, component, name, port_from_config)) |config_port| {
            port = config_port;
        }
    }

    const launch_args = launch_args_mod.buildLaunchArgs(allocator, launch_cmd, launch_verbose) catch return helpers.serverError();
    defer allocator.free(launch_args);
    const primary_cmd = if (launch_args.len > 0) launch_args[0] else launch_cmd;
    const effective_port: u16 = if (std.mem.eql(u8, primary_cmd, "agent")) 0 else port;

    const inst_dir = paths.instanceDir(allocator, component, name) catch return helpers.serverError();
    defer allocator.free(inst_dir);

    manager.startInstance(component, name, bin_path, launch_args, effective_port, health_endpoint, inst_dir, "", launch_cmd) catch return helpers.serverError();
    return helpers.jsonOk("{\"status\":\"started\"}");
}

pub fn handleStop(s: *state_mod.State, manager: *manager_mod.Manager, component: []const u8, name: []const u8) ApiResponse {
    _ = s.getInstance(component, name) orelse return helpers.notFound();
    manager.stopInstance(component, name) catch return helpers.serverError();
    return helpers.jsonOk("{\"status\":\"stopped\"}");
}

pub fn handleRestart(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, paths: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    _ = s.getInstance(component, name) orelse return helpers.notFound();
    manager.stopInstance(component, name) catch {};
    return handleStart(allocator, s, manager, paths, component, name, body);
}

pub fn handleDelete(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, paths: paths_mod.Paths, component: []const u8, name: []const u8) ApiResponse {
    const existing = s.getInstance(component, name) orelse return helpers.notFound();
    const rollback_version = allocator.dupe(u8, existing.version) catch return helpers.serverError();
    defer allocator.free(rollback_version);
    const rollback_launch_mode = allocator.dupe(u8, existing.launch_mode) catch return helpers.serverError();
    defer allocator.free(rollback_launch_mode);

    const inst_dir = paths.instanceDir(allocator, component, name) catch return helpers.serverError();
    defer allocator.free(inst_dir);

    manager.stopInstance(component, name) catch {};
    const hidden_inst_dir = hideInstanceDirForDelete(allocator, inst_dir) catch return helpers.serverError();
    defer if (hidden_inst_dir) |path| allocator.free(path);

    if (!s.removeInstance(component, name)) {
        if (hidden_inst_dir) |path| {
            std.fs.renameAbsolute(path, inst_dir) catch {};
        }
        return helpers.notFound();
    }
    s.save() catch {
        _ = s.addInstance(component, name, .{
            .version = rollback_version,
            .auto_start = existing.auto_start,
            .launch_mode = rollback_launch_mode,
            .verbose = existing.verbose,
        }) catch {};
        _ = s.save() catch {};
        if (hidden_inst_dir) |path| {
            std.fs.renameAbsolute(path, inst_dir) catch {};
        }
        return helpers.serverError();
    };

    if (hidden_inst_dir) |path| {
        std.fs.deleteTreeAbsolute(path) catch |err| {
            std.log.warn("deleted instance {s}/{s} but failed to clean hidden dir '{s}': {s}", .{
                component,
                name,
                path,
                @errorName(err),
            });
        };
    }

    return helpers.jsonOk("{\"status\":\"deleted\"}");
}

pub fn handlePatch(s: *state_mod.State, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    const entry = s.getInstance(component, name) orelse return helpers.notFound();

    const parsed = std.json.parseFromSlice(
        struct {
            auto_start: ?bool = null,
            launch_mode: ?[]const u8 = null,
            verbose: ?bool = null,
        },
        s.allocator,
        body,
        .{ .allocate = .alloc_always, .ignore_unknown_fields = true },
    ) catch return helpers.badRequest("{\"error\":\"invalid JSON body\"}");
    defer parsed.deinit();

    const new_auto_start = parsed.value.auto_start orelse entry.auto_start;
    const new_launch_mode = parsed.value.launch_mode orelse entry.launch_mode;
    const new_verbose = parsed.value.verbose orelse entry.verbose;

    _ = s.updateInstance(component, name, .{
        .version = entry.version,
        .auto_start = new_auto_start,
        .launch_mode = new_launch_mode,
        .verbose = new_verbose,
    }) catch return helpers.serverError();

    s.save() catch return helpers.serverError();

    return helpers.jsonOk("{\"status\":\"updated\"}");
}

fn appendInstanceJson(buf: *std.array_list.Managed(u8), entry: state_mod.InstanceEntry, status_str: []const u8) !void {
    try buf.appendSlice("{\"version\":\"");
    try helpers.appendEscaped(buf, entry.version);
    try buf.appendSlice("\",\"auto_start\":");
    try buf.appendSlice(if (entry.auto_start) "true" else "false");
    try buf.appendSlice(",\"launch_mode\":\"");
    try helpers.appendEscaped(buf, entry.launch_mode);
    try buf.appendSlice("\",\"verbose\":");
    try buf.appendSlice(if (entry.verbose) "true" else "false");
    try buf.appendSlice(",\"status\":\"");
    try buf.appendSlice(status_str);
    try buf.appendSlice("\"}");
}

fn buildListJson(buf: *std.array_list.Managed(u8), s: *state_mod.State, manager: *manager_mod.Manager) !void {
    try buf.appendSlice("{\"instances\":{");

    var comp_it = s.instances.iterator();
    var first_comp = true;
    while (comp_it.next()) |comp_entry| {
        if (!first_comp) try buf.append(',');
        first_comp = false;

        try buf.append('"');
        try helpers.appendEscaped(buf, comp_entry.key_ptr.*);
        try buf.appendSlice("\":{");

        var inst_it = comp_entry.value_ptr.iterator();
        var first_inst = true;
        while (inst_it.next()) |inst_entry| {
            if (!first_inst) try buf.append(',');
            first_inst = false;

            const status_str = if (manager.getStatus(comp_entry.key_ptr.*, inst_entry.key_ptr.*)) |st| @tagName(st.status) else "stopped";

            try buf.append('"');
            try helpers.appendEscaped(buf, inst_entry.key_ptr.*);
            try buf.appendSlice("\":");
            try appendInstanceJson(buf, inst_entry.value_ptr.*, status_str);
        }

        try buf.append('}');
    }

    try buf.appendSlice("}}");
}

fn hideInstanceDirForDelete(allocator: std.mem.Allocator, inst_dir: []const u8) !?[]const u8 {
    std.fs.accessAbsolute(inst_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };

    const parent = std.fs.path.dirname(inst_dir) orelse return error.InvalidPath;
    const base = std.fs.path.basename(inst_dir);
    const ts = @as(u64, @intCast(@max(0, std.time.milliTimestamp())));

    var attempt: u32 = 0;
    while (attempt < 1024) : (attempt += 1) {
        const hidden_path = try std.fmt.allocPrint(allocator, "{s}/.{s}.deleted-{d}-{d}", .{
            parent,
            base,
            ts,
            attempt,
        });
        errdefer allocator.free(hidden_path);

        std.fs.renameAbsolute(inst_dir, hidden_path) catch |err| switch (err) {
            error.FileNotFound => return null,
            error.PathAlreadyExists => continue,
            else => return err,
        };
        return hidden_path;
    }

    return error.PathAlreadyExists;
}

fn instanceWorkspaceDir(allocator: std.mem.Allocator, paths: paths_mod.Paths, component: []const u8, name: []const u8) ![]u8 {
    const inst_dir = try paths.instanceDir(allocator, component, name);
    defer allocator.free(inst_dir);
    return try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
}

fn readPortFromConfig(allocator: std.mem.Allocator, paths: paths_mod.Paths, component: []const u8, name: []const u8, dot_key: []const u8) ?u16 {
    const config_path = paths.instanceConfig(allocator, component, name) catch return null;
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();
    const contents = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch return null;
    defer allocator.free(contents);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{
        .allocate = .alloc_always,
    }) catch return null;
    defer parsed.deinit();

    var current = parsed.value;
    var it = std.mem.splitScalar(u8, dot_key, '.');
    while (it.next()) |segment| {
        switch (current) {
            .object => |obj| current = obj.get(segment) orelse return null,
            else => return null,
        }
    }

    return switch (current) {
        .integer => |v| if (v >= 0 and v <= 65535) @intCast(v) else null,
        else => null,
    };
}
