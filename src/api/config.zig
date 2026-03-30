const std = @import("std");
const paths_mod = @import("../core/paths.zig");
const state_mod = @import("../core/state.zig");
const config_refs = @import("../core/config_refs.zig");
const helpers = @import("helpers.zig");

const ApiResponse = helpers.ApiResponse;

const AgentProfileInput = struct {
    id: ?[]const u8 = null,
    provider: ?[]const u8 = null,
    model: ?[]const u8 = null,
    system_prompt: ?[]const u8 = null,
    temperature: ?f64 = null,
    max_depth: ?u32 = null,
};

const AgentProfilesRequest = struct {
    defaults: ?struct {
        model_primary: ?[]const u8 = null,
    } = null,
    profiles: []const AgentProfileInput = &.{},
};

const AgentBindingInput = struct {
    agent_id: ?[]const u8 = null,
    match: ?struct {
        channel: ?[]const u8 = null,
        account_id: ?[]const u8 = null,
        peer: ?struct {
            kind: ?[]const u8 = null,
            id: ?[]const u8 = null,
        } = null,
    } = null,
};

const AgentBindingsRequest = struct {
    bindings: []const AgentBindingInput = &.{},
};

const AgentProfileView = struct {
    id: []const u8,
    provider: []const u8,
    model: []const u8,
    system_prompt: ?[]const u8 = null,
    temperature: ?f64 = null,
    max_depth: ?u32 = null,
};

const AgentBindingView = struct {
    agent_id: []const u8,
    match: struct {
        channel: []const u8,
        account_id: ?[]const u8 = null,
        peer: struct {
            kind: []const u8,
            id: []const u8,
        },
    },
};

const agent_contract_version: u32 = 1;

const agent_profile_standard_fields = [_][]const u8{
    "id",
    "provider",
    "model",
    "system_prompt",
    "temperature",
    "max_depth",
};

const agent_profile_defaults_fields = [_][]const u8{
    "model_primary",
};

const agent_binding_standard_fields = [_][]const u8{
    "agent_id",
    "match.channel",
    "match.account_id",
    "match.peer.kind",
    "match.peer.id",
};

const AgentFieldPolicyView = struct {
    standard_fields: []const []const u8,
    defaults_fields: ?[]const []const u8 = null,
    unknown_fields: []const u8,
    write_mode: []const u8,
};

const AgentProfilesGetResponse = struct {
    contract_version: u32,
    ownership: []const u8,
    resource: []const u8,
    field_policy: AgentFieldPolicyView,
    defaults: struct {
        model_primary: ?[]const u8 = null,
    },
    profiles: []const AgentProfileView,
};

const AgentBindingsGetResponse = struct {
    contract_version: u32,
    ownership: []const u8,
    resource: []const u8,
    field_policy: AgentFieldPolicyView,
    bindings: []const AgentBindingView,
};

const AgentMutationResponse = struct {
    contract_version: u32 = agent_contract_version,
    ownership: []const u8 = "instance",
    resource: []const u8,
    status: []const u8 = "saved",
    apply_state: []const u8 = "config_saved",
    runtime_effect: []const u8 = "component_defined",
    unknown_fields: []const u8,
    profiles_count: ?usize = null,
    bindings_count: ?usize = null,
};

const AgentErrorResponse = struct {
    contract_version: u32 = agent_contract_version,
    resource: []const u8,
    status: []const u8,
    error_code: []const u8,
    @"error": []const u8,
    apply_state: ?[]const u8 = null,
};

const AgentBindingScope = struct {
    agent_id: []const u8,
    channel: []const u8,
    account_id: ?[]const u8 = null,
    peer_kind: []const u8,
    peer_id: []const u8,
};

// ─── Handlers ────────────────────────────────────────────────────────────────

/// Check if ?resolve=true is in the query string
fn hasResolveParam(target: []const u8) bool {
    const query_start = std.mem.indexOfScalar(u8, target, '?') orelse return false;
    return std.mem.indexOf(u8, target[query_start..], "resolve=true") != null;
}

/// GET /api/instances/{c}/{n}/config — read instance config file.
/// If ?resolve=true, resolve _ref references from saved providers/channels.
pub fn handleGet(allocator: std.mem.Allocator, p: paths_mod.Paths, state: *state_mod.State, component: []const u8, name: []const u8, resolve: bool) ApiResponse {
    const config_path = p.instanceConfig(allocator, component, name) catch return .{
        .status = "500 Internal Server Error",
        .content_type = "application/json",
        .body = "{\"error\":\"internal error\"}",
    };
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .{
            .status = "404 Not Found",
            .content_type = "application/json",
            .body = "{\"error\":\"config not found\"}",
        },
        else => return .{
            .status = "500 Internal Server Error",
            .content_type = "application/json",
            .body = "{\"error\":\"internal error\"}",
        },
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch return .{
        .status = "500 Internal Server Error",
        .content_type = "application/json",
        .body = "{\"error\":\"internal error\"}",
    };

    // If resolve=true, resolve _ref references
    if (resolve) {
        const resolved = config_refs.resolveConfigRefs(allocator, contents, state) catch {
            allocator.free(contents);
            return .{
                .status = "500 Internal Server Error",
                .content_type = "application/json",
                .body = "{\"error\":\"failed to resolve config references\"}",
            };
        };
        allocator.free(contents);
        return .{ .status = "200 OK", .content_type = "application/json", .body = resolved };
    }

    return .{ .status = "200 OK", .content_type = "application/json", .body = contents };
}

/// PUT /api/instances/{c}/{n}/config — replace config file with request body.
pub fn handlePut(allocator: std.mem.Allocator, p: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    return writeConfig(allocator, p, component, name, body);
}

/// PATCH /api/instances/{c}/{n}/config — for now, same as PUT.
pub fn handlePatch(allocator: std.mem.Allocator, p: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    return writeConfig(allocator, p, component, name, body);
}

pub fn handleGetAgentProfiles(allocator: std.mem.Allocator, p: paths_mod.Paths, component: []const u8, name: []const u8) ApiResponse {
    var parsed = loadConfigTree(allocator, p, component, name) catch |err| return switch (err) {
        error.FileNotFound => agentErrorResponse(
            allocator,
            "404 Not Found",
            "agent_profiles",
            "not_found",
            "instance_config_not_found",
            "config not found",
            null,
        ),
        else => helpers.serverError(),
    };
    defer parsed.deinit();

    if (parsed.value != .object) return helpers.serverError();

    var profiles = std.ArrayListUnmanaged(AgentProfileView){};
    defer profiles.deinit(allocator);

    const defaults_model_primary = extractDefaultModelPrimary(parsed.value.object);
    collectAgentProfiles(allocator, parsed.value.object, &profiles) catch return helpers.serverError();

    const body = std.json.Stringify.valueAlloc(allocator, AgentProfilesGetResponse{
        .contract_version = agent_contract_version,
        .ownership = "instance",
        .resource = "agent_profiles",
        .field_policy = .{
            .standard_fields = agent_profile_standard_fields[0..],
            .defaults_fields = agent_profile_defaults_fields[0..],
            .unknown_fields = "preserve_by_id",
            .write_mode = "replace_standard_fields",
        },
        .defaults = .{ .model_primary = defaults_model_primary },
        .profiles = profiles.items,
    }, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    }) catch return helpers.serverError();

    return helpers.jsonOk(body);
}

