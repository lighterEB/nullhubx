const std = @import("std");
const helpers = @import("../helpers.zig");
const command_service = @import("../../core/component_command_service.zig");
const integration_mod = @import("../../core/integration.zig");
const lifecycle = @import("lifecycle.zig");
const state_mod = @import("../../core/state.zig");
const manager_mod = @import("../../supervisor/manager.zig");
const paths_mod = @import("../../core/paths.zig");

pub const ApiResponse = helpers.ApiResponse;

const default_tracker_prompt_template =
    "Task {{task.id}}: {{task.title}}\n\n{{task.description}}\n\nMetadata:\n{{task.metadata}}";

const PipelineSummary = struct {
    id: []const u8,
    name: []const u8,
    roles: []const []const u8,
    triggers: []const []const u8,
};

const TrackerIntegrationOption = struct {
    name: []const u8,
    port: u16,
    running: bool,
    pipelines: []const PipelineSummary = &.{},
};

pub fn isIntegrationPath(target: []const u8) bool {
    const parsed = @import("common.zig").parsePath(target) orelse return false;
    return parsed.action != null and std.mem.eql(u8, parsed.action.?, "integration");
}

fn getStatusLocked(
    mutex: *std.Thread.Mutex,
    manager: *manager_mod.Manager,
    component: []const u8,
    name: []const u8,
) ?manager_mod.InstanceStatus {
    mutex.lock();
    defer mutex.unlock();
    return manager.getStatus(component, name);
}

fn listNullTicketsLocked(
    allocator: std.mem.Allocator,
    mutex: *std.Thread.Mutex,
    state: *state_mod.State,
    paths: paths_mod.Paths,
) ![]integration_mod.NullTicketsConfig {
    mutex.lock();
    defer mutex.unlock();
    return integration_mod.listNullTickets(allocator, state, paths);
}

fn listNullBoilersLocked(
    allocator: std.mem.Allocator,
    mutex: *std.Thread.Mutex,
    state: *state_mod.State,
    paths: paths_mod.Paths,
) ![]integration_mod.NullBoilerConfig {
    mutex.lock();
    defer mutex.unlock();
    return integration_mod.listNullBoilers(allocator, state, paths);
}

fn fetchPipelineSummaries(allocator: std.mem.Allocator, url: []const u8, bearer_token: ?[]const u8) ?[]PipelineSummary {
    const parsed = command_service.fetchJsonValue(allocator, url, bearer_token) orelse return null;
    if (parsed != .array) return null;

    var list: std.ArrayListUnmanaged(PipelineSummary) = .empty;
    errdefer deinitPipelineSummaries(allocator, list.items);
    defer list.deinit(allocator);

    for (parsed.array.items) |item| {
        const summary = parsePipelineSummary(allocator, item) catch continue;
        list.append(allocator, summary) catch {
            deinitPipelineSummary(allocator, summary);
            return null;
        };
    }

    return list.toOwnedSlice(allocator) catch null;
}

fn parsePipelineSummary(allocator: std.mem.Allocator, value: std.json.Value) !PipelineSummary {
    if (value != .object) return error.InvalidPipelineSummary;
    const obj = value.object;
    const definition = obj.get("definition") orelse return error.InvalidPipelineSummary;
    if (definition != .object) return error.InvalidPipelineSummary;

    return .{
        .id = try allocator.dupe(u8, jsonStringOrEmpty(obj, "id")),
        .name = try allocator.dupe(u8, jsonStringOrEmpty(obj, "name")),
        .roles = try collectPipelineRoles(allocator, definition),
        .triggers = try collectPipelineTriggers(allocator, definition),
    };
}

fn collectPipelineRoles(allocator: std.mem.Allocator, definition: std.json.Value) ![]const []const u8 {
    if (definition != .object) return allocator.alloc([]const u8, 0);
    const states_val = definition.object.get("states") orelse return allocator.alloc([]const u8, 0);
    if (states_val != .object) return allocator.alloc([]const u8, 0);

    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer list.deinit(allocator);

    var it = states_val.object.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .object) continue;
        const role = jsonString(entry.value_ptr.*.object, "agent_role") orelse continue;
        try appendUniqueString(allocator, &list, role);
    }

    return list.toOwnedSlice(allocator);
}

