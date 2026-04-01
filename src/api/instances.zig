const std = @import("std");
const builtin = @import("builtin");
const state_mod = @import("../core/state.zig");
const manager_mod = @import("../supervisor/manager.zig");
const command_service = @import("../core/component_command_service.zig");
const paths_mod = @import("../core/paths.zig");
const helpers = @import("helpers.zig");
const local_binary = @import("../core/local_binary.zig");
const component_cli = @import("../core/component_cli.zig");
const integration_mod = @import("../core/integration.zig");
const launch_args_mod = @import("../core/launch_args.zig");
const managed_skills = @import("../managed_skills.zig");
const manifest_mod = @import("../core/manifest.zig");
const nullclaw_web_channel = @import("../core/nullclaw_web_channel.zig");
const bridge_mod = @import("instances/bridge.zig");

const ApiResponse = helpers.ApiResponse;
const appendEscaped = helpers.appendEscaped;
const jsonOk = helpers.jsonOk;
const notFound = helpers.notFound;
const badRequest = helpers.badRequest;
const methodNotAllowed = helpers.methodNotAllowed;

const default_tracker_prompt_template =
    "Task {{task.id}}: {{task.title}}\n\n{{task.description}}\n\nMetadata:\n{{task.metadata}}";

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Read a port value from an instance's config.json using a dot-separated key
/// (e.g. "gateway.port" → config["gateway"]["port"]).
fn readPortFromConfig(allocator: std.mem.Allocator, paths: paths_mod.Paths, component: []const u8, name: []const u8, dot_key: []const u8) ?u16 {
    const config_path = paths.instanceConfig(allocator, component, name) catch return null;
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();
    const contents = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch return null;
    defer allocator.free(contents);

    // Parse as generic JSON and walk the dot-path
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{
        .allocate = .alloc_always,
    }) catch return null;
    defer parsed.deinit();

    var current = parsed.value;
    var it = std.mem.splitScalar(u8, dot_key, '.');
    while (it.next()) |segment| {
        switch (current) {
            .object => |obj| {
                current = obj.get(segment) orelse return null;
            },
            else => return null,
        }
    }

    switch (current) {
        .integer => |v| return if (v >= 0 and v <= 65535) @intCast(v) else null,
        else => return null,
    }
}

fn fetchJsonValue(allocator: std.mem.Allocator, url: []const u8, bearer_token: ?[]const u8) ?std.json.Value {
    return command_service.fetchJsonValue(allocator, url, bearer_token);
}

fn buildInstanceUrl(allocator: std.mem.Allocator, port: u16, path: []const u8) ?[]const u8 {
    return command_service.buildInstanceUrl(allocator, port, path);
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

const NullclawOnboardingStatus = struct {
    supported: bool = false,
    pending: bool = false,
    completed: bool = false,
    bootstrap_exists: bool = false,
    bootstrap_seeded_at: ?[]u8 = null,
    onboarding_completed_at: ?[]u8 = null,

    fn deinit(self: *NullclawOnboardingStatus, allocator: std.mem.Allocator) void {
        if (self.bootstrap_seeded_at) |value| allocator.free(value);
        if (self.onboarding_completed_at) |value| allocator.free(value);
        self.* = .{};
    }
};

const NullclawBootstrapMemoryProbe = struct {
    exists: bool = false,
    timestamp: ?[]u8 = null,

    fn deinit(self: *NullclawBootstrapMemoryProbe, allocator: std.mem.Allocator) void {
        if (self.timestamp) |value| allocator.free(value);
        self.* = .{};
    }

    fn takeTimestamp(self: *NullclawBootstrapMemoryProbe) ?[]u8 {
        const value = self.timestamp;
        self.timestamp = null;
        return value;
    }
};

const nullclaw_bootstrap_memory_key = "__bootstrap.prompt.BOOTSTRAP.md";

fn fileExistsAbsolute(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn nullclawWorkspaceStatePath(allocator: std.mem.Allocator, workspace_dir: []const u8) ![]const u8 {
    return std.fs.path.join(allocator, &.{ workspace_dir, ".nullclaw", "workspace-state.json" });
}

fn probeNullclawBootstrapInMemory(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) NullclawBootstrapMemoryProbe {
    const entry = s.getInstance(component, name) orelse return .{};

    const bin_path = paths.binary(allocator, component, entry.version) catch return .{};
    defer allocator.free(bin_path);
    std.fs.accessAbsolute(bin_path, .{}) catch return .{};

    const inst_dir = paths.instanceDir(allocator, component, name) catch return .{};
    defer allocator.free(inst_dir);

    const args = [_][]const u8{
        "memory",
        "get",
        nullclaw_bootstrap_memory_key,
        "--json",
    };
    const result = component_cli.runWithComponentHome(
        allocator,
        component,
        bin_path,
        &args,
        null,
        inst_dir,
    ) catch return .{};
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (!result.success or !isLikelyJsonPayload(result.stdout)) return .{};

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{
        .allocate = .alloc_if_needed,
        .ignore_unknown_fields = true,
    }) catch return .{};
    defer parsed.deinit();

    switch (parsed.value) {
        .null => return .{},
        .object => |obj| {
            var probe = NullclawBootstrapMemoryProbe{ .exists = true };
            if (obj.get("timestamp")) |timestamp_value| {
                if (timestamp_value == .string and timestamp_value.string.len > 0) {
                    probe.timestamp = allocator.dupe(u8, timestamp_value.string) catch null;
                }
            }
            return probe;
        },
        else => return .{},
    }
}

fn readNullclawOnboardingStatus(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) !NullclawOnboardingStatus {
    var status = NullclawOnboardingStatus{};
    errdefer status.deinit(allocator);

    if (!std.mem.eql(u8, component, "nullclaw")) return status;
    status.supported = true;

    const inst_dir = try paths.instanceDir(allocator, component, name);
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);

    const bootstrap_path = try std.fs.path.join(allocator, &.{ workspace_dir, "BOOTSTRAP.md" });
    defer allocator.free(bootstrap_path);
    status.bootstrap_exists = fileExistsAbsolute(bootstrap_path);

    const state_path = try nullclawWorkspaceStatePath(allocator, workspace_dir);
    defer allocator.free(state_path);

    const state_file = std.fs.openFileAbsolute(state_path, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (state_file) |file| {
        defer file.close();
        const raw = file.readToEndAlloc(allocator, 64 * 1024) catch null;
        if (raw) |state_raw| {
            defer allocator.free(state_raw);
            const parsed = std.json.parseFromSlice(struct {
                bootstrap_seeded_at: ?[]const u8 = null,
                bootstrapSeededAt: ?[]const u8 = null,
                onboarding_completed_at: ?[]const u8 = null,
                onboardingCompletedAt: ?[]const u8 = null,
            }, allocator, state_raw, .{
                .allocate = .alloc_if_needed,
                .ignore_unknown_fields = true,
            }) catch null;
            if (parsed) |state_parsed| {
                defer state_parsed.deinit();
                if (state_parsed.value.bootstrap_seeded_at orelse state_parsed.value.bootstrapSeededAt) |seeded| {
                    status.bootstrap_seeded_at = try allocator.dupe(u8, seeded);
                }
                if (state_parsed.value.onboarding_completed_at orelse state_parsed.value.onboardingCompletedAt) |completed| {
                    status.onboarding_completed_at = try allocator.dupe(u8, completed);
                }
            }
        }
    }

    status.completed = status.onboarding_completed_at != null and !status.bootstrap_exists;

    var bootstrap_probe = NullclawBootstrapMemoryProbe{};
    if (!status.completed and !status.bootstrap_exists) {
        bootstrap_probe = probeNullclawBootstrapInMemory(allocator, s, paths, component, name);
        if (status.bootstrap_seeded_at == null) {
            status.bootstrap_seeded_at = bootstrap_probe.takeTimestamp();
        }
    }
    defer bootstrap_probe.deinit(allocator);

    status.pending = !status.completed and (status.bootstrap_exists or status.bootstrap_seeded_at != null or bootstrap_probe.exists);
    return status;
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

fn fetchPipelineSummaries(allocator: std.mem.Allocator, url: []const u8, bearer_token: ?[]const u8) ?[]PipelineSummary {
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

    const bytes = response_body.written();
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();
    if (parsed.value != .array) return null;

    var list: std.ArrayListUnmanaged(PipelineSummary) = .empty;
    errdefer deinitPipelineSummaries(allocator, list.items);
    defer list.deinit(allocator);

    for (parsed.value.array.items) |item| {
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

pub const ProviderHealthConfig = struct {
    agents: ?struct {
        defaults: ?struct {
            model: ?struct {
                primary: ?[]const u8 = null,
            } = null,
        } = null,
    } = null,
    models: ?struct {
        providers: ?std.json.ArrayHashMap(struct {
            api_key: ?[]const u8 = null,
            base_url: ?[]const u8 = null,
            api_url: ?[]const u8 = null,
        }) = null,
    } = null,
};

pub const ProviderProbeResult = struct {
    live_ok: bool,
    status_code: ?u16 = null,
    reason: []const u8,
};

fn parseAnyHttpStatusCode(s: []const u8) ?u16 {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (!std.ascii.isDigit(s[i])) continue;
        var j = i;
        while (j < s.len and std.ascii.isDigit(s[j])) : (j += 1) {}
        if (j - i == 3) {
            const code = std.fmt.parseInt(u16, s[i..j], 10) catch continue;
            if (code >= 100 and code <= 599) return code;
        }
        i = j;
    }
    return null;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var match = true;
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle[j])) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

fn isLocalEndpoint(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "http://localhost") or
        std.mem.startsWith(u8, url, "https://localhost") or
        std.mem.startsWith(u8, url, "http://127.") or
        std.mem.startsWith(u8, url, "https://127.") or
        std.mem.startsWith(u8, url, "http://0.0.0.0") or
        std.mem.startsWith(u8, url, "https://0.0.0.0") or
        std.mem.startsWith(u8, url, "http://[::1]") or
        std.mem.startsWith(u8, url, "https://[::1]");
}

fn knownCompatibleProviderUrl(provider_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, provider_name, "lmstudio") or std.mem.eql(u8, provider_name, "lm-studio")) {
        return "http://localhost:1234/v1";
    }
    if (std.mem.eql(u8, provider_name, "vllm")) return "http://localhost:8000/v1";
    if (std.mem.eql(u8, provider_name, "llamacpp") or std.mem.eql(u8, provider_name, "llama.cpp")) {
        return "http://localhost:8080/v1";
    }
    if (std.mem.eql(u8, provider_name, "sglang")) return "http://localhost:30000/v1";
    if (std.mem.eql(u8, provider_name, "osaurus")) return "http://localhost:1337/v1";
    if (std.mem.eql(u8, provider_name, "litellm")) return "http://localhost:4000";
    return null;
}