pub fn handlePutAgentProfiles(allocator: std.mem.Allocator, p: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    const request = std.json.parseFromSlice(AgentProfilesRequest, allocator, body, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return agentErrorResponse(
        allocator,
        "400 Bad Request",
        "agent_profiles",
        "validation_failed",
        "invalid_agent_profiles_json",
        "invalid agent profiles JSON",
        "unchanged",
    );
    defer request.deinit();

    var seen_ids = std.StringHashMap(void).init(allocator);
    defer seen_ids.deinit();

    for (request.value.profiles) |profile| {
        const profile_id = profile.id orelse return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_profiles",
            "validation_failed",
            "profile_id_required",
            "profile id is required",
            "unchanged",
        );
        const provider = profile.provider orelse return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_profiles",
            "validation_failed",
            "profile_provider_required",
            "profile provider is required",
            "unchanged",
        );
        const model = profile.model orelse return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_profiles",
            "validation_failed",
            "profile_model_required",
            "profile model is required",
            "unchanged",
        );
        if (profile_id.len == 0 or provider.len == 0 or model.len == 0) {
            return agentErrorResponse(
                allocator,
                "400 Bad Request",
                "agent_profiles",
                "validation_failed",
                "profile_required_fields_empty",
                "profile id/provider/model must not be empty",
                "unchanged",
            );
        }
        const max_depth = profile.max_depth orelse 3;
        if (max_depth < 1 or max_depth > 8) {
            return agentErrorResponse(
                allocator,
                "400 Bad Request",
                "agent_profiles",
                "validation_failed",
                "profile_max_depth_out_of_range",
                "profile max_depth must be between 1 and 8",
                "unchanged",
            );
        }
        if (seen_ids.contains(profile_id)) {
            return agentErrorResponse(
                allocator,
                "400 Bad Request",
                "agent_profiles",
                "validation_failed",
                "profile_id_duplicate",
                "profile id must be unique",
                "unchanged",
            );
        }
        seen_ids.put(profile_id, {}) catch return helpers.serverError();
    }

    if (request.value.defaults) |defaults| {
        if (defaults.model_primary) |primary| {
            if (primary.len > 0 and !isProviderModelRef(primary)) {
                return agentErrorResponse(
                    allocator,
                    "400 Bad Request",
                    "agent_profiles",
                    "validation_failed",
                    "defaults_model_primary_invalid",
                    "defaults.model_primary must be provider/model",
                    "unchanged",
                );
            }
        }
    }

    var parsed = loadOrInitConfigTree(allocator, p, component, name) catch return helpers.serverError();
    defer parsed.deinit();
    if (parsed.value != .object) return helpers.serverError();
    const arena = parsed.arena.allocator();

    var existing_profiles = std.StringHashMap(std.json.Value).init(allocator);
    defer existing_profiles.deinit();
    collectAgentProfileValues(parsed.value.object, &existing_profiles) catch return helpers.serverError();

    const root_obj = &parsed.value.object;
    const agents_obj = ensureObjectField(arena, root_obj, "agents") catch return helpers.serverError();
    const defaults_obj = ensureObjectField(arena, agents_obj, "defaults") catch return helpers.serverError();
    const model_obj = ensureObjectField(arena, defaults_obj, "model") catch return helpers.serverError();

    if (request.value.defaults) |defaults| {
        if (defaults.model_primary) |primary| {
            if (primary.len == 0) {
                _ = model_obj.swapRemove("primary");
            } else {
                model_obj.put("primary", .{ .string = primary }) catch return helpers.serverError();
            }
        } else {
            _ = model_obj.swapRemove("primary");
        }
    } else {
        _ = model_obj.swapRemove("primary");
    }

    var list = std.json.Array.init(arena);
    for (request.value.profiles) |profile| {
        var item = std.json.ObjectMap.init(arena);
        if (existing_profiles.get(profile.id.?)) |existing_value| {
            if (existing_value == .object) {
                var it = existing_value.object.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    if (isKnownAgentProfileField(key)) continue;
                    item.put(key, entry.value_ptr.*) catch return helpers.serverError();
                }
            }
        }
        item.put("id", .{ .string = profile.id.? }) catch return helpers.serverError();
        item.put("provider", .{ .string = profile.provider.? }) catch return helpers.serverError();
        item.put("model", .{ .string = profile.model.? }) catch return helpers.serverError();
        if (profile.system_prompt) |system_prompt| {
            if (system_prompt.len > 0) {
                item.put("system_prompt", .{ .string = system_prompt }) catch return helpers.serverError();
            }
        }
        if (profile.temperature) |temperature| {
            item.put("temperature", .{ .float = temperature }) catch return helpers.serverError();
        }
        item.put("max_depth", .{ .integer = profile.max_depth orelse 3 }) catch return helpers.serverError();
        list.append(.{ .object = item }) catch return helpers.serverError();
    }
    agents_obj.put("list", .{ .array = list }) catch return helpers.serverError();

    const rendered = std.json.Stringify.valueAlloc(allocator, parsed.value, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    }) catch return helpers.serverError();
    defer allocator.free(rendered);

    const save_resp = writeConfig(allocator, p, component, name, rendered);
    if (!std.mem.eql(u8, save_resp.status, "200 OK")) return save_resp;

    const resp_body = std.json.Stringify.valueAlloc(allocator, AgentMutationResponse{
        .resource = "agent_profiles",
        .unknown_fields = "preserve_by_id",
        .profiles_count = request.value.profiles.len,
    }, .{
        .emit_null_optional_fields = false,
    }) catch return helpers.serverError();
    return helpers.jsonOk(resp_body);
}

pub fn handleGetAgentBindings(allocator: std.mem.Allocator, p: paths_mod.Paths, component: []const u8, name: []const u8) ApiResponse {
    var parsed = loadConfigTree(allocator, p, component, name) catch |err| return switch (err) {
        error.FileNotFound => agentErrorResponse(
            allocator,
            "404 Not Found",
            "agent_bindings",
            "not_found",
            "instance_config_not_found",
            "config not found",
            null,
        ),
        else => helpers.serverError(),
    };
    defer parsed.deinit();
    if (parsed.value != .object) return helpers.serverError();

    var bindings = std.ArrayListUnmanaged(AgentBindingView){};
    defer bindings.deinit(allocator);
    collectAgentBindings(allocator, parsed.value.object, &bindings) catch return helpers.serverError();

    const resp_body = std.json.Stringify.valueAlloc(allocator, AgentBindingsGetResponse{
        .contract_version = agent_contract_version,
        .ownership = "instance",
        .resource = "agent_bindings",
        .field_policy = .{
            .standard_fields = agent_binding_standard_fields[0..],
            .unknown_fields = "replace_all",
            .write_mode = "replace_all",
        },
        .bindings = bindings.items,
    }, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    }) catch return helpers.serverError();

    return helpers.jsonOk(resp_body);
}