fn collectPipelineTriggers(allocator: std.mem.Allocator, definition: std.json.Value) ![]const []const u8 {
    if (definition != .object) return allocator.alloc([]const u8, 0);
    const transitions_val = definition.object.get("transitions") orelse return allocator.alloc([]const u8, 0);
    if (transitions_val != .array) return allocator.alloc([]const u8, 0);

    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer list.deinit(allocator);

    for (transitions_val.array.items) |transition| {
        if (transition != .object) continue;
        const trigger = jsonString(transition.object, "trigger") orelse continue;
        try appendUniqueString(allocator, &list, trigger);
    }

    return list.toOwnedSlice(allocator);
}

fn appendUniqueString(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged([]const u8), value: []const u8) !void {
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, value)) return;
    }
    try list.append(allocator, try allocator.dupe(u8, value));
}

fn deinitPipelineSummary(allocator: std.mem.Allocator, summary: PipelineSummary) void {
    allocator.free(summary.id);
    allocator.free(summary.name);
    for (summary.roles) |role| allocator.free(role);
    allocator.free(summary.roles);
    for (summary.triggers) |trigger| allocator.free(trigger);
    allocator.free(summary.triggers);
}

fn deinitPipelineSummaries(allocator: std.mem.Allocator, summaries: []const PipelineSummary) void {
    for (summaries) |summary| deinitPipelineSummary(allocator, summary);
    allocator.free(@constCast(summaries));
}

fn jsonString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = obj.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

fn jsonStringOrEmpty(obj: std.json.ObjectMap, key: []const u8) []const u8 {
    return jsonString(obj, key) orelse "";
}

fn pipelineContainsString(values: []const []const u8, candidate: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, candidate)) return true;
    }
    return false;
}