pub fn providerRequiresApiKey(provider_name: []const u8, base_url: ?[]const u8) bool {
    if (std.mem.eql(u8, provider_name, "ollama") or
        std.mem.eql(u8, provider_name, "claude-cli") or
        std.mem.eql(u8, provider_name, "codex-cli") or
        std.mem.eql(u8, provider_name, "openai-codex"))
    {
        return false;
    }

    if (base_url) |configured| return !isLocalEndpoint(configured);

    if (std.mem.startsWith(u8, provider_name, "custom:")) {
        return !isLocalEndpoint(provider_name["custom:".len..]);
    }

    if (knownCompatibleProviderUrl(provider_name)) |known_url| {
        return !isLocalEndpoint(known_url);
    }

    return true;
}

fn classifyProbeFailure(status_code: ?u16, stdout: []const u8, stderr: []const u8) ProviderProbeResult {
    if (status_code) |code| {
        return switch (code) {
            401 => .{ .live_ok = false, .status_code = code, .reason = "invalid_api_key" },
            403 => .{ .live_ok = false, .status_code = code, .reason = "forbidden" },
            429 => .{ .live_ok = false, .status_code = code, .reason = "rate_limited" },
            else => if (code >= 500 and code <= 599)
                .{ .live_ok = false, .status_code = code, .reason = "provider_unavailable" }
            else
                .{ .live_ok = false, .status_code = code, .reason = "auth_check_failed" },
        };
    }

    if (containsIgnoreCase(stderr, "unauthorized") or containsIgnoreCase(stdout, "unauthorized")) {
        return .{ .live_ok = false, .reason = "invalid_api_key" };
    }
    if (containsIgnoreCase(stderr, "forbidden") or containsIgnoreCase(stdout, "forbidden")) {
        return .{ .live_ok = false, .reason = "forbidden" };
    }
    if (containsIgnoreCase(stderr, "rate limit") or containsIgnoreCase(stdout, "rate limit") or
        containsIgnoreCase(stderr, "too many requests") or containsIgnoreCase(stdout, "too many requests"))
    {
        return .{ .live_ok = false, .reason = "rate_limited" };
    }
    if (containsIgnoreCase(stderr, "timeout") or containsIgnoreCase(stdout, "timeout") or
        containsIgnoreCase(stderr, "network") or containsIgnoreCase(stdout, "network") or
        containsIgnoreCase(stderr, "connection") or containsIgnoreCase(stdout, "connection"))
    {
        return .{ .live_ok = false, .reason = "network_error" };
    }
    return .{ .live_ok = false, .reason = "auth_check_failed" };
}

fn canonicalProbeReason(raw: ?[]const u8, live_ok: bool) []const u8 {
    const reason = raw orelse (if (live_ok) "ok" else "auth_check_failed");

    if (std.mem.eql(u8, reason, "ok")) return "ok";
    if (std.mem.eql(u8, reason, "invalid_api_key")) return "invalid_api_key";
    if (std.mem.eql(u8, reason, "missing_api_key")) return "missing_api_key";
    if (std.mem.eql(u8, reason, "provider_not_detected")) return "provider_not_detected";
    if (std.mem.eql(u8, reason, "instance_not_running")) return "instance_not_running";
    if (std.mem.eql(u8, reason, "rate_limited")) return "rate_limited";
    if (std.mem.eql(u8, reason, "forbidden")) return "forbidden";
    if (std.mem.eql(u8, reason, "provider_unavailable")) return "provider_unavailable";
    if (std.mem.eql(u8, reason, "network_error")) return "network_error";
    if (std.mem.eql(u8, reason, "provider_rejected")) return "provider_rejected";
    if (std.mem.eql(u8, reason, "probe_exec_failed")) return "probe_exec_failed";
    if (std.mem.eql(u8, reason, "probe_request_failed")) return "probe_request_failed";
    if (std.mem.eql(u8, reason, "config_load_failed")) return "config_load_failed";
    if (std.mem.eql(u8, reason, "component_binary_missing")) return "component_binary_missing";
    if (std.mem.eql(u8, reason, "component_probe_failed")) return "component_probe_failed";
    if (std.mem.eql(u8, reason, "probe_timeout")) return "probe_timeout";
    if (std.mem.eql(u8, reason, "probe_home_path_failed")) return "probe_home_path_failed";
    if (std.mem.eql(u8, reason, "invalid_probe_response")) return "invalid_probe_response";
    if (std.mem.eql(u8, reason, "auth_check_failed")) return "auth_check_failed";

    return if (live_ok) "ok" else "auth_check_failed";
}

const ComponentHealthProbePayload = struct {
    live_ok: bool = false,
    reason: ?[]const u8 = null,
    status_code: ?u16 = null,
};

fn probeProviderViaComponentHealth(
    allocator: std.mem.Allocator,
    component: []const u8,
    binary_path: []const u8,
    instance_home: []const u8,
    provider: []const u8,
    model: []const u8,
) ProviderProbeResult {
    const args: []const []const u8 = if (model.len > 0)
        &.{ "--probe-provider-health", "--provider", provider, "--model", model, "--timeout-secs", "10" }
    else
        &.{ "--probe-provider-health", "--provider", provider, "--timeout-secs", "10" };
    const result = component_cli.runWithComponentHome(
        allocator,
        component,
        binary_path,
        args,
        null,
        instance_home,
    ) catch return .{ .live_ok = false, .reason = "probe_exec_failed" };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const parsed = std.json.parseFromSlice(ComponentHealthProbePayload, allocator, result.stdout, .{
        .allocate = .alloc_if_needed,
        .ignore_unknown_fields = true,
    }) catch {
        const status_code = parseAnyHttpStatusCode(result.stderr) orelse parseAnyHttpStatusCode(result.stdout);
        return if (result.success)
            .{ .live_ok = false, .reason = "invalid_probe_response", .status_code = status_code }
        else
            classifyProbeFailure(status_code, result.stdout, result.stderr);
    };
    defer parsed.deinit();

    const payload = parsed.value;
    const reason = canonicalProbeReason(payload.reason, payload.live_ok);
    if (!result.success and payload.reason == null and !payload.live_ok) {
        const status_code = payload.status_code orelse parseAnyHttpStatusCode(result.stderr) orelse parseAnyHttpStatusCode(result.stdout);
        return classifyProbeFailure(status_code, result.stdout, result.stderr);
    }
    return .{
        .live_ok = payload.live_ok,
        .status_code = payload.status_code,
        .reason = reason,
    };
}

pub fn probeComponentProvider(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    entry: state_mod.InstanceEntry,
    component: []const u8,
    name: []const u8,
    provider: []const u8,
    model: []const u8,
) ProviderProbeResult {
    const bin_path = paths.binary(allocator, component, entry.version) catch {
        return .{ .live_ok = false, .reason = "probe_binary_path_failed" };
    };
    defer allocator.free(bin_path);

    std.fs.accessAbsolute(bin_path, .{}) catch return .{ .live_ok = false, .reason = "component_binary_missing" };
    const inst_dir = paths.instanceDir(allocator, component, name) catch return .{ .live_ok = false, .reason = "probe_home_path_failed" };
    defer allocator.free(inst_dir);
    return probeProviderViaComponentHealth(allocator, component, bin_path, inst_dir, provider, model);
}

// ─── Path Parsing ────────────────────────────────────────────────────────────

pub const ParsedPath = struct {
    component: []const u8,
    name: []const u8,
    action: ?[]const u8,
};

pub fn stripQuery(target: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, target, '?')) |qmark| {
        return target[0..qmark];
    }
    return target;
}