pub fn handlePutAgentBindings(allocator: std.mem.Allocator, p: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    const request = std.json.parseFromSlice(AgentBindingsRequest, allocator, body, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return agentErrorResponse(
        allocator,
        "400 Bad Request",
        "agent_bindings",
        "validation_failed",
        "invalid_agent_bindings_json",
        "invalid agent bindings JSON",
        "unchanged",
    );
    defer request.deinit();

    var parsed = loadOrInitConfigTree(allocator, p, component, name) catch return helpers.serverError();
    defer parsed.deinit();
    if (parsed.value != .object) return helpers.serverError();
    const arena = parsed.arena.allocator();

    var profile_ids = std.StringHashMap(void).init(allocator);
    defer profile_ids.deinit();
    collectAgentProfileIds(allocator, parsed.value.object, &profile_ids) catch return helpers.serverError();

    var validated_bindings = std.ArrayListUnmanaged(AgentBindingScope){};
    defer {
        for (validated_bindings.items) |binding_scope| allocator.free(binding_scope.peer_id);
        validated_bindings.deinit(allocator);
    }

    for (request.value.bindings, 0..) |binding, binding_index| {
        const raw_agent_id = binding.agent_id orelse return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_bindings",
            "validation_failed",
            "binding_agent_id_required",
            "binding agent_id is required",
            "unchanged",
        );
        const agent_id = trimAsciiWhitespace(raw_agent_id);
        if (agent_id.len == 0) return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_bindings",
            "validation_failed",
            "binding_agent_id_empty",
            "binding agent_id must not be empty",
            "unchanged",
        );
        if (!profile_ids.contains(agent_id) and !std.mem.eql(u8, agent_id, "main") and !std.mem.eql(u8, agent_id, "default")) {
            return agentErrorResponse(
                allocator,
                "400 Bad Request",
                "agent_bindings",
                "validation_failed",
                "binding_agent_id_unknown",
                "binding agent_id must reference an existing profile",
                "unchanged",
            );
        }

        const match = binding.match orelse return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_bindings",
            "validation_failed",
            "binding_match_required",
            "binding match is required",
            "unchanged",
        );
        const raw_channel = match.channel orelse return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_bindings",
            "validation_failed",
            "binding_match_channel_required",
            "binding match.channel is required",
            "unchanged",
        );
        const channel = trimAsciiWhitespace(raw_channel);
        const peer = match.peer orelse return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_bindings",
            "validation_failed",
            "binding_match_peer_required",
            "binding match.peer is required",
            "unchanged",
        );
        const raw_peer_kind = peer.kind orelse return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_bindings",
            "validation_failed",
            "binding_match_peer_kind_required",
            "binding match.peer.kind is required",
            "unchanged",
        );
        const peer_kind = trimAsciiWhitespace(raw_peer_kind);
        const raw_peer_id = peer.id orelse return agentErrorResponse(
            allocator,
            "400 Bad Request",
            "agent_bindings",
            "validation_failed",
            "binding_match_peer_id_required",
            "binding match.peer.id is required",
            "unchanged",
        );
        const peer_id = trimAsciiWhitespace(raw_peer_id);
        if (channel.len == 0 or peer_kind.len == 0 or peer_id.len == 0) {
            return agentErrorResponse(
                allocator,
                "400 Bad Request",
                "agent_bindings",
                "validation_failed",
                "binding_match_fields_empty",
                "binding match fields must not be empty",
                "unchanged",
            );
        }

        const normalized_peer_id = normalizePeerIdOwned(allocator, peer_id) catch return helpers.serverError();
        errdefer allocator.free(normalized_peer_id);
        const binding_scope = AgentBindingScope{
            .agent_id = agent_id,
            .channel = channel,
            .account_id = trimOptionalAsciiWhitespace(match.account_id),
            .peer_kind = peer_kind,
            .peer_id = normalized_peer_id,
        };

        for (validated_bindings.items, 0..) |existing_scope, existing_index| {
            if (bindingRouteEquals(existing_scope, binding_scope)) {
                const message = bindingValidationMessageAlloc(
                    allocator,
                    .duplicate,
                    binding_index,
                    existing_index,
                    binding_scope,
                ) catch return helpers.serverError();
                defer allocator.free(message);
                allocator.free(normalized_peer_id);
                return agentErrorResponse(
                    allocator,
                    "400 Bad Request",
                    "agent_bindings",
                    "validation_failed",
                    "binding_route_duplicate",
                    message,
                    "unchanged",
                );
            }
            if (bindingScopeEquals(existing_scope, binding_scope)) {
                const message = bindingValidationMessageAlloc(
                    allocator,
                    .conflict,
                    binding_index,
                    existing_index,
                    binding_scope,
                ) catch return helpers.serverError();
                defer allocator.free(message);
                allocator.free(normalized_peer_id);
                return agentErrorResponse(
                    allocator,
                    "400 Bad Request",
                    "agent_bindings",
                    "validation_failed",
                    "binding_scope_conflict",
                    message,
                    "unchanged",
                );
            }
        }

        validated_bindings.append(allocator, binding_scope) catch return helpers.serverError();
    }

    var bindings_array = std.json.Array.init(arena);
    for (request.value.bindings) |binding| {
        var binding_obj = std.json.ObjectMap.init(arena);
        binding_obj.put("agent_id", .{ .string = trimAsciiWhitespace(binding.agent_id.?) }) catch return helpers.serverError();

        var match_obj = std.json.ObjectMap.init(arena);
        const match = binding.match.?;
        match_obj.put("channel", .{ .string = trimAsciiWhitespace(match.channel.?) }) catch return helpers.serverError();
        if (trimOptionalAsciiWhitespace(match.account_id)) |account_id| {
            match_obj.put("account_id", .{ .string = account_id }) catch return helpers.serverError();
        }

        var peer_obj = std.json.ObjectMap.init(arena);
        const peer = match.peer.?;
        peer_obj.put("kind", .{ .string = trimAsciiWhitespace(peer.kind.?) }) catch return helpers.serverError();
        const normalized_peer_id = normalizePeerIdAlloc(arena, trimAsciiWhitespace(peer.id.?)) catch return helpers.serverError();
        peer_obj.put("id", .{ .string = normalized_peer_id }) catch return helpers.serverError();
        match_obj.put("peer", .{ .object = peer_obj }) catch return helpers.serverError();

        binding_obj.put("match", .{ .object = match_obj }) catch return helpers.serverError();
        bindings_array.append(.{ .object = binding_obj }) catch return helpers.serverError();
    }
    parsed.value.object.put("bindings", .{ .array = bindings_array }) catch return helpers.serverError();

    const rendered = std.json.Stringify.valueAlloc(allocator, parsed.value, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    }) catch return helpers.serverError();
    defer allocator.free(rendered);

    const save_resp = writeConfig(allocator, p, component, name, rendered);
    if (!std.mem.eql(u8, save_resp.status, "200 OK")) return save_resp;

    const resp_body = std.json.Stringify.valueAlloc(allocator, AgentMutationResponse{
        .resource = "agent_bindings",
        .unknown_fields = "replace_all",
        .bindings_count = request.value.bindings.len,
    }, .{
        .emit_null_optional_fields = false,
    }) catch return helpers.serverError();
    return helpers.jsonOk(resp_body);
}