fn ensurePath(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn ensureObjectField(
    allocator: std.mem.Allocator,
    parent: *std.json.ObjectMap,
    key: []const u8,
) !*std.json.ObjectMap {
    if (parent.getPtr(key)) |value_ptr| {
        if (value_ptr.* != .object) {
            value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
        }
        return &value_ptr.object;
    }

    try parent.put(key, .{ .object = std.json.ObjectMap.init(allocator) });
    return &parent.getPtr(key).?.object;
}

fn resolvePathFromConfig(allocator: std.mem.Allocator, config_path: []const u8, value: []const u8) ![]const u8 {
    if (value.len == 0 or std.fs.path.isAbsolute(value)) return allocator.dupe(u8, value);
    const config_dir = std.fs.path.dirname(config_path) orelse return error.InvalidPath;
    return std.fs.path.resolve(allocator, &.{ config_dir, value });
}

fn isNullHubXManagedWorkflow(
    allocator: std.mem.Allocator,
    workflow_path: []const u8,
) bool {
    const file = std.fs.openFileAbsolute(workflow_path, .{}) catch return false;
    defer file.close();

    const bytes = file.readToEndAlloc(allocator, 1024 * 1024) catch return false;
    defer allocator.free(bytes);

    const parsed = std.json.parseFromSlice(struct {
        id: []const u8 = "",
        execution: []const u8 = "",
        prompt_template: ?[]const u8 = null,
    }, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return false;
    defer parsed.deinit();

    return std.mem.startsWith(u8, parsed.value.id, "wf-") and
        std.mem.eql(u8, parsed.value.execution, "subprocess") and
        parsed.value.prompt_template != null and
        std.mem.eql(u8, parsed.value.prompt_template.?, default_tracker_prompt_template);
}

pub fn handleGet(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    manager: *manager_mod.Manager,
    mutex: *std.Thread.Mutex,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) ApiResponse {
    if (std.mem.eql(u8, component, "nullboiler")) {
        var boiler_cfg = integration_mod.loadNullBoilerConfig(allocator, paths, name) catch null orelse return helpers.notFound();
        defer integration_mod.deinitNullBoilerConfig(allocator, &boiler_cfg);
        const trackers = listNullTicketsLocked(allocator, mutex, s, paths) catch return helpers.serverError();
        defer integration_mod.deinitNullTicketsConfigs(allocator, trackers);
        const linked = integration_mod.matchNullTicketsTarget(boiler_cfg, trackers);

        var tracker_options = std.ArrayListUnmanaged(TrackerIntegrationOption){};
        defer {
            for (tracker_options.items) |option| {
                deinitPipelineSummaries(allocator, option.pipelines);
            }
            tracker_options.deinit(allocator);
        }

        for (trackers) |tracker| {
            const is_running = blk: {
                const status = getStatusLocked(mutex, manager, "nulltickets", tracker.name) orelse break :blk false;
                break :blk status.status == .running;
            };
            const pipelines = blk: {
                if (!is_running) break :blk allocator.alloc(PipelineSummary, 0) catch return helpers.serverError();
                const url = command_service.buildInstanceUrl(allocator, tracker.port, "/pipelines") orelse break :blk allocator.alloc(PipelineSummary, 0) catch return helpers.serverError();
                defer allocator.free(url);
                break :blk fetchPipelineSummaries(allocator, url, tracker.api_token) orelse (allocator.alloc(PipelineSummary, 0) catch return helpers.serverError());
            };
            tracker_options.append(allocator, .{
                .name = tracker.name,
                .port = tracker.port,
                .running = is_running,
                .pipelines = pipelines,
            }) catch return helpers.serverError();
        }

        const tracker_status = blk: {
            const status = getStatusLocked(mutex, manager, "nullboiler", name) orelse break :blk null;
            if (status.status != .running) break :blk null;
            const url = command_service.buildInstanceUrl(allocator, boiler_cfg.port, "/tracker/status") orelse break :blk null;
            defer allocator.free(url);
            break :blk command_service.fetchJsonValue(allocator, url, boiler_cfg.api_token);
        };

        const queue_status = blk: {
            const linked_tracker = linked orelse break :blk null;
            const status = getStatusLocked(mutex, manager, "nulltickets", linked_tracker.name) orelse break :blk null;
            if (status.status != .running) break :blk null;
            const url = command_service.buildInstanceUrl(allocator, linked_tracker.port, "/ops/queue") orelse break :blk null;
            defer allocator.free(url);
            break :blk command_service.fetchJsonValue(allocator, url, linked_tracker.api_token);
        };

        const body = std.json.Stringify.valueAlloc(allocator, .{
            .kind = "nullboiler",
            .configured = boiler_cfg.tracker != null,
            .linked_tracker = if (linked) |tracker| .{
                .name = tracker.name,
                .port = tracker.port,
            } else null,
            .available_trackers = tracker_options.items,
            .current_link = if (boiler_cfg.tracker) |tracker| if (tracker.workflow) |workflow| .{
                .pipeline_id = workflow.pipeline_id,
                .claim_role = workflow.claim_role,
                .success_trigger = workflow.success_trigger,
                .max_concurrent_tasks = tracker.max_concurrent_tasks,
                .agent_id = tracker.agent_id,
                .workflow_file = workflow.file_name,
            } else null else null,
            .tracker = tracker_status,
            .queue = queue_status,
        }, .{ .emit_null_optional_fields = false }) catch return helpers.serverError();
        return helpers.jsonOk(body);
    }

    if (std.mem.eql(u8, component, "nulltickets")) {
        var tickets_cfg = integration_mod.loadNullTicketsConfig(allocator, paths, name) catch null orelse return helpers.notFound();
        defer integration_mod.deinitNullTicketsConfig(allocator, &tickets_cfg);
        const boilers = listNullBoilersLocked(allocator, mutex, s, paths) catch return helpers.serverError();
        defer integration_mod.deinitNullBoilerConfigs(allocator, boilers);

        var linked_boilers = std.ArrayListUnmanaged(struct {
            name: []const u8,
            port: u16,
            tracker: ?std.json.Value = null,
        }){};
        defer linked_boilers.deinit(allocator);

        for (boilers) |boiler| {
            const linked = integration_mod.matchNullTicketsTarget(boiler, &.{tickets_cfg}) orelse continue;
            _ = linked;
            const tracker_value = blk: {
                const status = getStatusLocked(mutex, manager, "nullboiler", boiler.name) orelse break :blk null;
                if (status.status != .running) break :blk null;
                const url = command_service.buildInstanceUrl(allocator, boiler.port, "/tracker/status") orelse break :blk null;
                defer allocator.free(url);
                break :blk command_service.fetchJsonValue(allocator, url, boiler.api_token);
            };
            linked_boilers.append(allocator, .{
                .name = boiler.name,
                .port = boiler.port,
                .tracker = tracker_value,
            }) catch return helpers.serverError();
        }

        const queue = blk: {
            const status = getStatusLocked(mutex, manager, "nulltickets", name) orelse break :blk null;
            if (status.status != .running) break :blk null;
            const url = command_service.buildInstanceUrl(allocator, tickets_cfg.port, "/ops/queue") orelse break :blk null;
            defer allocator.free(url);
            break :blk command_service.fetchJsonValue(allocator, url, tickets_cfg.api_token);
        };

        const body = std.json.Stringify.valueAlloc(allocator, .{
            .kind = "nulltickets",
            .queue = queue,
            .linked_boilers = linked_boilers.items,
        }, .{ .emit_null_optional_fields = false }) catch return helpers.serverError();
        return helpers.jsonOk(body);
    }

    return helpers.notFound();
}

pub fn handlePost(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    manager: *manager_mod.Manager,
    mutex: *std.Thread.Mutex,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    body: []const u8,
) ApiResponse {
    if (!std.mem.eql(u8, component, "nullboiler")) return helpers.badRequest("{\"error\":\"integration updates are only supported for nullboiler\"}");

    const tracker_cfg = blk: {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }) catch return helpers.badRequest("{\"error\":\"invalid JSON body\"}");
        defer parsed.deinit();
        if (parsed.value != .object) return helpers.badRequest("{\"error\":\"invalid JSON body\"}");
        const tracker_name = if (parsed.value.object.get("tracker_instance")) |value|
            if (value == .string and value.string.len > 0) value.string else null
        else
            null;
        if (tracker_name == null) return helpers.badRequest("{\"error\":\"tracker_instance is required\"}");
        const pipeline_id = if (parsed.value.object.get("pipeline_id")) |value|
            if (value == .string and value.string.len > 0) value.string else null
        else
            null;
        if (pipeline_id == null) return helpers.badRequest("{\"error\":\"pipeline_id is required\"}");
        const cfg = integration_mod.loadNullTicketsConfig(allocator, paths, tracker_name.?) catch null orelse return helpers.notFound();
        errdefer {
            var owned_cfg = cfg;
            integration_mod.deinitNullTicketsConfig(allocator, &owned_cfg);
        }
        const pipeline_id_owned = allocator.dupe(u8, pipeline_id.?) catch return helpers.serverError();
        errdefer allocator.free(pipeline_id_owned);
        const claim_role_value = if (parsed.value.object.get("claim_role")) |value|
            if (value == .string and value.string.len > 0) value.string else "coder"
        else
            "coder";
        const claim_role_owned = allocator.dupe(u8, claim_role_value) catch return helpers.serverError();
        errdefer allocator.free(claim_role_owned);
        const success_trigger_value = if (parsed.value.object.get("success_trigger")) |value|
            if (value == .string and value.string.len > 0) value.string else "complete"
        else
            "complete";
        const success_trigger_owned = allocator.dupe(u8, success_trigger_value) catch return helpers.serverError();
        errdefer allocator.free(success_trigger_owned);
        break :blk .{
            .tickets = cfg,
            .pipeline_id = pipeline_id_owned,
            .claim_role = claim_role_owned,
            .success_trigger = success_trigger_owned,
            .max_concurrent_tasks = if (parsed.value.object.get("max_concurrent_tasks")) |value|
                switch (value) {
                    .integer => if (value.integer > 0 and value.integer <= std.math.maxInt(u32)) @as(?u32, @intCast(value.integer)) else null,
                    .string => std.fmt.parseInt(u32, value.string, 10) catch null,
                    else => null,
                }
            else
                null,
        };
    };
    defer {
        var owned_cfg = tracker_cfg.tickets;
        integration_mod.deinitNullTicketsConfig(allocator, &owned_cfg);
        allocator.free(tracker_cfg.pipeline_id);
        allocator.free(tracker_cfg.claim_role);
        allocator.free(tracker_cfg.success_trigger);
    }

    var existing = integration_mod.loadNullBoilerConfig(allocator, paths, name) catch null orelse return helpers.notFound();
    defer integration_mod.deinitNullBoilerConfig(allocator, &existing);

    const tracker_runtime = getStatusLocked(mutex, manager, "nulltickets", tracker_cfg.tickets.name);
    if (tracker_runtime != null and tracker_runtime.?.status == .running) {
        const pipelines_url = command_service.buildInstanceUrl(allocator, tracker_cfg.tickets.port, "/pipelines") orelse return helpers.serverError();
        defer allocator.free(pipelines_url);
        if (fetchPipelineSummaries(allocator, pipelines_url, tracker_cfg.tickets.api_token)) |pipelines| {
            defer deinitPipelineSummaries(allocator, pipelines);
            var matched = false;
            for (pipelines) |pipeline| {
                if (!std.mem.eql(u8, pipeline.id, tracker_cfg.pipeline_id)) continue;
                matched = true;
                if (pipeline.roles.len > 0 and !pipelineContainsString(pipeline.roles, tracker_cfg.claim_role)) {
                    return helpers.badRequest("{\"error\":\"claim_role is not valid for the selected pipeline\"}");
                }
                if (pipeline.triggers.len > 0 and !pipelineContainsString(pipeline.triggers, tracker_cfg.success_trigger)) {
                    return helpers.badRequest("{\"error\":\"success_trigger is not valid for the selected pipeline\"}");
                }
                break;
            }
            if (!matched) {
                return helpers.badRequest("{\"error\":\"pipeline_id was not found in the selected tracker\"}");
            }
        }
    }

    const config_path = paths.instanceConfig(allocator, "nullboiler", name) catch return helpers.serverError();
    defer allocator.free(config_path);
    const file = std.fs.openFileAbsolute(config_path, .{}) catch return helpers.serverError();
    defer file.close();
    const config_bytes = file.readToEndAlloc(allocator, 1024 * 1024) catch return helpers.serverError();
    defer allocator.free(config_bytes);

    var parsed_config = std.json.parseFromSlice(std.json.Value, allocator, config_bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return helpers.serverError();
    defer parsed_config.deinit();
    if (parsed_config.value != .object) return helpers.serverError();
    const arena = parsed_config.arena.allocator();

    const tracker_map = ensureObjectField(arena, &parsed_config.value.object, "tracker") catch return helpers.serverError();
    const tracker_url = std.fmt.allocPrint(arena, "http://127.0.0.1:{d}", .{tracker_cfg.tickets.port}) catch return helpers.serverError();
    tracker_map.put("url", .{ .string = tracker_url }) catch return helpers.serverError();
    if (tracker_cfg.tickets.api_token) |token| {
        tracker_map.put("api_token", .{ .string = token }) catch return helpers.serverError();
    } else {
        _ = tracker_map.swapRemove("api_token");
    }
    if (jsonString(tracker_map.*, "agent_id")) |agent_id| {
        if (agent_id.len == 0) {
            tracker_map.put("agent_id", .{ .string = if (existing.tracker) |tracker| tracker.agent_id else name }) catch return helpers.serverError();
        }
    } else {
        tracker_map.put("agent_id", .{ .string = if (existing.tracker) |tracker| tracker.agent_id else name }) catch return helpers.serverError();
    }
    if (jsonString(tracker_map.*, "workflows_dir")) |workflows_dir| {
        if (workflows_dir.len == 0) {
            tracker_map.put("workflows_dir", .{ .string = "workflows" }) catch return helpers.serverError();
        }
    } else {
        tracker_map.put("workflows_dir", .{ .string = "workflows" }) catch return helpers.serverError();
    }

    const concurrency_map = ensureObjectField(arena, tracker_map, "concurrency") catch return helpers.serverError();
    if (tracker_cfg.max_concurrent_tasks) |max_concurrent_tasks| {
        concurrency_map.put("max_concurrent_tasks", .{ .integer = max_concurrent_tasks }) catch return helpers.serverError();
    } else if (concurrency_map.get("max_concurrent_tasks") == null) {
        concurrency_map.put("max_concurrent_tasks", .{ .integer = if (existing.tracker) |tracker| tracker.max_concurrent_tasks else 1 }) catch return helpers.serverError();
    }

    const workflows_dir_value = jsonStringOrEmpty(tracker_map.*, "workflows_dir");
    const rendered = std.json.Stringify.valueAlloc(allocator, parsed_config.value, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    }) catch return helpers.serverError();
    defer allocator.free(rendered);

    const out = std.fs.createFileAbsolute(config_path, .{ .truncate = true }) catch return helpers.serverError();
    defer out.close();
    out.writeAll(rendered) catch return helpers.serverError();
    out.writeAll("\n") catch return helpers.serverError();

    const workflows_dir = resolvePathFromConfig(allocator, config_path, workflows_dir_value) catch return helpers.serverError();
    defer allocator.free(workflows_dir);

    ensureTrackerWorkflowFile(
        allocator,
        config_path,
        workflows_dir,
        if (existing.tracker) |tracker| if (tracker.workflow) |workflow| workflow.file_name else null else null,
        tracker_cfg.pipeline_id,
        tracker_cfg.claim_role,
        tracker_cfg.success_trigger,
    ) catch return helpers.serverError();

    if (getStatusLocked(mutex, manager, "nullboiler", name)) |status| {
        if (status.status == .running) {
            mutex.lock();
            defer mutex.unlock();
            return lifecycle.handleRestart(allocator, s, manager, paths, "nullboiler", name, "");
        }
    }

    return helpers.jsonOk("{\"status\":\"linked\"}");
}