/// Parse `/api/instances/{component}/{name}` or
/// `/api/instances/{component}/{name}/{action}` from a request target.
/// Returns `null` if the path does not match the expected prefix or has
/// too few / too many segments.
pub fn parsePath(target: []const u8) ?ParsedPath {
    const clean = stripQuery(target);
    const prefix = "/api/instances/";
    if (!std.mem.startsWith(u8, clean, prefix)) return null;

    const rest = clean[prefix.len..];
    if (rest.len == 0) return null;

    var it = std.mem.splitScalar(u8, rest, '/');
    const component = it.next() orelse return null;
    if (component.len == 0) return null;

    const name = it.next() orelse return null;
    if (name.len == 0) return null;

    const action_raw = it.next();
    // If there is a fourth segment the path is invalid.
    if (it.next() != null) return null;

    const action: ?[]const u8 = if (action_raw) |a| (if (a.len == 0) null else a) else null;

    return .{ .component = component, .name = name, .action = action };
}

pub const UsageLedgerLine = struct {
    ts: i64 = 0,
    provider: ?[]const u8 = null,
    model: ?[]const u8 = null,
    prompt_tokens: u64 = 0,
    completion_tokens: u64 = 0,
    total_tokens: u64 = 0,
    success: bool = true,
};

pub const UsageAggregate = struct {
    provider: []const u8,
    model: []const u8,
    prompt_tokens: u64 = 0,
    completion_tokens: u64 = 0,
    total_tokens: u64 = 0,
    requests: u64 = 0,
    last_used: i64 = 0,
};

pub const TOKEN_USAGE_LEDGER_FILENAME = "llm_token_usage.jsonl";
pub const LEGACY_USAGE_LEDGER_FILENAME = "llm_usage.jsonl";
pub const USAGE_CACHE_VERSION: u32 = 1;
pub const USAGE_CACHE_MAX_LEDGER_BYTES: usize = 128 * 1024 * 1024;
pub const USAGE_HOURLY_RETENTION_SECS: i64 = 14 * 24 * 60 * 60;
pub const USAGE_DAILY_RETENTION_SECS: i64 = 730 * 24 * 60 * 60;
pub const HOUR_SECS: i64 = 60 * 60;
pub const DAY_SECS: i64 = 24 * 60 * 60;

pub const UsageCacheBucket = struct {
    bucket_start: i64 = 0,
    provider: []const u8 = "",
    model: []const u8 = "",
    prompt_tokens: u64 = 0,
    completion_tokens: u64 = 0,
    total_tokens: u64 = 0,
    requests: u64 = 0,
    last_used: i64 = 0,
};

pub const UsageCacheSnapshot = struct {
    version: u32 = USAGE_CACHE_VERSION,
    generated_at: i64 = 0,
    ledger_size: u64 = 0,
    ledger_mtime_ns: i64 = 0,
    hourly: []UsageCacheBucket = &.{},
    daily: []UsageCacheBucket = &.{},

    pub fn deinit(self: *UsageCacheSnapshot, allocator: std.mem.Allocator) void {
        for (self.hourly) |row| {
            allocator.free(row.provider);
            allocator.free(row.model);
        }
        if (self.hourly.len > 0) allocator.free(self.hourly);
        for (self.daily) |row| {
            allocator.free(row.provider);
            allocator.free(row.model);
        }
        if (self.daily.len > 0) allocator.free(self.daily);
        self.* = .{};
    }
};

pub fn emptyUsageCache(now_ts: i64) UsageCacheSnapshot {
    return .{ .generated_at = now_ts };
}

fn bucketFloor(ts: i64, bucket_secs: i64) i64 {
    return @divFloor(ts, bucket_secs) * bucket_secs;
}

pub fn isShortUsageWindow(window: []const u8) bool {
    return std.mem.eql(u8, window, "24h") or std.mem.eql(u8, window, "7d");
}

pub fn resolveUsageLedgerPath(allocator: std.mem.Allocator, inst_dir: []const u8) ![]u8 {
    const preferred = try std.fs.path.join(allocator, &.{ inst_dir, TOKEN_USAGE_LEDGER_FILENAME });
    std.fs.accessAbsolute(preferred, .{}) catch {
        const legacy = try std.fs.path.join(allocator, &.{ inst_dir, LEGACY_USAGE_LEDGER_FILENAME });
        if (std.fs.accessAbsolute(legacy, .{})) |_| {
            allocator.free(preferred);
            return legacy;
        } else |_| {}
        allocator.free(legacy);
    };
    return preferred;
}

pub fn usageCachePath(allocator: std.mem.Allocator, paths: paths_mod.Paths, component: []const u8, name: []const u8) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.json", .{name});
    defer allocator.free(filename);
    return std.fs.path.join(allocator, &.{ paths.root, "cache", "usage", component, filename });
}

fn parseI64(v: std.json.Value) ?i64 {
    return switch (v) {
        .integer => @intCast(v.integer),
        else => null,
    };
}

fn parseU64(v: std.json.Value) ?u64 {
    return switch (v) {
        .integer => if (v.integer >= 0) @intCast(v.integer) else null,
        else => null,
    };
}

fn parseU32(v: std.json.Value) ?u32 {
    return switch (v) {
        .integer => if (v.integer >= 0 and v.integer <= std.math.maxInt(u32)) @intCast(v.integer) else null,
        else => null,
    };
}

fn parseUsageCacheBuckets(allocator: std.mem.Allocator, value: std.json.Value) ![]UsageCacheBucket {
    if (value != .array) return allocator.alloc(UsageCacheBucket, 0);

    var list: std.ArrayListUnmanaged(UsageCacheBucket) = .empty;
    errdefer {
        for (list.items) |row| {
            allocator.free(row.provider);
            allocator.free(row.model);
        }
        list.deinit(allocator);
    }

    for (value.array.items) |item| {
        if (item != .object) continue;
        const provider_v = item.object.get("provider") orelse continue;
        const model_v = item.object.get("model") orelse continue;
        if (provider_v != .string or model_v != .string) continue;

        const provider_copy = try allocator.dupe(u8, provider_v.string);
        errdefer allocator.free(provider_copy);
        const model_copy = try allocator.dupe(u8, model_v.string);
        errdefer allocator.free(model_copy);

        try list.append(allocator, .{
            .bucket_start = if (item.object.get("bucket_start")) |v| parseI64(v) orelse 0 else 0,
            .provider = provider_copy,
            .model = model_copy,
            .prompt_tokens = if (item.object.get("prompt_tokens")) |v| parseU64(v) orelse 0 else 0,
            .completion_tokens = if (item.object.get("completion_tokens")) |v| parseU64(v) orelse 0 else 0,
            .total_tokens = if (item.object.get("total_tokens")) |v| parseU64(v) orelse 0 else 0,
            .requests = if (item.object.get("requests")) |v| parseU64(v) orelse 0 else 0,
            .last_used = if (item.object.get("last_used")) |v| parseI64(v) orelse 0 else 0,
        });
    }

    return list.toOwnedSlice(allocator);
}

pub fn loadUsageCacheSnapshot(allocator: std.mem.Allocator, cache_path: []const u8, now_ts: i64) !?UsageCacheSnapshot {
    const file = std.fs.openFileAbsolute(cache_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{
        .allocate = .alloc_if_needed,
    }) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;

    var snapshot = emptyUsageCache(now_ts);
    errdefer snapshot.deinit(allocator);

    const root = parsed.value.object;
    if (root.get("version")) |v| snapshot.version = parseU32(v) orelse USAGE_CACHE_VERSION;
    if (root.get("generated_at")) |v| snapshot.generated_at = parseI64(v) orelse now_ts;
    if (root.get("ledger_size")) |v| snapshot.ledger_size = parseU64(v) orelse 0;
    if (root.get("ledger_mtime_ns")) |v| snapshot.ledger_mtime_ns = parseI64(v) orelse 0;
    if (root.get("hourly")) |v| snapshot.hourly = try parseUsageCacheBuckets(allocator, v);
    if (root.get("daily")) |v| snapshot.daily = try parseUsageCacheBuckets(allocator, v);

    return snapshot;
}

fn writeUsageCacheBuckets(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    buckets: []const UsageCacheBucket,
) !void {
    _ = allocator;
    try w.writeByte('[');
    for (buckets, 0..) |row, idx| {
        if (idx > 0) try w.writeByte(',');
        try w.writeAll("{\"bucket_start\":");
        try w.print("{d}", .{row.bucket_start});
        try w.writeAll(",\"provider\":");
        try w.print("{f}", .{std.json.fmt(row.provider, .{})});
        try w.writeAll(",\"model\":");
        try w.print("{f}", .{std.json.fmt(row.model, .{})});
        try w.writeAll(",\"prompt_tokens\":");
        try w.print("{d}", .{row.prompt_tokens});
        try w.writeAll(",\"completion_tokens\":");
        try w.print("{d}", .{row.completion_tokens});
        try w.writeAll(",\"total_tokens\":");
        try w.print("{d}", .{row.total_tokens});
        try w.writeAll(",\"requests\":");
        try w.print("{d}", .{row.requests});
        try w.writeAll(",\"last_used\":");
        try w.print("{d}", .{row.last_used});
        try w.writeByte('}');
    }
    try w.writeByte(']');
}