fn writeConfig(allocator: std.mem.Allocator, p: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    const config_path = p.instanceConfig(allocator, component, name) catch return .{
        .status = "500 Internal Server Error",
        .content_type = "application/json",
        .body = "{\"error\":\"internal error\"}",
    };
    defer allocator.free(config_path);

    // Ensure the parent directory exists.
    const dir_path = p.instanceDir(allocator, component, name) catch return .{
        .status = "500 Internal Server Error",
        .content_type = "application/json",
        .body = "{\"error\":\"internal error\"}",
    };
    defer allocator.free(dir_path);

    std.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => {
            // Try creating parent directories.
            const inst_base = p.instanceDir(allocator, component, "") catch return .{
                .status = "500 Internal Server Error",
                .content_type = "application/json",
                .body = "{\"error\":\"internal error\"}",
            };
            defer allocator.free(inst_base);
            // Use makePath for nested creation.
            makeDirRecursive(dir_path) catch return .{
                .status = "500 Internal Server Error",
                .content_type = "application/json",
                .body = "{\"error\":\"cannot create instance directory\"}",
            };
        },
    };

    const file = std.fs.createFileAbsolute(config_path, .{}) catch return .{
        .status = "500 Internal Server Error",
        .content_type = "application/json",
        .body = "{\"error\":\"cannot write config\"}",
    };
    defer file.close();

    file.writeAll(body) catch return .{
        .status = "500 Internal Server Error",
        .content_type = "application/json",
        .body = "{\"error\":\"cannot write config\"}",
    };

    return .{ .status = "200 OK", .content_type = "application/json", .body = "{\"status\":\"saved\"}" };
}

fn makeDirRecursive(path: []const u8) !void {
    // Walk from root to leaf, creating each segment.
    var i: usize = 1; // skip leading /
    while (i < path.len) {
        if (path[i] == '/') {
            std.fs.makeDirAbsolute(path[0..i]) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }
        i += 1;
    }
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

/// Parse a config-related sub-path from a parsed instance path.
/// Returns true if the path ends with "/config".
pub fn isConfigPath(target: []const u8) bool {
    return std.mem.endsWith(u8, target, "/config") or
        std.mem.startsWith(u8, target, "/api/instances/") and
            std.mem.indexOf(u8, target, "/config?") != null;
}

/// Extract component and name from /api/instances/{c}/{n}/config.
pub const ParsedConfigPath = struct {
    component: []const u8,
    name: []const u8,
};

pub fn parseConfigPath(target: []const u8) ?ParsedConfigPath {
    const prefix = "/api/instances/";

    if (!std.mem.startsWith(u8, target, prefix)) return null;

    // Strip query string
    const query_pos = std.mem.indexOfScalar(u8, target, '?');
    const path_end = query_pos orelse target.len;
    const path = target[0..path_end];

    const suffix = "/config";
    if (!std.mem.endsWith(u8, path, suffix)) return null;

    const rest = path[prefix.len .. path.len - suffix.len];
    if (rest.len == 0) return null;

    const sep = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
    const component = rest[0..sep];
    const name = rest[sep + 1 ..];

    if (component.len == 0 or name.len == 0) return null;
    // Ensure no extra slashes in name.
    if (std.mem.indexOfScalar(u8, name, '/') != null) return null;

    return .{ .component = component, .name = name };
}

/// Check if request wants resolved config
pub fn shouldResolve(target: []const u8) bool {
    return hasResolveParam(target);
}

pub fn isAgentProfilesPath(target: []const u8) bool {
    return pathMatchesSuffix(target, "/agents/profiles");
}

pub fn isAgentBindingsPath(target: []const u8) bool {
    return pathMatchesSuffix(target, "/agents/bindings");
}

pub fn parseAgentProfilesPath(target: []const u8) ?ParsedConfigPath {
    return parseInstanceSuffixPath(target, "/agents/profiles");
}

pub fn parseAgentBindingsPath(target: []const u8) ?ParsedConfigPath {
    return parseInstanceSuffixPath(target, "/agents/bindings");
}

fn loadConfigTree(allocator: std.mem.Allocator, p: paths_mod.Paths, component: []const u8, name: []const u8) !std.json.Parsed(std.json.Value) {
    const config_path = try p.instanceConfig(allocator, component, name);
    defer allocator.free(config_path);
    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4 * 1024 * 1024);
    defer allocator.free(contents);
    return try std.json.parseFromSlice(std.json.Value, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

fn loadOrInitConfigTree(allocator: std.mem.Allocator, p: paths_mod.Paths, component: []const u8, name: []const u8) !std.json.Parsed(std.json.Value) {
    return loadConfigTree(allocator, p, component, name) catch |err| switch (err) {
        error.FileNotFound => std.json.parseFromSlice(std.json.Value, allocator, "{}", .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        }),
        else => err,
    };
}

fn pathMatchesSuffix(target: []const u8, suffix: []const u8) bool {
    const path = stripQuery(target);
    return std.mem.startsWith(u8, path, "/api/instances/") and std.mem.endsWith(u8, path, suffix);
}

fn parseInstanceSuffixPath(target: []const u8, suffix: []const u8) ?ParsedConfigPath {
    const prefix = "/api/instances/";
    const path = stripQuery(target);
    if (!std.mem.startsWith(u8, path, prefix)) return null;
    if (!std.mem.endsWith(u8, path, suffix)) return null;

    const rest = path[prefix.len .. path.len - suffix.len];
    const sep = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
    const component = rest[0..sep];
    const name = rest[sep + 1 ..];
    if (component.len == 0 or name.len == 0) return null;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return null;
    return .{ .component = component, .name = name };
}

fn stripQuery(target: []const u8) []const u8 {
    const query_pos = std.mem.indexOfScalar(u8, target, '?') orelse return target;
    return target[0..query_pos];
}

fn extractDefaultModelPrimary(root_obj: std.json.ObjectMap) ?[]const u8 {
    if (root_obj.get("agents")) |agents_val| {
        if (agents_val == .object) {
            if (agents_val.object.get("defaults")) |defaults_val| {
                if (defaults_val == .object) {
                    if (defaults_val.object.get("model")) |model_val| {
                        if (model_val == .object) {
                            if (model_val.object.get("primary")) |primary_val| {
                                if (primary_val == .string and primary_val.string.len > 0) return primary_val.string;
                            }
                        }
                    }
                }
            }
        }
    }
    return null;
}

fn collectAgentProfiles(allocator: std.mem.Allocator, root_obj: std.json.ObjectMap, out: *std.ArrayListUnmanaged(AgentProfileView)) !void {
    if (root_obj.get("agents")) |agents_val| {
        if (agents_val == .object) {
            if (agents_val.object.get("list")) |list_val| {
                if (list_val == .array) {
                    for (list_val.array.items) |item| {
                        const profile = parseAgentProfileValue("", item) orelse continue;
                        try out.append(allocator, profile);
                    }
                    return;
                }
            }

            var it = agents_val.object.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (std.mem.eql(u8, key, "defaults") or std.mem.eql(u8, key, "list")) continue;
                const profile = parseAgentProfileValue(key, entry.value_ptr.*) orelse continue;
                try out.append(allocator, profile);
            }
        }
    }
}

fn collectAgentProfileIds(allocator: std.mem.Allocator, root_obj: std.json.ObjectMap, out: *std.StringHashMap(void)) !void {
    var profiles = std.ArrayListUnmanaged(AgentProfileView){};
    defer profiles.deinit(allocator);
    try collectAgentProfiles(allocator, root_obj, &profiles);
    for (profiles.items) |profile| {
        try out.put(profile.id, {});
    }
}