test "dispatch routes GET integration action for linked nullboiler" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = @import("../instances.zig").TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nulltickets", "tracker-a", .{ .version = "1.0.0" });
    try s.addInstance("nullboiler", "boiler-a", .{ .version = "1.0.0" });

    try @import("../instances.zig").writeTestInstanceConfig(allocator, mctx.paths, "nulltickets", "tracker-a", "{\"port\":7711,\"api_token\":\"admin-token\"}");
    try @import("../instances.zig").writeTestInstanceConfig(
        allocator,
        mctx.paths,
        "nullboiler",
        "boiler-a",
        "{\"port\":8811,\"tracker\":{\"url\":\"http://127.0.0.1:7711\",\"api_token\":\"admin-token\",\"agent_id\":\"boiler-a\",\"workflows_dir\":\"workflows\",\"concurrency\":{\"max_concurrent_tasks\":2}}}",
    );
    try @import("../instances.zig").writeTestTrackerWorkflow(allocator, mctx.paths, "boiler-a", "dev-tasks.json", "pipe-dev", "reviewer", "complete");

    const resp = handleGet(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "nullboiler", "boiler-a");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("nullboiler", parsed.value.object.get("kind").?.string);
    const linked = parsed.value.object.get("linked_tracker").?.object;
    try std.testing.expectEqualStrings("tracker-a", linked.get("name").?.string);
    try std.testing.expectEqual(@as(i64, 7711), linked.get("port").?.integer);
    const current_link = parsed.value.object.get("current_link").?.object;
    try std.testing.expectEqualStrings("pipe-dev", current_link.get("pipeline_id").?.string);
    try std.testing.expectEqualStrings("reviewer", current_link.get("claim_role").?.string);
    try std.testing.expectEqualStrings("complete", current_link.get("success_trigger").?.string);
    try std.testing.expectEqual(@as(i64, 2), current_link.get("max_concurrent_tasks").?.integer);
}