pub fn writeUsageCacheSnapshot(allocator: std.mem.Allocator, cache_path: []const u8, snapshot: *const UsageCacheSnapshot) !void {
    const cache_dir = std.fs.path.dirname(cache_path) orelse return error.InvalidPath;
    std.fs.makeDirAbsolute(cache_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    var file = try std.fs.createFileAbsolute(cache_path, .{ .truncate = true });
    defer file.close();

    var writer_buf: [8192]u8 = undefined;
    var file_writer = file.writer(&writer_buf);
    const w = &file_writer.interface;

    try w.writeAll("{\"version\":");
    try w.print("{d}", .{snapshot.version});
    try w.writeAll(",\"generated_at\":");
    try w.print("{d}", .{snapshot.generated_at});
    try w.writeAll(",\"ledger_size\":");
    try w.print("{d}", .{snapshot.ledger_size});
    try w.writeAll(",\"ledger_mtime_ns\":");
    try w.print("{d}", .{snapshot.ledger_mtime_ns});
    try w.writeAll(",\"hourly\":");
    try writeUsageCacheBuckets(allocator, w, snapshot.hourly);
    try w.writeAll(",\"daily\":");
    try writeUsageCacheBuckets(allocator, w, snapshot.daily);
    try w.writeAll("}\n");
    try w.flush();
}

fn upsertUsageBucket(
    allocator: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(UsageCacheBucket),
    bucket_start: i64,
    provider: []const u8,
    model: []const u8,
    prompt_tokens: u64,
    completion_tokens: u64,
    total_tokens: u64,
    ts: i64,
) !void {
    for (list.items) |*row| {
        if (row.bucket_start == bucket_start and std.mem.eql(u8, row.provider, provider) and std.mem.eql(u8, row.model, model)) {
            row.prompt_tokens += prompt_tokens;
            row.completion_tokens += completion_tokens;
            row.total_tokens += total_tokens;
            row.requests += 1;
            if (ts > row.last_used) row.last_used = ts;
            return;
        }
    }

    try list.append(allocator, .{
        .bucket_start = bucket_start,
        .provider = try allocator.dupe(u8, provider),
        .model = try allocator.dupe(u8, model),
        .prompt_tokens = prompt_tokens,
        .completion_tokens = completion_tokens,
        .total_tokens = total_tokens,
        .requests = 1,
        .last_used = ts,
    });
}

fn pruneUsageBuckets(allocator: std.mem.Allocator, list: *std.ArrayListUnmanaged(UsageCacheBucket), min_bucket_start: i64) void {
    var i: usize = 0;
    while (i < list.items.len) {
        if (list.items[i].bucket_start < min_bucket_start) {
            allocator.free(list.items[i].provider);
            allocator.free(list.items[i].model);
            _ = list.swapRemove(i);
            continue;
        }
        i += 1;
    }
}

pub fn rebuildUsageCacheSnapshot(
    allocator: std.mem.Allocator,
    ledger_path: []const u8,
    ledger_size: u64,
    ledger_mtime_ns: i64,
    now_ts: i64,
) !UsageCacheSnapshot {
    var snapshot = emptyUsageCache(now_ts);
    snapshot.ledger_size = ledger_size;
    snapshot.ledger_mtime_ns = ledger_mtime_ns;

    var hourly_list: std.ArrayListUnmanaged(UsageCacheBucket) = .empty;
    errdefer {
        for (hourly_list.items) |row| {
            allocator.free(row.provider);
            allocator.free(row.model);
        }
        hourly_list.deinit(allocator);
    }
    var daily_list: std.ArrayListUnmanaged(UsageCacheBucket) = .empty;
    errdefer {
        for (daily_list.items) |row| {
            allocator.free(row.provider);
            allocator.free(row.model);
        }
        daily_list.deinit(allocator);
    }

    const file = std.fs.openFileAbsolute(ledger_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            snapshot.hourly = &.{};
            snapshot.daily = &.{};
            return snapshot;
        },
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, USAGE_CACHE_MAX_LEDGER_BYTES);
    defer allocator.free(contents);

    var line_it = std.mem.splitScalar(u8, contents, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(UsageLedgerLine, allocator, line, .{
            .allocate = .alloc_if_needed,
            .ignore_unknown_fields = true,
        }) catch continue;
        defer parsed.deinit();

        const record = parsed.value;
        if (record.ts <= 0) continue;

        const provider_raw = record.provider orelse "unknown";
        const model_raw = record.model orelse "unknown";
        const provider = if (provider_raw.len > 0) provider_raw else "unknown";
        const model = if (model_raw.len > 0) model_raw else "unknown";
        const total_tokens: u64 = if (record.total_tokens > 0)
            record.total_tokens
        else
            record.prompt_tokens + record.completion_tokens;

        try upsertUsageBucket(
            allocator,
            &hourly_list,
            bucketFloor(record.ts, HOUR_SECS),
            provider,
            model,
            record.prompt_tokens,
            record.completion_tokens,
            total_tokens,
            record.ts,
        );
        try upsertUsageBucket(
            allocator,
            &daily_list,
            bucketFloor(record.ts, DAY_SECS),
            provider,
            model,
            record.prompt_tokens,
            record.completion_tokens,
            total_tokens,
            record.ts,
        );
    }

    pruneUsageBuckets(allocator, &hourly_list, now_ts - USAGE_HOURLY_RETENTION_SECS);
    pruneUsageBuckets(allocator, &daily_list, now_ts - USAGE_DAILY_RETENTION_SECS);

    snapshot.hourly = try hourly_list.toOwnedSlice(allocator);
    snapshot.daily = try daily_list.toOwnedSlice(allocator);
    return snapshot;
}

pub fn parseUsageWindow(target: []const u8) []const u8 {
    const qmark = std.mem.indexOfScalar(u8, target, '?') orelse return "24h";
    const query = target[qmark + 1 ..];
    var params = std.mem.splitScalar(u8, query, '&');
    while (params.next()) |param| {
        if (!std.mem.startsWith(u8, param, "window=")) continue;
        const value = param["window=".len..];
        if (std.mem.eql(u8, value, "24h")) return "24h";
        if (std.mem.eql(u8, value, "7d")) return "7d";
        if (std.mem.eql(u8, value, "30d")) return "30d";
        if (std.mem.eql(u8, value, "all")) return "all";
    }
    return "24h";
}

pub fn usageWindowMinTs(window: []const u8, now_ts: i64) ?i64 {
    if (std.mem.eql(u8, window, "all")) return null;
    if (std.mem.eql(u8, window, "24h")) return now_ts - 24 * 60 * 60;
    if (std.mem.eql(u8, window, "7d")) return now_ts - 7 * 24 * 60 * 60;
    if (std.mem.eql(u8, window, "30d")) return now_ts - 30 * 24 * 60 * 60;
    return now_ts - 24 * 60 * 60;
}

fn queryParamRaw(target: []const u8, key: []const u8) ?[]const u8 {
    const qmark = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    const query = target[qmark + 1 ..];
    var params = std.mem.splitScalar(u8, query, '&');
    while (params.next()) |param| {
        if (param.len <= key.len) continue;
        if (!std.mem.startsWith(u8, param, key)) continue;
        if (param[key.len] != '=') continue;
        return param[key.len + 1 ..];
    }
    return null;
}

fn decodeQueryValueAlloc(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const encoded = try allocator.dupe(u8, raw);
    for (encoded) |*ch| {
        if (ch.* == '+') ch.* = ' ';
    }
    const decoded = std.Uri.percentDecodeInPlace(encoded);
    if (decoded.ptr == encoded.ptr and decoded.len == encoded.len) return encoded;
    const out = try allocator.dupe(u8, decoded);
    allocator.free(encoded);
    return out;
}

pub fn queryParamValueAlloc(allocator: std.mem.Allocator, target: []const u8, key: []const u8) !?[]u8 {
    const raw = queryParamRaw(target, key) orelse return null;
    const decoded = try decodeQueryValueAlloc(allocator, raw);
    return decoded;
}

pub fn queryParamBool(target: []const u8, key: []const u8) bool {
    const raw = queryParamRaw(target, key) orelse return false;
    return std.mem.eql(u8, raw, "1") or std.mem.eql(u8, raw, "true") or std.mem.eql(u8, raw, "yes");
}

pub fn queryParamUsize(target: []const u8, key: []const u8, default_value: usize) usize {
    const raw = queryParamRaw(target, key) orelse return default_value;
    return std.fmt.parseInt(usize, raw, 10) catch default_value;
}

fn isLikelyJsonPayload(bytes: []const u8) bool {
    return command_service.isLikelyJsonPayload(bytes);
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
    try appendEscaped(&buf, code);
    try buf.appendSlice("\",\"message\":\"");
    try appendEscaped(&buf, message);
    try buf.append('"');

    if (stderr) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len > 0) {
            try buf.appendSlice(",\"stderr\":\"");
            try appendEscaped(&buf, trimmed);
            try buf.append('"');
        }
    }

    if (stdout) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len > 0) {
            try buf.appendSlice(",\"stdout\":\"");
            try appendEscaped(&buf, trimmed);
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
    return jsonOk(body);
}