fn collectAgentProfileValues(root_obj: std.json.ObjectMap, out: *std.StringHashMap(std.json.Value)) !void {
    if (root_obj.get("agents")) |agents_val| {
        if (agents_val == .object) {
            if (agents_val.object.get("list")) |list_val| {
                if (list_val == .array) {
                    for (list_val.array.items) |item| {
                        const id = extractAgentProfileId("", item) orelse continue;
                        try out.put(id, item);
                    }
                    return;
                }
            }

            var it = agents_val.object.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (std.mem.eql(u8, key, "defaults") or std.mem.eql(u8, key, "list")) continue;
                const id = extractAgentProfileId(key, entry.value_ptr.*) orelse continue;
                try out.put(id, entry.value_ptr.*);
            }
        }
    }
}

fn extractAgentProfileId(fallback_id: []const u8, value: std.json.Value) ?[]const u8 {
    if (value != .object) return if (fallback_id.len > 0) fallback_id else null;
    const obj = value.object;
    const id = if (obj.get("id")) |id_val|
        if (id_val == .string and id_val.string.len > 0) id_val.string else null
    else if (obj.get("name")) |name_val|
        if (name_val == .string and name_val.string.len > 0) name_val.string else null
    else
        null;
    if (id) |id_value| return id_value;
    return if (fallback_id.len > 0) fallback_id else null;
}

fn parseAgentProfileValue(fallback_id: []const u8, value: std.json.Value) ?AgentProfileView {
    if (value != .object) return null;
    const obj = value.object;

    const id = if (obj.get("id")) |id_val|
        if (id_val == .string and id_val.string.len > 0) id_val.string else fallback_id
    else if (obj.get("name")) |name_val|
        if (name_val == .string and name_val.string.len > 0) name_val.string else fallback_id
    else
        fallback_id;
    if (id.len == 0) return null;

    const provider_field = if (obj.get("provider")) |provider_val|
        if (provider_val == .string and provider_val.string.len > 0) provider_val.string else null
    else
        null;

    const model_field = if (obj.get("model")) |model_val| switch (model_val) {
        .string => if (model_val.string.len > 0) model_val.string else null,
        .object => blk: {
            if (model_val.object.get("primary")) |primary_val| {
                if (primary_val == .string and primary_val.string.len > 0) break :blk primary_val.string;
            }
            break :blk null;
        },
        else => null,
    } else null;

    const resolved = resolveProviderModel(provider_field, model_field orelse return null) orelse return null;

    return .{
        .id = id,
        .provider = resolved.provider,
        .model = resolved.model,
        .system_prompt = if (obj.get("system_prompt")) |system_prompt_val|
            if (system_prompt_val == .string and system_prompt_val.string.len > 0) system_prompt_val.string else null
        else
            null,
        .temperature = if (obj.get("temperature")) |temperature_val| switch (temperature_val) {
            .float => temperature_val.float,
            .integer => @floatFromInt(temperature_val.integer),
            else => null,
        } else null,
        .max_depth = if (obj.get("max_depth")) |max_depth_val|
            if (max_depth_val == .integer and max_depth_val.integer >= 0) @intCast(max_depth_val.integer) else null
        else
            null,
    };
}

fn isKnownAgentProfileField(key: []const u8) bool {
    return std.mem.eql(u8, key, "id") or
        std.mem.eql(u8, key, "name") or
        std.mem.eql(u8, key, "provider") or
        std.mem.eql(u8, key, "model") or
        std.mem.eql(u8, key, "system_prompt") or
        std.mem.eql(u8, key, "temperature") or
        std.mem.eql(u8, key, "max_depth");
}

fn collectAgentBindings(allocator: std.mem.Allocator, root_obj: std.json.ObjectMap, out: *std.ArrayListUnmanaged(AgentBindingView)) !void {
    if (root_obj.get("bindings")) |bindings_val| {
        if (bindings_val == .array) {
            for (bindings_val.array.items) |binding_val| {
                const binding = parseAgentBindingValue(binding_val) orelse continue;
                try out.append(allocator, binding);
            }
        }
    }
}

fn parseAgentBindingValue(value: std.json.Value) ?AgentBindingView {
    if (value != .object) return null;
    const obj = value.object;
    const agent_id_val = obj.get("agent_id") orelse return null;
    if (agent_id_val != .string or agent_id_val.string.len == 0) return null;
    const match_val = obj.get("match") orelse return null;
    if (match_val != .object) return null;
    const match_obj = match_val.object;
    const channel_val = match_obj.get("channel") orelse return null;
    if (channel_val != .string or channel_val.string.len == 0) return null;
    const peer_val = match_obj.get("peer") orelse return null;
    if (peer_val != .object) return null;
    const peer_obj = peer_val.object;
    const peer_kind_val = peer_obj.get("kind") orelse return null;
    const peer_id_val = peer_obj.get("id") orelse return null;
    if (peer_kind_val != .string or peer_kind_val.string.len == 0) return null;
    if (peer_id_val != .string or peer_id_val.string.len == 0) return null;

    return .{
        .agent_id = agent_id_val.string,
        .match = .{
            .channel = channel_val.string,
            .account_id = if (match_obj.get("account_id")) |account_id_val|
                if (account_id_val == .string and account_id_val.string.len > 0) account_id_val.string else null
            else
                null,
            .peer = .{
                .kind = peer_kind_val.string,
                .id = peer_id_val.string,
            },
        },
    };
}

fn ensureObjectField(allocator: std.mem.Allocator, parent: *std.json.ObjectMap, key: []const u8) !*std.json.ObjectMap {
    if (parent.getPtr(key)) |existing| {
        if (existing.* == .object) return &existing.object;
    }
    try parent.put(key, .{ .object = std.json.ObjectMap.init(allocator) });
    return &parent.getPtr(key).?.object;
}

fn isProviderModelRef(value: []const u8) bool {
    return splitPrimaryModelRef(value) != null;
}

fn normalizePeerIdAlloc(allocator: std.mem.Allocator, raw_id: []const u8) ![]const u8 {
    const legacy_sep = "#topic:";
    if (std.mem.indexOf(u8, raw_id, legacy_sep)) |sep_pos| {
        const chat_id = raw_id[0..sep_pos];
        const thread_part = raw_id[sep_pos + legacy_sep.len ..];
        if (chat_id.len > 0 and thread_part.len > 0) {
            return std.fmt.allocPrint(allocator, "{s}:thread:{s}", .{ chat_id, thread_part });
        }
    }
    return raw_id;
}

fn normalizePeerIdOwned(allocator: std.mem.Allocator, raw_id: []const u8) ![]const u8 {
    const normalized = try normalizePeerIdAlloc(allocator, raw_id);
    if (normalized.ptr == raw_id.ptr and normalized.len == raw_id.len) {
        return allocator.dupe(u8, normalized);
    }
    return normalized;
}

fn trimAsciiWhitespace(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, &std.ascii.whitespace);
}

fn trimOptionalAsciiWhitespace(value: ?[]const u8) ?[]const u8 {
    const raw_value = value orelse return null;
    const trimmed = trimAsciiWhitespace(raw_value);
    if (trimmed.len == 0) return null;
    return trimmed;
}

fn optionalAsciiEqlIgnoreCase(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if (lhs == null and rhs == null) return true;
    if (lhs == null or rhs == null) return false;
    return std.ascii.eqlIgnoreCase(lhs.?, rhs.?);
}