test "dispatch routes POST integration action for nullboiler" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = @import("../instances.zig").TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nulltickets", "tracker-a", .{ .version = "1.0.0" });
    try s.addInstance("nullboiler", "boiler-a", .{ .version = "1.0.0" });

    try @import("../instances.zig").writeTestInstanceConfig(allocator, mctx.paths, "nulltickets", "tracker-a", "{\"port\":7711,\"api_token\":\"admin-token\"}");
    try @import("../instances.zig").writeTestInstanceConfig(allocator, mctx.paths, "nullboiler", "boiler-a", "{\"port\":8811}");

    const resp = handlePost(
        allocator,
        &s,
        &mctx.manager,
        &mctx.mutex,
        mctx.paths,
        "nullboiler",
        "boiler-a",
        "{\"tracker_instance\":\"tracker-a\",\"pipeline_id\":\"pipe-dev\",\"claim_role\":\"reviewer\",\"success_trigger\":\"complete\",\"max_concurrent_tasks\":3}",
    );
    try std.testing.expectEqualStrings("200 OK", resp.status);

    const config_path = try mctx.paths.instanceConfig(allocator, "nullboiler", "boiler-a");
    defer allocator.free(config_path);
    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();
    const config_bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, config_bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const tracker = parsed.value.object.get("tracker").?.object;
    try std.testing.expectEqualStrings("http://127.0.0.1:7711", tracker.get("url").?.string);
    try std.testing.expectEqualStrings("admin-token", tracker.get("api_token").?.string);
    try std.testing.expectEqualStrings("workflows", tracker.get("workflows_dir").?.string);
    const concurrency = tracker.get("concurrency").?.object;
    try std.testing.expectEqual(@as(i64, 3), concurrency.get("max_concurrent_tasks").?.integer);

    const workflow_path = try std.fs.path.join(allocator, &.{ mctx.paths.root, "instances", "nullboiler", "boiler-a", "workflows", integration_mod.managed_workflow_file_name });
    defer allocator.free(workflow_path);
    const workflow_file = try std.fs.openFileAbsolute(workflow_path, .{});
    defer workflow_file.close();
    const workflow = try workflow_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(workflow);
    try std.testing.expect(std.mem.indexOf(u8, workflow, "\"pipeline_id\": \"pipe-dev\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, workflow, "\"claim_roles\": [\n    \"reviewer\"\n  ]") != null);
    try std.testing.expect(std.mem.indexOf(u8, workflow, "\"transition_to\": \"complete\"") != null);
}