fn jsonCliConflict(
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

const CapturedInstanceCli = command_service.CapturedInstanceCli;

fn runInstanceCliCaptured(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    args: []const []const u8,
) CapturedInstanceCli {
    return command_service.runInstanceCliCaptured(allocator, s, paths, component, name, args);
}

fn runInstanceCliJson(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    args: []const []const u8,
) ApiResponse {
    return command_service.runInstanceCliJson(allocator, s, paths, component, name, args);
}

// ─── JSON helpers ────────────────────────────────────────────────────────────

fn appendInstanceJson(buf: *std.array_list.Managed(u8), entry: state_mod.InstanceEntry, status_str: []const u8) !void {
    try buf.appendSlice("{\"version\":\"");
    try appendEscaped(buf, entry.version);
    try buf.appendSlice("\",\"auto_start\":");
    try buf.appendSlice(if (entry.auto_start) "true" else "false");
    try buf.appendSlice(",\"launch_mode\":\"");
    try appendEscaped(buf, entry.launch_mode);
    try buf.appendSlice("\",\"verbose\":");
    try buf.appendSlice(if (entry.verbose) "true" else "false");
    try buf.appendSlice(",\"status\":\"");
    try buf.appendSlice(status_str);
    try buf.appendSlice("\"}");
}

// ─── Handlers ────────────────────────────────────────────────────────────────

/// GET /api/instances — list all instances grouped by component.
pub fn handleList(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager) ApiResponse {
    return @import("instances/lifecycle.zig").handleList(allocator, s, manager);
}

/// GET /api/instances/{component}/{name} — detail for one instance.
pub fn handleGet(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, component: []const u8, name: []const u8) ApiResponse {
    return @import("instances/lifecycle.zig").handleGet(allocator, s, manager, component, name);
}

/// POST /api/instances/{component}/{name}/start
pub fn handleStart(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, paths: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    return @import("instances/lifecycle.zig").handleStart(allocator, s, manager, paths, component, name, body);
}

/// POST /api/instances/{component}/{name}/stop
pub fn handleStop(s: *state_mod.State, manager: *manager_mod.Manager, component: []const u8, name: []const u8) ApiResponse {
    return @import("instances/lifecycle.zig").handleStop(s, manager, component, name);
}

/// POST /api/instances/{component}/{name}/restart
pub fn handleRestart(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, paths: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    return @import("instances/lifecycle.zig").handleRestart(allocator, s, manager, paths, component, name, body);
}

/// GET /api/instances/{component}/{name}/provider-health
/// Performs a live provider credential probe for known providers.
pub fn handleProviderHealth(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, paths: paths_mod.Paths, component: []const u8, name: []const u8) ApiResponse {
    return bridge_mod.handleProviderHealth(allocator, s, manager, paths, component, name);
}

/// GET /api/instances/{component}/{name}/usage?window=24h|7d|30d|all
/// Uses a persistent nullhubx cache (hourly + daily buckets) rebuilt from token ledger.
pub fn handleUsage(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, target: []const u8) ApiResponse {
    return @import("instances/usage.zig").handleUsage(allocator, s, paths, component, name, target);
}

/// GET /api/instances/{component}/{name}/history?limit=N&offset=N
/// GET /api/instances/{component}/{name}/history?session_id=...&limit=N&offset=N
pub fn handleHistory(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, target: []const u8) ApiResponse {
    return bridge_mod.handleHistory(allocator, s, paths, component, name, target);
}

/// GET /api/instances/{component}/{name}/onboarding
pub fn handleOnboarding(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) ApiResponse {
    if (s.getInstance(component, name) == null) return notFound();

    var status = readNullclawOnboardingStatus(allocator, s, paths, component, name) catch
        return helpers.serverError();
    defer status.deinit(allocator);

    const body = std.json.Stringify.valueAlloc(allocator, .{
        .supported = status.supported,
        .pending = status.pending,
        .completed = status.completed,
        .bootstrap_exists = status.bootstrap_exists,
        .bootstrap_seeded_at = status.bootstrap_seeded_at,
        .onboarding_completed_at = status.onboarding_completed_at,
        .starter_message = if (status.supported) "Wake up, my friend!" else null,
    }, .{}) catch return helpers.serverError();

    return jsonOk(body);
}

/// GET /api/instances/{component}/{name}/memory?stats=1
/// GET /api/instances/{component}/{name}/memory?key=...
/// GET /api/instances/{component}/{name}/memory?query=...&limit=N
/// GET /api/instances/{component}/{name}/memory?category=...&limit=N
pub fn handleMemory(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, target: []const u8) ApiResponse {
    return bridge_mod.handleMemory(allocator, s, paths, component, name, target);
}

fn instanceWorkspaceDir(allocator: std.mem.Allocator, paths: paths_mod.Paths, component: []const u8, name: []const u8) ![]u8 {
    const inst_dir = try paths.instanceDir(allocator, component, name);
    defer allocator.free(inst_dir);
    return try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
}

pub fn handleSkillsInstall(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    body: []const u8,
) ApiResponse {
    return bridge_mod.handleSkillsInstall(allocator, s, paths, component, name, body);
}

pub fn handleSkillsRemove(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    target: []const u8,
) ApiResponse {
    return bridge_mod.handleSkillsRemove(allocator, s, paths, component, name, target);
}

/// GET /api/instances/{component}/{name}/skills
/// GET /api/instances/{component}/{name}/skills?name=...
/// GET /api/instances/{component}/{name}/skills?catalog=1
pub fn handleSkills(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, target: []const u8) ApiResponse {
    return bridge_mod.handleSkills(allocator, s, paths, component, name, target);
}

/// DELETE /api/instances/{component}/{name}
pub fn handleDelete(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, paths: paths_mod.Paths, component: []const u8, name: []const u8) ApiResponse {
    return @import("instances/lifecycle.zig").handleDelete(allocator, s, manager, paths, component, name);
}

/// POST /api/instances/{component}/import — import a standalone installation.
/// Copies config and data from ~/.{component}/ into the nullhubx instance directory.
/// The binary will be downloaded via the normal install flow on first start.
pub fn handleImport(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8) ApiResponse {
    return @import("instances/import.zig").handleImport(allocator, s, paths, component);
}

/// PATCH /api/instances/{component}/{name} — update settings (auto_start).
pub fn handlePatch(s: *state_mod.State, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    return @import("instances/lifecycle.zig").handlePatch(s, component, name, body);
}

pub fn handleIntegrationGet(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    manager: *manager_mod.Manager,
    mutex: *std.Thread.Mutex,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) ApiResponse {
    return @import("instances/integration.zig").handleGet(allocator, s, manager, mutex, paths, component, name);
}

pub fn handleIntegrationPost(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    manager: *manager_mod.Manager,
    mutex: *std.Thread.Mutex,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    body: []const u8,
) ApiResponse {
    return @import("instances/integration.zig").handlePost(allocator, s, manager, mutex, paths, component, name, body);
}

// ─── Top-level dispatcher ────────────────────────────────────────────────────

pub fn isIntegrationPath(target: []const u8) bool {
    const parsed = parsePath(target) orelse return false;
    return parsed.action != null and std.mem.eql(u8, parsed.action.?, "integration");
}

/// Route an `/api/instances` request. Called from server.zig.
/// `method` is the HTTP verb, `target` is the full request path,
/// `body` is the (possibly empty) request body.
pub fn dispatch(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    manager: *manager_mod.Manager,
    mutex: *std.Thread.Mutex,
    paths: paths_mod.Paths,
    method: []const u8,
    target: []const u8,
    body: []const u8,
) ?ApiResponse {
    // Exact match for the collection endpoint.
    if (std.mem.eql(u8, stripQuery(target), "/api/instances")) {
        if (std.mem.eql(u8, method, "GET")) return handleList(allocator, s, manager);
        return methodNotAllowed();
    }

    const parsed = parsePath(target) orelse return null;

    if (parsed.action) |action| {
        if (std.mem.eql(u8, action, "provider-health")) {
            if (!std.mem.eql(u8, method, "GET")) return methodNotAllowed();
            return handleProviderHealth(allocator, s, manager, paths, parsed.component, parsed.name);
        }
        if (std.mem.eql(u8, action, "usage")) {
            if (!std.mem.eql(u8, method, "GET")) return methodNotAllowed();
            return handleUsage(allocator, s, paths, parsed.component, parsed.name, target);
        }
        if (std.mem.eql(u8, action, "history")) {
            if (!std.mem.eql(u8, method, "GET")) return methodNotAllowed();
            return handleHistory(allocator, s, paths, parsed.component, parsed.name, target);
        }
        if (std.mem.eql(u8, action, "onboarding")) {
            if (!std.mem.eql(u8, method, "GET")) return methodNotAllowed();
            return handleOnboarding(allocator, s, paths, parsed.component, parsed.name);
        }
        if (std.mem.eql(u8, action, "memory")) {
            if (!std.mem.eql(u8, method, "GET")) return methodNotAllowed();
            return handleMemory(allocator, s, paths, parsed.component, parsed.name, target);
        }
        if (std.mem.eql(u8, action, "skills")) {
            if (std.mem.eql(u8, method, "GET")) return handleSkills(allocator, s, paths, parsed.component, parsed.name, target);
            if (std.mem.eql(u8, method, "POST")) return handleSkillsInstall(allocator, s, paths, parsed.component, parsed.name, body);
            if (std.mem.eql(u8, method, "DELETE")) return handleSkillsRemove(allocator, s, paths, parsed.component, parsed.name, target);
            return methodNotAllowed();
        }
        if (std.mem.eql(u8, action, "integration")) {
            if (std.mem.eql(u8, method, "GET")) return handleIntegrationGet(allocator, s, manager, mutex, paths, parsed.component, parsed.name);
            if (std.mem.eql(u8, method, "POST")) return handleIntegrationPost(allocator, s, manager, mutex, paths, parsed.component, parsed.name, body);
            return methodNotAllowed();
        }

        // Remaining actions are POST-only.
        if (!std.mem.eql(u8, method, "POST")) return methodNotAllowed();

        if (std.mem.eql(u8, action, "start")) return handleStart(allocator, s, manager, paths, parsed.component, parsed.name, body);
        if (std.mem.eql(u8, action, "stop")) return handleStop(s, manager, parsed.component, parsed.name);
        if (std.mem.eql(u8, action, "restart")) return handleRestart(allocator, s, manager, paths, parsed.component, parsed.name, body);

        return notFound();
    }

    // POST /api/instances/{component}/import — import standalone installation
    if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, parsed.name, "import")) {
        return handleImport(allocator, s, paths, parsed.component);
    }

    // No action — CRUD on the instance itself.
    if (std.mem.eql(u8, method, "GET")) return handleGet(allocator, s, manager, parsed.component, parsed.name);
    if (std.mem.eql(u8, method, "DELETE")) return handleDelete(allocator, s, manager, paths, parsed.component, parsed.name);
    if (std.mem.eql(u8, method, "PATCH")) return handlePatch(s, parsed.component, parsed.name, body);

    return methodNotAllowed();
}