fn bindingScopeEquals(lhs: AgentBindingScope, rhs: AgentBindingScope) bool {
    return std.ascii.eqlIgnoreCase(lhs.channel, rhs.channel) and
        optionalAsciiEqlIgnoreCase(lhs.account_id, rhs.account_id) and
        std.ascii.eqlIgnoreCase(lhs.peer_kind, rhs.peer_kind) and
        std.mem.eql(u8, lhs.peer_id, rhs.peer_id);
}

fn bindingRouteEquals(lhs: AgentBindingScope, rhs: AgentBindingScope) bool {
    return std.mem.eql(u8, lhs.agent_id, rhs.agent_id) and bindingScopeEquals(lhs, rhs);
}

fn bindingScopeLabelAlloc(allocator: std.mem.Allocator, scope: AgentBindingScope) ![]const u8 {
    if (scope.account_id) |account_id| {
        return std.fmt.allocPrint(
            allocator,
            "channel/account/peer scope `{s}` / `{s}` / `{s}` `{s}`",
            .{ scope.channel, account_id, scope.peer_kind, scope.peer_id },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "channel/account/peer scope `{s}` / any-account / `{s}` `{s}`",
        .{ scope.channel, scope.peer_kind, scope.peer_id },
    );
}

fn bindingValidationMessageAlloc(
    allocator: std.mem.Allocator,
    kind: enum { duplicate, conflict },
    current_index: usize,
    existing_index: usize,
    scope: AgentBindingScope,
) ![]const u8 {
    const scope_label = try bindingScopeLabelAlloc(allocator, scope);
    defer allocator.free(scope_label);

    return switch (kind) {
        .duplicate => std.fmt.allocPrint(
            allocator,
            "binding #{d} duplicates binding #{d} for {s}",
            .{ current_index + 1, existing_index + 1, scope_label },
        ),
        .conflict => std.fmt.allocPrint(
            allocator,
            "binding #{d} conflicts with binding #{d}: {s} can target only one agent",
            .{ current_index + 1, existing_index + 1, scope_label },
        ),
    };
}

fn agentErrorResponse(
    allocator: std.mem.Allocator,
    http_status: []const u8,
    resource: []const u8,
    status: []const u8,
    error_code: []const u8,
    message: []const u8,
    apply_state: ?[]const u8,
) ApiResponse {
    const body = std.json.Stringify.valueAlloc(allocator, AgentErrorResponse{
        .resource = resource,
        .status = status,
        .error_code = error_code,
        .@"error" = message,
        .apply_state = apply_state,
    }, .{
        .emit_null_optional_fields = false,
    }) catch return helpers.serverError();

    return .{
        .status = http_status,
        .content_type = "application/json",
        .body = body,
    };
}

const PrimaryModelRef = struct {
    provider: []const u8,
    model: []const u8,
};

fn resolveProviderModel(provider_field: ?[]const u8, model_field: []const u8) ?PrimaryModelRef {
    if (provider_field) |provider| {
        return .{ .provider = provider, .model = model_field };
    }
    return splitPrimaryModelRef(model_field);
}

fn splitPrimaryModelRef(primary: []const u8) ?PrimaryModelRef {
    if (std.mem.startsWith(u8, primary, "custom:")) {
        const proto_start = std.mem.indexOf(u8, primary, "://") orelse return null;
        var i: usize = proto_start + 3;
        var model_start: ?usize = null;
        while (i + 3 < primary.len) : (i += 1) {
            if (primary[i] != '/' or primary[i + 1] != 'v') continue;
            var j = i + 2;
            var has_digit = false;
            while (j < primary.len and std.ascii.isDigit(primary[j])) : (j += 1) {
                has_digit = true;
            }
            if (!has_digit) continue;
            if (j < primary.len and primary[j] == '/') {
                if (j + 1 >= primary.len) return null;
                model_start = j + 1;
                break;
            }
        }
        const split_at = model_start orelse return null;
        return .{
            .provider = primary[0 .. split_at - 1],
            .model = primary[split_at..],
        };
    }

    const slash = std.mem.indexOfScalar(u8, primary, '/') orelse return null;
    if (slash == 0 or slash + 1 >= primary.len) return null;
    return .{
        .provider = primary[0..slash],
        .model = primary[slash + 1 ..],
    };
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "parseConfigPath: valid path" {
    const p = parseConfigPath("/api/instances/nullclaw/my-agent/config").?;
    try std.testing.expectEqualStrings("nullclaw", p.component);
    try std.testing.expectEqualStrings("my-agent", p.name);
}

test "parseConfigPath: handles query string" {
    const p = parseConfigPath("/api/instances/nullclaw/my-agent/config?resolve=true").?;
    try std.testing.expectEqualStrings("nullclaw", p.component);
    try std.testing.expectEqualStrings("my-agent", p.name);
}

test "parseConfigPath: rejects path without /config suffix" {
    try std.testing.expect(parseConfigPath("/api/instances/nullclaw/my-agent") == null);
}

test "parseConfigPath: rejects path with extra segments" {
    try std.testing.expect(parseConfigPath("/api/instances/nullclaw/my-agent/config/extra") == null);
}

test "parseConfigPath: rejects path without name" {
    try std.testing.expect(parseConfigPath("/api/instances/nullclaw//config") == null);
}

test "isConfigPath detects config suffix" {
    try std.testing.expect(isConfigPath("/api/instances/nullclaw/my-agent/config"));
    try std.testing.expect(isConfigPath("/api/instances/nullclaw/my-agent/config?resolve=true"));
    try std.testing.expect(!isConfigPath("/api/instances/nullclaw/my-agent"));
    try std.testing.expect(!isConfigPath("/api/instances/nullclaw/my-agent/logs"));
}

test "shouldResolve detects resolve param" {
    try std.testing.expect(shouldResolve("/api/instances/nullclaw/my-agent/config?resolve=true"));
    try std.testing.expect(!shouldResolve("/api/instances/nullclaw/my-agent/config"));
}

test "agent config paths parse correctly" {
    const profiles = parseAgentProfilesPath("/api/instances/nullclaw/my-agent/agents/profiles?view=full").?;
    try std.testing.expectEqualStrings("nullclaw", profiles.component);
    try std.testing.expectEqualStrings("my-agent", profiles.name);
    try std.testing.expect(isAgentProfilesPath("/api/instances/nullclaw/my-agent/agents/profiles"));
    try std.testing.expect(!isAgentProfilesPath("/api/instances/nullclaw/my-agent/config"));

    const bindings = parseAgentBindingsPath("/api/instances/nullclaw/my-agent/agents/bindings").?;
    try std.testing.expectEqualStrings("nullclaw", bindings.component);
    try std.testing.expectEqualStrings("my-agent", bindings.name);
    try std.testing.expect(isAgentBindingsPath("/api/instances/nullclaw/my-agent/agents/bindings"));
    try std.testing.expect(!isAgentBindingsPath("/api/instances/nullclaw/my-agent/logs"));
}

test "handleGet returns 404 when no config file exists" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-config-api-get";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);
    var s = state_mod.State.init(allocator, "/tmp/test-state.json");
    defer s.deinit();

    const resp = handleGet(allocator, p, &s, "nullclaw", "my-agent", false);
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"config not found\"}", resp.body);
}