test "dispatch integration relink preserves advanced tracker config and custom workflows" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = @import("../instances.zig").TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nulltickets", "tracker-a", .{ .version = "1.0.0" });
    try s.addInstance("nullboiler", "boiler-a", .{ .version = "1.0.0" });

    try @import("../instances.zig").writeTestInstanceConfig(allocator, mctx.paths, "nulltickets", "tracker-a", "{\"port\":7711,\"api_token\":\"admin-token\"}");
    try @import("../instances.zig").writeTestInstanceConfig(
        allocator,
        mctx.paths,
        "nullboiler",
        "boiler-a",
        "{\"port\":8811,\"tracker\":{\"url\":\"http://127.0.0.1:7701\",\"api_token\":\"stale-token\",\"agent_id\":\"custom-agent\",\"workflows_dir\":\"custom-workflows\",\"poll_interval_ms\":9000,\"lease_ttl_ms\":222000,\"heartbeat_interval_ms\":44000,\"workspace\":{\"root\":\"../workspaces\"},\"subprocess\":{\"base_port\":9300},\"concurrency\":{\"max_concurrent_tasks\":7,\"per_pipeline\":{\"pipe-old\":2}}}}",
    );

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullboiler", "boiler-a");
    defer allocator.free(inst_dir);
    const workflows_dir = try std.fs.path.join(allocator, &.{ inst_dir, "custom-workflows" });
    defer allocator.free(workflows_dir);
    try ensurePath(workflows_dir);

    const custom_workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, "manual.json" });
    defer allocator.free(custom_workflow_path);
    {
        const file = try std.fs.createFileAbsolute(custom_workflow_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\{
            \\  "id": "wf-manual",
            \\  "pipeline_id": "pipe-manual",
            \\  "claim_roles": ["reviewer"],
            \\  "execution": "subprocess",
            \\  "prompt_template": "Manual workflow",
            \\  "on_success": { "transition_to": "approved" }
            \\}
            \\
        );
    }

    const generated_workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, "pipe-old.json" });
    defer allocator.free(generated_workflow_path);
    {
        const rendered = try std.json.Stringify.valueAlloc(allocator, .{
            .id = "wf-pipe-old-coder",
            .pipeline_id = "pipe-old",
            .claim_roles = &.{"coder"},
            .execution = "subprocess",
            .prompt_template = default_tracker_prompt_template,
            .on_success = .{
                .transition_to = "complete",
            },
        }, .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = false,
        });
        defer allocator.free(rendered);

        const file = try std.fs.createFileAbsolute(generated_workflow_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(rendered);
        try file.writeAll("\n");
    }

    const resp = handlePost(
        allocator,
        &s,
        &mctx.manager,
        &mctx.mutex,
        mctx.paths,
        "nullboiler",
        "boiler-a",
        "{\"tracker_instance\":\"tracker-a\",\"pipeline_id\":\"pipe-dev\",\"claim_role\":\"reviewer\",\"success_trigger\":\"complete\"}",
    );
    try std.testing.expectEqualStrings("200 OK", resp.status);

    const config_path = try mctx.paths.instanceConfig(allocator, "nullboiler", "boiler-a");
    defer allocator.free(config_path);
    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();
    const config_bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, config_bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const tracker = parsed.value.object.get("tracker").?.object;
    try std.testing.expectEqualStrings("http://127.0.0.1:7711", tracker.get("url").?.string);
    try std.testing.expectEqualStrings("admin-token", tracker.get("api_token").?.string);
    try std.testing.expectEqualStrings("custom-agent", tracker.get("agent_id").?.string);
    try std.testing.expectEqualStrings("custom-workflows", tracker.get("workflows_dir").?.string);
    try std.testing.expectEqual(@as(i64, 9000), tracker.get("poll_interval_ms").?.integer);
    try std.testing.expectEqual(@as(i64, 222000), tracker.get("lease_ttl_ms").?.integer);
    try std.testing.expectEqual(@as(i64, 44000), tracker.get("heartbeat_interval_ms").?.integer);
    try std.testing.expect(tracker.get("workspace") != null);
    try std.testing.expect(tracker.get("subprocess") != null);

    const concurrency = tracker.get("concurrency").?.object;
    try std.testing.expectEqual(@as(i64, 7), concurrency.get("max_concurrent_tasks").?.integer);
    try std.testing.expect(concurrency.get("per_pipeline") != null);

    const managed_workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, integration_mod.managed_workflow_file_name });
    defer allocator.free(managed_workflow_path);
    const managed_file = try std.fs.openFileAbsolute(managed_workflow_path, .{});
    managed_file.close();

    const custom_file = try std.fs.openFileAbsolute(custom_workflow_path, .{});
    custom_file.close();

    try std.testing.expectError(error.FileNotFound, std.fs.openFileAbsolute(generated_workflow_path, .{}));
}