// ─── Tests ───────────────────────────────────────────────────────────────────

pub const TestManagerCtx = struct {
    manager: manager_mod.Manager,
    mutex: std.Thread.Mutex = .{},
    paths: paths_mod.Paths,

    fn init(allocator: std.mem.Allocator) TestManagerCtx {
        const root = std.fmt.allocPrint(
            allocator,
            "/tmp/nullhubx-test-instances-api-{d}-{x}",
            .{ std.time.nanoTimestamp(), std.crypto.random.int(u64) },
        ) catch @panic("alloc test root failed");
        defer allocator.free(root);

        var p = paths_mod.Paths.init(allocator, root) catch @panic("Paths.init failed");
        std.fs.deleteTreeAbsolute(p.root) catch {};
        p.ensureDirs() catch @panic("ensureDirs failed");
        return .{
            .paths = p,
            .manager = manager_mod.Manager.init(allocator, p),
            .mutex = .{},
        };
    }

    fn deinit(self: *TestManagerCtx, allocator: std.mem.Allocator) void {
        self.manager.deinit();
        std.fs.deleteTreeAbsolute(self.paths.root) catch {};
        self.paths.deinit(allocator);
    }
};

pub fn writeTestInstanceConfig(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    json: []const u8,
) !void {
    try paths.ensureDirs();
    const inst_dir = try paths.instanceDir(allocator, component, name);
    defer allocator.free(inst_dir);
    try ensurePath(inst_dir);

    const config_path = try paths.instanceConfig(allocator, component, name);
    defer allocator.free(config_path);
    const file = try std.fs.createFileAbsolute(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(json);
    try file.writeAll("\n");
}

pub fn writeTestTrackerWorkflow(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    boiler_name: []const u8,
    file_name: []const u8,
    pipeline_id: []const u8,
    claim_role: []const u8,
    success_trigger: []const u8,
) !void {
    const inst_dir = try paths.instanceDir(allocator, "nullboiler", boiler_name);
    defer allocator.free(inst_dir);
    const workflows_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workflows" });
    defer allocator.free(workflows_dir);
    try ensurePath(workflows_dir);

    const workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, file_name });
    defer allocator.free(workflow_path);
    const rendered = try std.json.Stringify.valueAlloc(allocator, .{
        .id = "wf-test",
        .pipeline_id = pipeline_id,
        .claim_roles = &.{claim_role},
        .execution = "subprocess",
        .prompt_template = "Task {{task.id}}: {{task.title}}",
        .on_success = .{
            .transition_to = success_trigger,
        },
    }, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    });
    defer allocator.free(rendered);

    const file = try std.fs.createFileAbsolute(workflow_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(rendered);
    try file.writeAll("\n");
}

pub fn writeTestBinary(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    version: []const u8,
    script: []const u8,
) !void {
    try paths.ensureDirs();
    const bin_path = try paths.binary(allocator, component, version);
    defer allocator.free(bin_path);

    const file = try std.fs.createFileAbsolute(bin_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(script);
    if (comptime std.fs.has_executable_bit) {
        try file.chmod(0o755);
    }
}

test "parsePath: component and name" {
    const p = parsePath("/api/instances/nullclaw/my-agent").?;
    try std.testing.expectEqualStrings("nullclaw", p.component);
    try std.testing.expectEqualStrings("my-agent", p.name);
    try std.testing.expect(p.action == null);
}

test "parsePath: component, name, and action" {
    const p = parsePath("/api/instances/nullclaw/my-agent/start").?;
    try std.testing.expectEqualStrings("nullclaw", p.component);
    try std.testing.expectEqualStrings("my-agent", p.name);
    try std.testing.expectEqualStrings("start", p.action.?);
}

test "parsePath: provider-health action" {
    const p = parsePath("/api/instances/nullclaw/default/provider-health").?;
    try std.testing.expectEqualStrings("nullclaw", p.component);
    try std.testing.expectEqualStrings("default", p.name);
    try std.testing.expectEqualStrings("provider-health", p.action.?);
}

test "parsePath: usage action with query string" {
    const p = parsePath("/api/instances/nullclaw/default/usage?window=7d").?;
    try std.testing.expectEqualStrings("nullclaw", p.component);
    try std.testing.expectEqualStrings("default", p.name);
    try std.testing.expectEqualStrings("usage", p.action.?);
}

test "parsePath: onboarding action" {
    const p = parsePath("/api/instances/nullclaw/default/onboarding").?;
    try std.testing.expectEqualStrings("nullclaw", p.component);
    try std.testing.expectEqualStrings("default", p.name);
    try std.testing.expectEqualStrings("onboarding", p.action.?);
}

test "parseUsageWindow defaults to 24h" {
    try std.testing.expectEqualStrings("24h", parseUsageWindow("/api/instances/nullclaw/default/usage"));
}

test "parseUsageWindow accepts supported values" {
    try std.testing.expectEqualStrings("24h", parseUsageWindow("/api/instances/nullclaw/default/usage?window=24h"));
    try std.testing.expectEqualStrings("7d", parseUsageWindow("/api/instances/nullclaw/default/usage?window=7d"));
    try std.testing.expectEqualStrings("30d", parseUsageWindow("/api/instances/nullclaw/default/usage?window=30d"));
    try std.testing.expectEqualStrings("all", parseUsageWindow("/api/instances/nullclaw/default/usage?window=all"));
}

test "queryParamValueAlloc decodes percent-encoded and plus-separated values" {
    const allocator = std.testing.allocator;
    const value = (try queryParamValueAlloc(allocator, "/api/instances/nullclaw/default/memory?query=hello+world%2Fskills", "query")).?;
    defer allocator.free(value);
    try std.testing.expectEqualStrings("hello world/skills", value);
}

test "parseAnyHttpStatusCode extracts first valid http code" {
    try std.testing.expectEqual(@as(?u16, 200), parseAnyHttpStatusCode("{\"x\":1}\n200\n"));
    try std.testing.expectEqual(@as(?u16, 401), parseAnyHttpStatusCode("status=401 unauthorized"));
    try std.testing.expectEqual(@as(?u16, null), parseAnyHttpStatusCode("not-a-code"));
}

test "classifyProbeFailure maps status codes" {
    const unauthorized = classifyProbeFailure(401, "", "");
    try std.testing.expectEqualStrings("invalid_api_key", unauthorized.reason);
    const forbidden = classifyProbeFailure(403, "", "");
    try std.testing.expectEqualStrings("forbidden", forbidden.reason);
    const limited = classifyProbeFailure(429, "", "");
    try std.testing.expectEqualStrings("rate_limited", limited.reason);
    const unavailable = classifyProbeFailure(503, "", "");
    try std.testing.expectEqualStrings("provider_unavailable", unavailable.reason);
}

test "classifyProbeFailure maps stderr hints" {
    const unauthorized = classifyProbeFailure(null, "", "Unauthorized");
    try std.testing.expectEqualStrings("invalid_api_key", unauthorized.reason);
    const network = classifyProbeFailure(null, "", "connection timeout");
    try std.testing.expectEqualStrings("network_error", network.reason);
}

test "canonicalProbeReason keeps stable reason slices" {
    try std.testing.expectEqualStrings("ok", canonicalProbeReason("ok", true));
    try std.testing.expectEqualStrings("invalid_api_key", canonicalProbeReason("invalid_api_key", false));
    try std.testing.expectEqualStrings("auth_check_failed", canonicalProbeReason("unexpected_reason", false));
    try std.testing.expectEqualStrings("ok", canonicalProbeReason("unexpected_reason", true));
}

test "parsePath: rejects bare /api/instances/" {
    try std.testing.expect(parsePath("/api/instances/") == null);
}

test "parsePath: rejects wrong prefix" {
    try std.testing.expect(parsePath("/api/other/foo/bar") == null);
}

test "parsePath: rejects too many segments" {
    try std.testing.expect(parsePath("/api/instances/a/b/c/d") == null);
}

test "parsePath: component only (no name) returns null" {
    try std.testing.expect(parsePath("/api/instances/nullclaw") == null);
}

test "handleList returns valid JSON structure" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "2026.3.1", .auto_start = true });
    try s.addInstance("nullclaw", "staging", .{ .version = "2026.3.1", .auto_start = false });

    const resp = handleList(allocator, &s, &mctx.manager);
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expectEqualStrings("application/json", resp.content_type);

    // Verify it is valid JSON by parsing it.
    const parsed = try std.json.parseFromSlice(
        struct {
            instances: std.json.ArrayHashMap(std.json.ArrayHashMap(struct {
                version: []const u8,
                auto_start: bool,
                launch_mode: []const u8 = "gateway",
                verbose: bool = false,
                status: []const u8,
            })),
        },
        allocator,
        resp.body,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    // Check the nullclaw component exists with two instances.
    const nullclaw = parsed.value.instances.map.get("nullclaw").?;
    try std.testing.expectEqual(@as(usize, 2), nullclaw.map.count());

    const agent = nullclaw.map.get("my-agent").?;
    try std.testing.expectEqualStrings("2026.3.1", agent.version);
    try std.testing.expect(agent.auto_start == true);
}