test "handlePut writes config file" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-config-api-put";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);

    const body = "{\"key\":\"value\"}";
    const resp = handlePut(allocator, p, "nullclaw", "my-agent", body);
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expectEqualStrings("{\"status\":\"saved\"}", resp.body);

    // Verify the file was written.
    const config_path = try p.instanceConfig(allocator, "nullclaw", "my-agent");
    defer allocator.free(config_path);

    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(contents);
    try std.testing.expectEqualStrings(body, contents);
}

test "handleGet reads written config" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-config-api-roundtrip";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);
    var s = state_mod.State.init(allocator, "/tmp/test-state-roundtrip.json");
    defer s.deinit();

    const body = "{\"port\":8080}";
    const put_resp = handlePut(allocator, p, "nullclaw", "my-agent", body);
    try std.testing.expectEqualStrings("200 OK", put_resp.status);

    const get_resp = handleGet(allocator, p, &s, "nullclaw", "my-agent", false);
    defer allocator.free(get_resp.body);
    try std.testing.expectEqualStrings("200 OK", get_resp.status);
    try std.testing.expectEqualStrings(body, get_resp.body);
}

test "handlePatch writes config (same as PUT for now)" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-config-api-patch";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);

    const body = "{\"updated\":true}";
    const resp = handlePatch(allocator, p, "nullclaw", "my-agent", body);
    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expectEqualStrings("{\"status\":\"saved\"}", resp.body);
}

test "handlePutAgentProfiles writes config and handleGetAgentProfiles reads normalized payload" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-agent-profiles";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);

    const put_body =
        \\{
        \\  "defaults": { "model_primary": "openrouter/openai/gpt-5-mini" },
        \\  "profiles": [
        \\    {
        \\      "id": "writer",
        \\      "provider": "openrouter",
        \\      "model": "anthropic/claude-sonnet-4",
        \\      "system_prompt": "Write clearly",
        \\      "temperature": 0.2,
        \\      "max_depth": 4
        \\    }
        \\  ]
        \\}
    ;

    const put_resp = handlePutAgentProfiles(allocator, p, "nullclaw", "my-agent", put_body);
    defer allocator.free(put_resp.body);
    try std.testing.expectEqualStrings("200 OK", put_resp.status);
    var put_parsed = try std.json.parseFromSlice(std.json.Value, allocator, put_resp.body, .{});
    defer put_parsed.deinit();
    const put_obj = put_parsed.value.object;
    try std.testing.expectEqual(@as(i64, agent_contract_version), put_obj.get("contract_version").?.integer);
    try std.testing.expectEqualStrings("agent_profiles", put_obj.get("resource").?.string);
    try std.testing.expectEqualStrings("config_saved", put_obj.get("apply_state").?.string);
    try std.testing.expectEqualStrings("component_defined", put_obj.get("runtime_effect").?.string);
    try std.testing.expectEqualStrings("preserve_by_id", put_obj.get("unknown_fields").?.string);
    try std.testing.expectEqual(@as(i64, 1), put_obj.get("profiles_count").?.integer);

    const config_path = try p.instanceConfig(allocator, "nullclaw", "my-agent");
    defer allocator.free(config_path);
    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"agents\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"primary\": \"openrouter/openai/gpt-5-mini\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"id\": \"writer\"") != null);

    const get_resp = handleGetAgentProfiles(allocator, p, "nullclaw", "my-agent");
    defer allocator.free(get_resp.body);
    try std.testing.expectEqualStrings("200 OK", get_resp.status);
    var get_parsed = try std.json.parseFromSlice(std.json.Value, allocator, get_resp.body, .{});
    defer get_parsed.deinit();
    const get_obj = get_parsed.value.object;
    try std.testing.expectEqual(@as(i64, agent_contract_version), get_obj.get("contract_version").?.integer);
    try std.testing.expectEqualStrings("agent_profiles", get_obj.get("resource").?.string);
    try std.testing.expectEqualStrings("instance", get_obj.get("ownership").?.string);
    try std.testing.expectEqualStrings("preserve_by_id", get_obj.get("field_policy").?.object.get("unknown_fields").?.string);
    try std.testing.expect(std.mem.indexOf(u8, get_resp.body, "\"model_primary\": \"openrouter/openai/gpt-5-mini\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_resp.body, "\"id\": \"writer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_resp.body, "\"provider\": \"openrouter\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_resp.body, "\"model\": \"anthropic/claude-sonnet-4\"") != null);
}

test "handlePutAgentProfiles preserves unknown fields" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-agent-profiles-merge";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);

    const initial =
        \\{
        \\  "agents": {
        \\    "list": [
        \\      {
        \\        "id": "writer",
        \\        "provider": "openrouter",
        \\        "model": "openai/gpt-4",
        \\        "extra": { "mode": "strict" },
        \\        "tools": ["web"]
        \\      }
        \\    ]
        \\  }
        \\}
    ;
    const seed_resp = handlePut(allocator, p, "nullclaw", "my-agent", initial);
    try std.testing.expectEqualStrings("200 OK", seed_resp.status);

    const update_body =
        \\{
        \\  "profiles": [
        \\    { "id": "writer", "provider": "openrouter", "model": "openai/gpt-5-mini" }
        \\  ]
        \\}
    ;
    const update_resp = handlePutAgentProfiles(allocator, p, "nullclaw", "my-agent", update_body);
    defer allocator.free(update_resp.body);
    try std.testing.expectEqualStrings("200 OK", update_resp.status);

    const config_path = try p.instanceConfig(allocator, "nullclaw", "my-agent");
    defer allocator.free(config_path);
    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"extra\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"tools\"") != null);
}

test "handlePutAgentProfiles returns structured validation error" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-agent-profiles-error";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);

    const resp = handlePutAgentProfiles(allocator, p, "nullclaw", "my-agent",
        \\{
        \\  "profiles": [
        \\    { "provider": "openrouter", "model": "openai/gpt-5-mini" }
        \\  ]
        \\}
    );
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("400 Bad Request", resp.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("agent_profiles", obj.get("resource").?.string);
    try std.testing.expectEqualStrings("validation_failed", obj.get("status").?.string);
    try std.testing.expectEqualStrings("profile_id_required", obj.get("error_code").?.string);
    try std.testing.expectEqualStrings("unchanged", obj.get("apply_state").?.string);
}

test "handleGetAgentProfiles returns structured not-found error" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-agent-profiles-get-missing";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);

    const resp = handleGetAgentProfiles(allocator, p, "nullclaw", "missing");
    defer allocator.free(resp.body);
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("agent_profiles", obj.get("resource").?.string);
    try std.testing.expectEqualStrings("not_found", obj.get("status").?.string);
    try std.testing.expectEqualStrings("instance_config_not_found", obj.get("error_code").?.string);
}

