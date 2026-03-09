const std = @import("std");
const paths_mod = @import("paths.zig");
const state_mod = @import("state.zig");

pub const NullTicketsConfig = struct {
    name: []const u8,
    port: u16 = 7700,
    api_token: ?[]const u8 = null,
};

pub const NullBoilerTrackerConfig = struct {
    url: []const u8,
    api_token: ?[]const u8 = null,
    agent_id: []const u8 = "nullboiler",
    agent_role: []const u8 = "coder",
    workflow_path: []const u8 = "tracker-workflow.json",
    success_trigger: ?[]const u8 = null,
    max_concurrent_tasks: u32 = 1,
};

pub const NullBoilerConfig = struct {
    name: []const u8,
    port: u16 = 8080,
    api_token: ?[]const u8 = null,
    tracker: ?NullBoilerTrackerConfig = null,
};

pub fn listNullTickets(allocator: std.mem.Allocator, state: *state_mod.State, paths: paths_mod.Paths) ![]NullTicketsConfig {
    const names = try state.instanceNames("nulltickets") orelse return allocator.alloc(NullTicketsConfig, 0);
    var list: std.ArrayListUnmanaged(NullTicketsConfig) = .empty;
    errdefer deinitNullTicketsConfigs(allocator, list.items);
    defer list.deinit(allocator);

    for (names) |name| {
        if (try loadNullTicketsConfig(allocator, paths, name)) |cfg| {
            var owned = cfg;
            errdefer deinitNullTicketsConfig(allocator, &owned);
            try list.append(allocator, owned);
        }
    }

    return list.toOwnedSlice(allocator);
}

pub fn listNullBoilers(allocator: std.mem.Allocator, state: *state_mod.State, paths: paths_mod.Paths) ![]NullBoilerConfig {
    const names = try state.instanceNames("nullboiler") orelse return allocator.alloc(NullBoilerConfig, 0);
    var list: std.ArrayListUnmanaged(NullBoilerConfig) = .empty;
    errdefer deinitNullBoilerConfigs(allocator, list.items);
    defer list.deinit(allocator);

    for (names) |name| {
        if (try loadNullBoilerConfig(allocator, paths, name)) |cfg| {
            var owned = cfg;
            errdefer deinitNullBoilerConfig(allocator, &owned);
            try list.append(allocator, owned);
        }
    }

    return list.toOwnedSlice(allocator);
}

pub fn loadNullTicketsConfig(allocator: std.mem.Allocator, paths: paths_mod.Paths, name: []const u8) !?NullTicketsConfig {
    const config_path = paths.instanceConfig(allocator, "nulltickets", name) catch return null;
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = std.json.parseFromSlice(NullTicketsConfigFile, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    return .{
        .name = try allocator.dupe(u8, name),
        .port = parsed.value.port,
        .api_token = if (parsed.value.api_token) |token| try allocator.dupe(u8, token) else null,
    };
}

pub fn loadNullBoilerConfig(allocator: std.mem.Allocator, paths: paths_mod.Paths, name: []const u8) !?NullBoilerConfig {
    const config_path = paths.instanceConfig(allocator, "nullboiler", name) catch return null;
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = std.json.parseFromSlice(NullBoilerConfigFile, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    return .{
        .name = try allocator.dupe(u8, name),
        .port = parsed.value.port,
        .api_token = if (parsed.value.api_token) |token| try allocator.dupe(u8, token) else null,
        .tracker = if (parsed.value.tracker) |tracker| .{
            .url = try allocator.dupe(u8, tracker.url),
            .api_token = if (tracker.api_token) |token| try allocator.dupe(u8, token) else null,
            .agent_id = try allocator.dupe(u8, tracker.agent_id),
            .agent_role = try allocator.dupe(u8, tracker.agent_role),
            .workflow_path = try allocator.dupe(u8, tracker.workflow_path),
            .success_trigger = if (tracker.success_trigger) |trigger| try allocator.dupe(u8, trigger) else null,
            .max_concurrent_tasks = tracker.max_concurrent_tasks,
        } else null,
    };
}

pub fn deinitNullTicketsConfig(allocator: std.mem.Allocator, cfg: *NullTicketsConfig) void {
    allocator.free(cfg.name);
    if (cfg.api_token) |token| allocator.free(token);
    cfg.* = undefined;
}

pub fn deinitNullTicketsConfigs(allocator: std.mem.Allocator, configs: []NullTicketsConfig) void {
    for (configs) |*cfg| deinitNullTicketsConfig(allocator, cfg);
    allocator.free(configs);
}

pub fn deinitNullBoilerConfig(allocator: std.mem.Allocator, cfg: *NullBoilerConfig) void {
    allocator.free(cfg.name);
    if (cfg.api_token) |token| allocator.free(token);
    if (cfg.tracker) |*tracker| {
        allocator.free(tracker.url);
        if (tracker.api_token) |token| allocator.free(token);
        allocator.free(tracker.agent_id);
        allocator.free(tracker.agent_role);
        allocator.free(tracker.workflow_path);
        if (tracker.success_trigger) |trigger| allocator.free(trigger);
    }
    cfg.* = undefined;
}

pub fn deinitNullBoilerConfigs(allocator: std.mem.Allocator, configs: []NullBoilerConfig) void {
    for (configs) |*cfg| deinitNullBoilerConfig(allocator, cfg);
    allocator.free(configs);
}

pub fn matchNullTicketsTarget(boiler_cfg: NullBoilerConfig, tickets: []const NullTicketsConfig) ?NullTicketsConfig {
    const tracker = boiler_cfg.tracker orelse return null;
    const tracker_port = extractLocalPort(tracker.url) orelse return null;

    for (tickets) |ticket| {
        if (ticket.port == tracker_port) return ticket;
    }
    return null;
}

pub fn countLinkedBoilersForTickets(tickets_cfg: NullTicketsConfig, boilers: []const NullBoilerConfig) usize {
    var count: usize = 0;
    for (boilers) |boiler| {
        const target = matchNullTicketsTarget(boiler, &.{tickets_cfg}) orelse continue;
        _ = target;
        count += 1;
    }
    return count;
}

pub fn extractLocalPort(url: []const u8) ?u16 {
    const uri = std.Uri.parse(url) catch return null;
    const host = uri.host orelse return null;
    const port = uri.port orelse return null;

    return switch (host) {
        .raw => |value| if (isLocalHost(value)) port else null,
        else => null,
    };
}

fn isLocalHost(host: []const u8) bool {
    return std.mem.eql(u8, host, "127.0.0.1") or
        std.mem.eql(u8, host, "localhost") or
        std.mem.eql(u8, host, "0.0.0.0") or
        std.mem.eql(u8, host, "::1");
}

const NullTicketsConfigFile = struct {
    port: u16 = 7700,
    api_token: ?[]const u8 = null,
};

const NullBoilerConfigFile = struct {
    port: u16 = 8080,
    api_token: ?[]const u8 = null,
    tracker: ?struct {
        url: []const u8,
        api_token: ?[]const u8 = null,
        agent_id: []const u8 = "nullboiler",
        agent_role: []const u8 = "coder",
        workflow_path: []const u8 = "tracker-workflow.json",
        success_trigger: ?[]const u8 = null,
        max_concurrent_tasks: u32 = 1,
    } = null,
};