test "handleGet returns 404 for missing instance" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    const resp = handleGet(allocator, &s, &mctx.manager, "nonexistent", "nope");
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"not found\"}", resp.body);
}

test "handleGet returns instance detail JSON" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "2026.3.1", .auto_start = true });

    const resp = handleGet(allocator, &s, &mctx.manager, "nullclaw", "my-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);

    // Parse and verify JSON content.
    const parsed = try std.json.parseFromSlice(
        struct {
            version: []const u8,
            auto_start: bool,
            launch_mode: []const u8 = "gateway",
            verbose: bool = false,
            status: []const u8,
        },
        allocator,
        resp.body,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    try std.testing.expectEqualStrings("2026.3.1", parsed.value.version);
    try std.testing.expect(parsed.value.auto_start == true);
    try std.testing.expectEqualStrings("stopped", parsed.value.status);
}

test "handleStart returns 404 for missing instance" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    const resp = handleStart(allocator, &s, &mctx.manager, mctx.paths, "nope", "nope", "");
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
}

test "handleStart returns 500 when binary does not exist" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    // Binary doesn't exist at /tmp/nullhubx-test-instances-api/bin/nullclaw-1.0.0
    // so startInstance will fail and handler returns 500.
    const resp = handleStart(allocator, &s, &mctx.manager, mctx.paths, "nullclaw", "my-agent", "");
    try std.testing.expectEqualStrings("500 Internal Server Error", resp.status);
}

test "handleStop returns 200 for existing instance" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const resp = handleStop(&s, &mctx.manager, "nullclaw", "my-agent");
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expectEqualStrings("{\"status\":\"stopped\"}", resp.body);
}

test "handleRestart returns 500 when binary does not exist" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    // Binary doesn't exist so startInstance fails => 500
    const resp = handleRestart(allocator, &s, &mctx.manager, mctx.paths, "nullclaw", "my-agent", "");
    try std.testing.expectEqualStrings("500 Internal Server Error", resp.status);
}

test "handleDelete removes instance" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const resp = handleDelete(allocator, &s, &mctx.manager, mctx.paths, "nullclaw", "my-agent");
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expectEqualStrings("{\"status\":\"deleted\"}", resp.body);

    // Verify it was actually removed.
    try std.testing.expect(s.getInstance("nullclaw", "my-agent") == null);
}

test "handleDelete removes instance directory from active path" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api-delete-path.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });
    try writeTestInstanceConfig(allocator, mctx.paths, "nullclaw", "my-agent", "{\"gateway\":{\"port\":3000}}");

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "my-agent");
    defer allocator.free(inst_dir);

    const resp = handleDelete(allocator, &s, &mctx.manager, mctx.paths, "nullclaw", "my-agent");
    try std.testing.expectEqualStrings("200 OK", resp.status);

    std.fs.accessAbsolute(inst_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    @panic("expected instance directory to be removed");
}

test "handleDelete restores instance when state save fails" {
    const allocator = std.testing.allocator;
    const bad_state_root = "/tmp/nullhubx-test-instances-api-delete-rollback";
    std.fs.deleteTreeAbsolute(bad_state_root) catch {};
    defer std.fs.deleteTreeAbsolute(bad_state_root) catch {};

    const bad_state_path = try std.fmt.allocPrint(allocator, "{s}/missing/state.json", .{bad_state_root});
    defer allocator.free(bad_state_path);

    var s = state_mod.State.init(allocator, bad_state_path);
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });
    try writeTestInstanceConfig(allocator, mctx.paths, "nullclaw", "my-agent", "{\"gateway\":{\"port\":3000}}");

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "my-agent");
    defer allocator.free(inst_dir);

    const resp = handleDelete(allocator, &s, &mctx.manager, mctx.paths, "nullclaw", "my-agent");
    try std.testing.expectEqualStrings("500 Internal Server Error", resp.status);
    try std.testing.expect(s.getInstance("nullclaw", "my-agent") != null);
    try std.fs.accessAbsolute(inst_dir, .{});
}

test "handleDelete returns 404 for missing instance" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    const resp = handleDelete(allocator, &s, &mctx.manager, mctx.paths, "nope", "nope");
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
}

test "handlePatch updates auto_start" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0", .auto_start = false });

    const resp = handlePatch(&s, "nullclaw", "my-agent", "{\"auto_start\":true}");
    try std.testing.expectEqualStrings("200 OK", resp.status);

    const entry = s.getInstance("nullclaw", "my-agent").?;
    try std.testing.expect(entry.auto_start == true);
}

test "handlePatch returns 404 for missing instance" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();

    const resp = handlePatch(&s, "nope", "nope", "{\"auto_start\":true}");
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
}

test "handlePatch returns 400 for invalid JSON" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const resp = handlePatch(&s, "nullclaw", "my-agent", "not-json");
    try std.testing.expectEqualStrings("400 Bad Request", resp.status);
}

test "handlePatch updates launch_mode" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const resp = handlePatch(&s, "nullclaw", "my-agent", "{\"launch_mode\":\"agent\"}");
    try std.testing.expectEqualStrings("200 OK", resp.status);

    const entry = s.getInstance("nullclaw", "my-agent").?;
    try std.testing.expectEqualStrings("agent", entry.launch_mode);
}

test "handlePatch updates verbose startup flag" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const resp = handlePatch(&s, "nullclaw", "my-agent", "{\"verbose\":true}");
    try std.testing.expectEqualStrings("200 OK", resp.status);

    const entry = s.getInstance("nullclaw", "my-agent").?;
    try std.testing.expect(entry.verbose);
}

test "handleGet includes launch_mode in JSON" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0", .launch_mode = "agent" });

    const resp = handleGet(allocator, &s, &mctx.manager, "nullclaw", "my-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"launch_mode\":\"agent\"") != null);
}

test "handleGet includes verbose in JSON" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0", .verbose = true });

    const resp = handleGet(allocator, &s, &mctx.manager, "nullclaw", "my-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"verbose\":true") != null);
}

test "dispatch routes GET /api/instances" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/instances", "").?;
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "nullclaw") != null);
}

test "dispatch routes POST start action" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    // Binary doesn't exist so start returns 500
    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "POST", "/api/instances/nullclaw/my-agent/start", "").?;
    try std.testing.expectEqualStrings("500 Internal Server Error", resp.status);
}

test "dispatch routes GET provider-health action" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    // No config file exists in this test fixture, so health action returns 404.
    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/instances/nullclaw/my-agent/provider-health", "").?;
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
}

test "handleOnboarding reports pending bootstrap for fresh nullclaw workspace" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "my-agent");
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);
    try ensurePath(workspace_dir);

    const bootstrap_path = try std.fs.path.join(allocator, &.{ workspace_dir, "BOOTSTRAP.md" });
    defer allocator.free(bootstrap_path);
    const bootstrap_file = try std.fs.createFileAbsolute(bootstrap_path, .{ .truncate = true });
    defer bootstrap_file.close();
    try bootstrap_file.writeAll("# bootstrap\n");

    const resp = handleOnboarding(allocator, &s, mctx.paths, "nullclaw", "my-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pending\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"starter_message\":\"Wake up, my friend!\"") != null);
}

test "handleOnboarding reports pending bootstrap from workspace state without disk bootstrap file" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "my-agent");
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);
    try ensurePath(workspace_dir);

    const state_path = try nullclawWorkspaceStatePath(allocator, workspace_dir);
    defer allocator.free(state_path);
    try ensurePath(std.fs.path.dirname(state_path).?);
    const state_file = try std.fs.createFileAbsolute(state_path, .{ .truncate = true });
    defer state_file.close();
    try state_file.writeAll(
        "{\n  \"bootstrap_seeded_at\": \"2026-03-13T01:17:17Z\"\n}\n",
    );

    const resp = handleOnboarding(allocator, &s, mctx.paths, "nullclaw", "my-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_exists\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pending\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"completed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_seeded_at\":\"2026-03-13T01:17:17Z\"") != null);
}