test "handlePutAgentBindings validates agent ids and normalizes legacy topic ids" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-agent-bindings";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);

    const profiles_body =
        \\{
        \\  "profiles": [
        \\    {
        \\      "id": "ops",
        \\      "provider": "openrouter",
        \\      "model": "openai/gpt-5-mini"
        \\    }
        \\  ]
        \\}
    ;
    const profiles_resp = handlePutAgentProfiles(allocator, p, "nullclaw", "my-agent", profiles_body);
    defer allocator.free(profiles_resp.body);
    try std.testing.expectEqualStrings("200 OK", profiles_resp.status);

    const invalid_resp = handlePutAgentBindings(allocator, p, "nullclaw", "my-agent",
        \\{
        \\  "bindings": [
        \\    {
        \\      "agent_id": "missing",
        \\      "match": {
        \\        "channel": "telegram",
        \\        "peer": { "kind": "chat", "id": "123" }
        \\      }
        \\    }
        \\  ]
        \\}
    );
    defer allocator.free(invalid_resp.body);
    try std.testing.expectEqualStrings("400 Bad Request", invalid_resp.status);
    var invalid_parsed = try std.json.parseFromSlice(std.json.Value, allocator, invalid_resp.body, .{});
    defer invalid_parsed.deinit();
    const invalid_obj = invalid_parsed.value.object;
    try std.testing.expectEqualStrings("agent_bindings", invalid_obj.get("resource").?.string);
    try std.testing.expectEqualStrings("validation_failed", invalid_obj.get("status").?.string);
    try std.testing.expectEqualStrings("binding_agent_id_unknown", invalid_obj.get("error_code").?.string);
    try std.testing.expectEqualStrings("unchanged", invalid_obj.get("apply_state").?.string);

    const valid_resp = handlePutAgentBindings(allocator, p, "nullclaw", "my-agent",
        \\{
        \\  "bindings": [
        \\    {
        \\      "agent_id": "ops",
        \\      "match": {
        \\        "channel": "telegram",
        \\        "account_id": "bot-a",
        \\        "peer": { "kind": "chat", "id": "123#topic:456" }
        \\      }
        \\    }
        \\  ]
        \\}
    );
    defer allocator.free(valid_resp.body);
    try std.testing.expectEqualStrings("200 OK", valid_resp.status);
    var valid_parsed = try std.json.parseFromSlice(std.json.Value, allocator, valid_resp.body, .{});
    defer valid_parsed.deinit();
    const valid_obj = valid_parsed.value.object;
    try std.testing.expectEqual(@as(i64, agent_contract_version), valid_obj.get("contract_version").?.integer);
    try std.testing.expectEqualStrings("agent_bindings", valid_obj.get("resource").?.string);
    try std.testing.expectEqualStrings("config_saved", valid_obj.get("apply_state").?.string);
    try std.testing.expectEqualStrings("component_defined", valid_obj.get("runtime_effect").?.string);
    try std.testing.expectEqualStrings("replace_all", valid_obj.get("unknown_fields").?.string);
    try std.testing.expectEqual(@as(i64, 1), valid_obj.get("bindings_count").?.integer);

    const get_resp = handleGetAgentBindings(allocator, p, "nullclaw", "my-agent");
    defer allocator.free(get_resp.body);
    try std.testing.expectEqualStrings("200 OK", get_resp.status);
    var get_parsed = try std.json.parseFromSlice(std.json.Value, allocator, get_resp.body, .{});
    defer get_parsed.deinit();
    const get_obj = get_parsed.value.object;
    try std.testing.expectEqual(@as(i64, agent_contract_version), get_obj.get("contract_version").?.integer);
    try std.testing.expectEqualStrings("agent_bindings", get_obj.get("resource").?.string);
    try std.testing.expectEqualStrings("instance", get_obj.get("ownership").?.string);
    try std.testing.expectEqualStrings("replace_all", get_obj.get("field_policy").?.object.get("unknown_fields").?.string);
    try std.testing.expect(std.mem.indexOf(u8, get_resp.body, "\"agent_id\": \"ops\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_resp.body, "\"account_id\": \"bot-a\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, get_resp.body, "\"id\": \"123:thread:456\"") != null);
}

test "handlePutAgentBindings rejects duplicate and conflicting exact scopes" {
    const allocator = std.testing.allocator;
    const tmp_root = "/tmp/nullhubx-test-agent-binding-conflicts";
    std.fs.deleteTreeAbsolute(tmp_root) catch {};
    defer std.fs.deleteTreeAbsolute(tmp_root) catch {};

    var p = try paths_mod.Paths.init(allocator, tmp_root);
    defer p.deinit(allocator);

    const profiles_body =
        \\{
        \\  "profiles": [
        \\    {
        \\      "id": "ops",
        \\      "provider": "openrouter",
        \\      "model": "openai/gpt-5-mini"
        \\    },
        \\    {
        \\      "id": "support",
        \\      "provider": "openrouter",
        \\      "model": "openai/gpt-5-mini"
        \\    }
        \\  ]
        \\}
    ;
    const profiles_resp = handlePutAgentProfiles(allocator, p, "nullclaw", "conflict-demo", profiles_body);
    defer allocator.free(profiles_resp.body);
    try std.testing.expectEqualStrings("200 OK", profiles_resp.status);

    const duplicate_resp = handlePutAgentBindings(allocator, p, "nullclaw", "conflict-demo",
        \\{
        \\  "bindings": [
        \\    {
        \\      "agent_id": "ops",
        \\      "match": {
        \\        "channel": "telegram",
        \\        "account_id": "main",
        \\        "peer": { "kind": "group", "id": "-100123" }
        \\      }
        \\    },
        \\    {
        \\      "agent_id": "ops",
        \\      "match": {
        \\        "channel": "telegram",
        \\        "account_id": "main",
        \\        "peer": { "kind": "group", "id": "-100123" }
        \\      }
        \\    }
        \\  ]
        \\}
    );
    defer allocator.free(duplicate_resp.body);
    try std.testing.expectEqualStrings("400 Bad Request", duplicate_resp.status);
    var duplicate_parsed = try std.json.parseFromSlice(std.json.Value, allocator, duplicate_resp.body, .{});
    defer duplicate_parsed.deinit();
    const duplicate_obj = duplicate_parsed.value.object;
    try std.testing.expectEqualStrings("binding_route_duplicate", duplicate_obj.get("error_code").?.string);
    try std.testing.expect(std.mem.indexOf(u8, duplicate_obj.get("error").?.string, "binding #2 duplicates binding #1") != null);

    const conflict_resp = handlePutAgentBindings(allocator, p, "nullclaw", "conflict-demo",
        \\{
        \\  "bindings": [
        \\    {
        \\      "agent_id": "ops",
        \\      "match": {
        \\        "channel": "telegram",
        \\        "account_id": "main",
        \\        "peer": { "kind": "group", "id": "-100123#topic:42" }
        \\      }
        \\    },
        \\    {
        \\      "agent_id": "support",
        \\      "match": {
        \\        "channel": "telegram",
        \\        "account_id": "main",
        \\        "peer": { "kind": "group", "id": "-100123:thread:42" }
        \\      }
        \\    }
        \\  ]
        \\}
    );
    defer allocator.free(conflict_resp.body);
    try std.testing.expectEqualStrings("400 Bad Request", conflict_resp.status);
    var conflict_parsed = try std.json.parseFromSlice(std.json.Value, allocator, conflict_resp.body, .{});
    defer conflict_parsed.deinit();
    const conflict_obj = conflict_parsed.value.object;
    try std.testing.expectEqualStrings("binding_scope_conflict", conflict_obj.get("error_code").?.string);
    try std.testing.expect(std.mem.indexOf(u8, conflict_obj.get("error").?.string, "binding #2 conflicts with binding #1") != null);
}