fn ensureTrackerWorkflowFile(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    workflows_dir: []const u8,
    previous_workflow_file: ?[]const u8,
    pipeline_id: []const u8,
    claim_role: []const u8,
    success_trigger: []const u8,
) !void {
    try ensurePath(workflows_dir);

    var workflows_handle = try std.fs.openDirAbsolute(workflows_dir, .{ .iterate = true });
    defer workflows_handle.close();
    var workflows_it = workflows_handle.iterate();
    while (try workflows_it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        if (std.mem.eql(u8, entry.name, integration_mod.managed_workflow_file_name)) continue;

        const candidate_path = try std.fs.path.join(allocator, &.{ workflows_dir, entry.name });
        const managed = isNullHubXManagedWorkflow(allocator, candidate_path);
        if (managed) {
            std.fs.deleteFileAbsolute(candidate_path) catch {};
        }
        allocator.free(candidate_path);
    }

    if (previous_workflow_file) |file_name| {
        if (!std.mem.eql(u8, file_name, integration_mod.managed_workflow_file_name)) {
            const previous_path = try std.fs.path.join(allocator, &.{ workflows_dir, file_name });
            defer allocator.free(previous_path);
            if (isNullHubXManagedWorkflow(allocator, previous_path)) {
                std.fs.deleteFileAbsolute(previous_path) catch {};
            }
        }
    }

    const config_dir = std.fs.path.dirname(config_path) orelse return error.InvalidPath;
    const legacy_path = try std.fs.path.join(allocator, &.{ config_dir, integration_mod.legacy_workflow_file_name });
    defer allocator.free(legacy_path);
    std.fs.deleteFileAbsolute(legacy_path) catch {};

    const legacy_workflows_path = try std.fs.path.join(allocator, &.{ workflows_dir, integration_mod.legacy_workflow_file_name });
    defer allocator.free(legacy_workflows_path);
    std.fs.deleteFileAbsolute(legacy_workflows_path) catch {};

    const workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, integration_mod.managed_workflow_file_name });
    defer allocator.free(workflow_path);

    const workflow_id = try std.fmt.allocPrint(allocator, "wf-{s}-{s}", .{ pipeline_id, claim_role });
    defer allocator.free(workflow_id);
    const rendered = try std.json.Stringify.valueAlloc(allocator, .{
        .id = workflow_id,
        .pipeline_id = pipeline_id,
        .claim_roles = &.{claim_role},
        .execution = "subprocess",
        .prompt_template = default_tracker_prompt_template,
        .on_success = .{
            .transition_to = success_trigger,
        },
    }, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    });
    defer allocator.free(rendered);

    const file_out = try std.fs.createFileAbsolute(workflow_path, .{ .truncate = true });
    defer file_out.close();
    try file_out.writeAll(rendered);
    try file_out.writeAll("\n");
}