test "handleOnboarding falls back to CLI bootstrap memory for legacy sqlite workspace" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "legacy-agent", .{ .version = "1.0.3" });
    const script =
        \\#!/bin/sh
        \\if [ "$1" = "memory" ] && [ "$2" = "get" ] && [ "$3" = "__bootstrap.prompt.BOOTSTRAP.md" ]; then
        \\  if [ -z "$NULLCLAW_HOME" ]; then
        \\    echo "missing home" >&2
        \\    exit 1
        \\  fi
        \\  printf '%s\n' '{"key":"__bootstrap.prompt.BOOTSTRAP.md","category":"core","timestamp":"2026-03-13T02:37:27Z","content":"# bootstrap","session_id":null}'
        \\  exit 0
        \\fi
        \\echo "unexpected args" >&2
        \\exit 1
        \\
    ;
    try writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.3", script);

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "legacy-agent");
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);
    try ensurePath(workspace_dir);

    const resp = handleOnboarding(allocator, &s, mctx.paths, "nullclaw", "legacy-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_exists\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pending\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"completed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_seeded_at\":\"2026-03-13T02:37:27Z\"") != null);
}

test "handleOnboarding stays idle when legacy sqlite bootstrap memory is absent" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "empty-agent", .{ .version = "1.0.4" });
    const script =
        \\#!/bin/sh
        \\if [ "$1" = "memory" ] && [ "$2" = "get" ] && [ "$3" = "__bootstrap.prompt.BOOTSTRAP.md" ]; then
        \\  printf '%s\n' 'null'
        \\  exit 0
        \\fi
        \\echo "unexpected args" >&2
        \\exit 1
        \\
    ;
    try writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.4", script);

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "empty-agent");
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);
    try ensurePath(workspace_dir);

    const resp = handleOnboarding(allocator, &s, mctx.paths, "nullclaw", "empty-agent");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_exists\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pending\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"completed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bootstrap_seeded_at\":null") != null);
}

test "dispatch routes GET onboarding action" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "my-agent");
    defer allocator.free(inst_dir);
    const workspace_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
    defer allocator.free(workspace_dir);
    try ensurePath(workspace_dir);

    const state_path = try nullclawWorkspaceStatePath(allocator, workspace_dir);
    defer allocator.free(state_path);
    try ensurePath(std.fs.path.dirname(state_path).?);
    const state_file = try std.fs.createFileAbsolute(state_path, .{ .truncate = true });
    defer state_file.close();
    try state_file.writeAll(
        "{\n  \"bootstrap_seeded_at\": \"2026-03-13T01:17:17Z\",\n  \"onboarding_completed_at\": \"2026-03-13T01:30:41Z\"\n}\n",
    );

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/instances/nullclaw/my-agent/onboarding", "").?;
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"completed\":true") != null);
}

test "dispatch provider-health rejects POST" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "POST", "/api/instances/nullclaw/my-agent/provider-health", "").?;
    try std.testing.expectEqualStrings("405 Method Not Allowed", resp.status);
}

test "handleHistory returns CLI JSON and passes instance home" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });
    const script =
        \\#!/bin/sh
        \\if [ "$1" = "history" ] && [ "$2" = "list" ]; then
        \\  if [ -z "$NULLCLAW_HOME" ]; then
        \\    echo "missing home" >&2
        \\    exit 1
        \\  fi
        \\  printf '%s\n' '{"total":1,"limit":50,"offset":0,"sessions":[{"session_id":"s-1","message_count":2,"first_message_at":"2026-03-10T10:00:00Z","last_message_at":"2026-03-10T10:01:00Z"}]}'
        \\  exit 0
        \\fi
        \\if [ "$1" = "history" ] && [ "$2" = "show" ]; then
        \\  printf '{"session_id":"%s","total":2,"limit":100,"offset":0,"messages":[{"role":"user","content":"hi","created_at":"2026-03-10T10:00:00Z"}]}\n' "$3"
        \\  exit 0
        \\fi
        \\echo "unexpected args" >&2
        \\exit 1
        \\
    ;
    try writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.0", script);

    const list_resp = handleHistory(allocator, &s, mctx.paths, "nullclaw", "my-agent", "/api/instances/nullclaw/my-agent/history?limit=50&offset=0");
    defer allocator.free(list_resp.body);
    try std.testing.expectEqualStrings("200 OK", list_resp.status);
    try std.testing.expect(std.mem.indexOf(u8, list_resp.body, "\"session_id\":\"s-1\"") != null);

    const show_resp = handleHistory(allocator, &s, mctx.paths, "nullclaw", "my-agent", "/api/instances/nullclaw/my-agent/history?session_id=s-1&limit=100&offset=0");
    defer allocator.free(show_resp.body);
    try std.testing.expectEqualStrings("200 OK", show_resp.status);
    try std.testing.expect(std.mem.indexOf(u8, show_resp.body, "\"session_id\":\"s-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, show_resp.body, "\"role\":\"user\"") != null);
}

test "handleMemory wraps legacy CLI failures as JSON errors" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.1" });
    const script =
        \\#!/bin/sh
        \\echo "Unknown memory command" >&2
        \\exit 1
        \\
    ;
    try writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.1", script);

    const resp = handleMemory(allocator, &s, mctx.paths, "nullclaw", "my-agent", "/api/instances/nullclaw/my-agent/memory?stats=1");
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"error\":\"cli_command_failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "Unknown memory command") != null);
}

test "dispatch routes GET skills action" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.2" });
    const script =
        \\#!/bin/sh
        \\if [ "$1" = "skills" ] && [ "$2" = "list" ]; then
        \\  printf '%s\n' '[{"name":"checks","version":"1.0.0","description":"Checks","author":"","enabled":true,"always":false,"available":true,"missing_deps":"","path":"/tmp/checks","source":"workspace","instructions_bytes":42}]'
        \\  exit 0
        \\fi
        \\echo "unexpected args" >&2
        \\exit 1
        \\
    ;
    try writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.2", script);

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/instances/nullclaw/my-agent/skills", "").?;
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"name\":\"checks\"") != null);
}

test "dispatch routes GET skills catalog" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.2" });

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/instances/nullclaw/my-agent/skills?catalog=1", "").?;
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"name\":\"nullhubx-admin\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"install_kind\":\"bundled\"") != null);
}

test "dispatch routes POST bundled skill install" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.2" });
    try writeTestInstanceConfig(allocator, mctx.paths, "nullclaw", "my-agent", "{\"autonomy\":{\"level\":\"supervised\"}}");

    const resp = dispatch(
        allocator,
        &s,
        &mctx.manager,
        &mctx.mutex,
        mctx.paths,
        "POST",
        "/api/instances/nullclaw/my-agent/skills",
        "{\"bundled\":\"nullhubx-admin\"}",
    ).?;
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"bundled\":\"nullhubx-admin\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"restart_required\":true") != null);

    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "my-agent");
    defer allocator.free(inst_dir);
    const skill_path = try std.fs.path.join(allocator, &.{ inst_dir, "workspace", "skills", "nullhubx-admin", "SKILL.md" });
    defer allocator.free(skill_path);
    const installed_file = std.fs.openFileAbsolute(skill_path, .{}) catch @panic("missing skill");
    defer installed_file.close();
    const installed = installed_file.readToEndAlloc(allocator, 64 * 1024) catch @panic("missing skill");
    defer allocator.free(installed);
    try std.testing.expect(std.mem.indexOf(u8, installed, "nullhubx api <METHOD> <PATH>") != null);

    const config_path = try mctx.paths.instanceConfig(allocator, "nullclaw", "my-agent");
    defer allocator.free(config_path);
    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();
    const config = try config_file.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(config);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"nullhubx *\"") != null);
}

test "dispatch routes DELETE skills action" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.3" });
    const script =
        \\#!/bin/sh
        \\if [ "$1" = "skills" ] && [ "$2" = "remove" ] && [ "$3" = "nullhubx-admin" ]; then
        \\  printf '%s\n' 'Removed skill: nullhubx-admin'
        \\  exit 0
        \\fi
        \\echo "unexpected args" >&2
        \\exit 1
        \\
    ;
    try writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.3", script);

    const resp = dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "DELETE", "/api/instances/nullclaw/my-agent/skills?name=nullhubx-admin", "").?;
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"removed\"") != null);
}

test "dispatch routes POST source install returns conflict on CLI failure" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};
    defer std.fs.deleteTreeAbsolute(mctx.paths.root) catch {};

    try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.4" });
    const script =
        \\#!/bin/sh
        \\echo "network blocked" >&2
        \\exit 1
        \\
    ;
    try writeTestBinary(allocator, mctx.paths, "nullclaw", "1.0.4", script);

    const resp = dispatch(
        allocator,
        &s,
        &mctx.manager,
        &mctx.mutex,
        mctx.paths,
        "POST",
        "/api/instances/nullclaw/my-agent/skills",
        "{\"source\":\"https://example.com/skill.git\"}",
    ).?;
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("409 Conflict", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"error\":\"skills_install_failed\"") != null);
}

test "dispatch returns null for non-matching path" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try std.testing.expect(dispatch(allocator, &s, &mctx.manager, &mctx.mutex, mctx.paths, "GET", "/api/other", "") == null);
}
