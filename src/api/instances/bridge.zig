const std = @import("std");
const helpers = @import("../helpers.zig");
const managed_skills = @import("../../managed_skills.zig");
const command_service = @import("../../core/component_command_service.zig");
const legacy = @import("../instances.zig");
const state_mod = @import("../../core/state.zig");
const manager_mod = @import("../../supervisor/manager.zig");
const paths_mod = @import("../../core/paths.zig");

pub const ApiResponse = helpers.ApiResponse;

pub fn handleProviderHealth(allocator: std.mem.Allocator, s: *state_mod.State, manager: *manager_mod.Manager, paths: paths_mod.Paths, component: []const u8, name: []const u8) ApiResponse {
    const entry = s.getInstance(component, name) orelse return helpers.notFound();

    const config_path = paths.instanceConfig(allocator, component, name) catch return helpers.serverError();
    defer allocator.free(config_path);

    const file = std.fs.openFileAbsolute(config_path, .{}) catch return .{
        .status = "404 Not Found",
        .content_type = "application/json",
        .body = "{\"error\":\"config not found\"}",
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch return helpers.serverError();
    defer allocator.free(contents);

    const parsed = std.json.parseFromSlice(legacy.ProviderHealthConfig, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return helpers.badRequest("{\"error\":\"invalid config JSON\"}");
    defer parsed.deinit();

    var provider: []const u8 = "";
    var model: []const u8 = "";
    var configured = false;
    var provider_base_url: ?[]const u8 = null;

    if (parsed.value.agents) |agents| {
        if (agents.defaults) |defaults| {
            if (defaults.model) |model_cfg| {
                if (model_cfg.primary) |primary| {
                    if (primary.len > 0) {
                        if (std.mem.indexOfScalar(u8, primary, '/')) |sep| {
                            provider = primary[0..sep];
                            model = primary[sep + 1 ..];
                        } else {
                            provider = primary;
                            model = primary;
                        }
                    }
                }
            }
        }
    }

    if (parsed.value.models) |models_cfg| {
        if (models_cfg.providers) |providers| {
            if (provider.len > 0) {
                if (providers.map.get(provider)) |provider_entry| {
                    if (provider_entry.base_url) |u| {
                        if (u.len > 0) provider_base_url = u;
                    }
                    if (provider_base_url == null) {
                        if (provider_entry.api_url) |u| {
                            if (u.len > 0) provider_base_url = u;
                        }
                    }
                    if (provider_entry.api_key) |k| {
                        if (k.len > 0) configured = true;
                    }
                }
            }
            if (provider.len == 0) {
                var it = providers.map.iterator();
                while (it.next()) |provider_entry| {
                    provider = provider_entry.key_ptr.*;
                    if (provider_entry.value_ptr.base_url) |u| {
                        if (u.len > 0) provider_base_url = u;
                    }
                    if (provider_base_url == null) {
                        if (provider_entry.value_ptr.api_url) |u| {
                            if (u.len > 0) provider_base_url = u;
                        }
                    }
                    if (provider_entry.value_ptr.api_key) |k| {
                        if (k.len > 0) configured = true;
                    }
                    break;
                }
            }
            if (!configured and provider.len > 0) {
                if (providers.map.get(provider)) |provider_entry| {
                    if (provider_entry.base_url) |u| {
                        if (u.len > 0) provider_base_url = u;
                    }
                    if (provider_base_url == null) {
                        if (provider_entry.api_url) |u| {
                            if (u.len > 0) provider_base_url = u;
                        }
                    }
                    if (provider_entry.api_key) |k| {
                        if (k.len > 0) configured = true;
                    }
                }
            }
        }
    }
    if (provider.len > 0 and !legacy.providerRequiresApiKey(provider, provider_base_url)) {
        configured = true;
    }

    const running = blk: {
        if (manager.getStatus(component, name)) |st| {
            break :blk st.status == .running;
        }
        break :blk false;
    };

    var status: []const u8 = "unknown";
    var reason: []const u8 = "not_probed";
    var live_ok = false;
    var status_code: ?u16 = null;

    if (provider.len == 0) {
        status = "error";
        reason = "provider_not_detected";
    } else if (!running) {
        status = "error";
        reason = "instance_not_running";
    } else {
        const probe = legacy.probeComponentProvider(allocator, paths, entry, component, name, provider, model);
        live_ok = probe.live_ok;
        status_code = probe.status_code;
        status = if (probe.live_ok) "ok" else "error";
        reason = probe.reason;
    }

    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    buf.appendSlice("{\"provider\":\"") catch return helpers.serverError();
    helpers.appendEscaped(&buf, provider) catch return helpers.serverError();
    buf.appendSlice("\",\"model\":\"") catch return helpers.serverError();
    helpers.appendEscaped(&buf, model) catch return helpers.serverError();
    buf.appendSlice("\",\"configured\":") catch return helpers.serverError();
    buf.appendSlice(if (configured) "true" else "false") catch return helpers.serverError();
    buf.appendSlice(",\"running\":") catch return helpers.serverError();
    buf.appendSlice(if (running) "true" else "false") catch return helpers.serverError();
    buf.appendSlice(",\"live_ok\":") catch return helpers.serverError();
    buf.appendSlice(if (live_ok) "true" else "false") catch return helpers.serverError();
    buf.appendSlice(",\"status\":\"") catch return helpers.serverError();
    helpers.appendEscaped(&buf, status) catch return helpers.serverError();
    buf.appendSlice("\",\"reason\":\"") catch return helpers.serverError();
    helpers.appendEscaped(&buf, reason) catch return helpers.serverError();
    buf.appendSlice("\"") catch return helpers.serverError();
    if (status_code) |code| {
        buf.writer().print(",\"status_code\":{d}", .{code}) catch return helpers.serverError();
    }
    buf.appendSlice("}") catch return helpers.serverError();

    const body = buf.toOwnedSlice() catch return helpers.serverError();
    return helpers.jsonOk(body);
}

pub fn handleHistory(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, target: []const u8) ApiResponse {
    const session_id = legacy.queryParamValueAlloc(allocator, target, "session_id") catch return helpers.serverError();
    defer if (session_id) |value| allocator.free(value);

    const limit = legacy.queryParamUsize(target, "limit", if (session_id != null) 100 else 50);
    const offset = legacy.queryParamUsize(target, "offset", 0);

    var limit_buf: [32]u8 = undefined;
    var offset_buf: [32]u8 = undefined;
    const limit_str = std.fmt.bufPrint(&limit_buf, "{d}", .{limit}) catch return helpers.serverError();
    const offset_str = std.fmt.bufPrint(&offset_buf, "{d}", .{offset}) catch return helpers.serverError();

    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer args.deinit(allocator);

    args.append(allocator, "history") catch return helpers.serverError();
    if (session_id) |value| {
        if (value.len == 0) return helpers.badRequest("{\"error\":\"session_id is required\"}");
        args.append(allocator, "show") catch return helpers.serverError();
        args.append(allocator, value) catch return helpers.serverError();
    } else {
        args.append(allocator, "list") catch return helpers.serverError();
    }
    args.append(allocator, "--limit") catch return helpers.serverError();
    args.append(allocator, limit_str) catch return helpers.serverError();
    args.append(allocator, "--offset") catch return helpers.serverError();
    args.append(allocator, offset_str) catch return helpers.serverError();
    args.append(allocator, "--json") catch return helpers.serverError();

    return command_service.runInstanceCliJson(allocator, s, paths, component, name, args.items);
}

pub fn handleMemory(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, target: []const u8) ApiResponse {
    const key = legacy.queryParamValueAlloc(allocator, target, "key") catch return helpers.serverError();
    defer if (key) |value| allocator.free(value);
    const query = legacy.queryParamValueAlloc(allocator, target, "query") catch return helpers.serverError();
    defer if (query) |value| allocator.free(value);
    const category = legacy.queryParamValueAlloc(allocator, target, "category") catch return helpers.serverError();
    defer if (category) |value| allocator.free(value);

    const default_limit: usize = if (query != null) 6 else 20;
    const limit = legacy.queryParamUsize(target, "limit", default_limit);

    var limit_buf: [32]u8 = undefined;
    const limit_str = std.fmt.bufPrint(&limit_buf, "{d}", .{limit}) catch return helpers.serverError();

    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer args.deinit(allocator);

    args.append(allocator, "memory") catch return helpers.serverError();
    if (legacy.queryParamBool(target, "stats")) {
        args.append(allocator, "stats") catch return helpers.serverError();
        args.append(allocator, "--json") catch return helpers.serverError();
        return command_service.runInstanceCliJson(allocator, s, paths, component, name, args.items);
    }

    if (key) |value| {
        if (value.len == 0) return helpers.badRequest("{\"error\":\"key is required\"}");
        args.append(allocator, "get") catch return helpers.serverError();
        args.append(allocator, value) catch return helpers.serverError();
        args.append(allocator, "--json") catch return helpers.serverError();
        return command_service.runInstanceCliJson(allocator, s, paths, component, name, args.items);
    }

    if (query) |value| {
        if (value.len == 0) return helpers.badRequest("{\"error\":\"query is required\"}");
        args.append(allocator, "search") catch return helpers.serverError();
        args.append(allocator, value) catch return helpers.serverError();
        args.append(allocator, "--limit") catch return helpers.serverError();
        args.append(allocator, limit_str) catch return helpers.serverError();
        args.append(allocator, "--json") catch return helpers.serverError();
        return command_service.runInstanceCliJson(allocator, s, paths, component, name, args.items);
    }

    args.append(allocator, "list") catch return helpers.serverError();
    if (category) |value| {
        if (value.len > 0) {
            args.append(allocator, "--category") catch return helpers.serverError();
            args.append(allocator, value) catch return helpers.serverError();
        }
    }
    args.append(allocator, "--limit") catch return helpers.serverError();
    args.append(allocator, limit_str) catch return helpers.serverError();
    args.append(allocator, "--json") catch return helpers.serverError();
    return command_service.runInstanceCliJson(allocator, s, paths, component, name, args.items);
}

pub fn handleCapabilities(
    allocator: std.mem.Allocator,
    s: *state_mod.State,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) ApiResponse {
    return @import("capabilities.zig").handleGet(allocator, s, paths, component, name);
}

pub fn handleSkills(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, target: []const u8) ApiResponse {
    _ = s.getInstance(component, name) orelse return helpers.notFound();
    if (legacy.queryParamBool(target, "catalog")) return handleSkillsCatalog(allocator, component);
    const skill_name = legacy.queryParamValueAlloc(allocator, target, "name") catch return helpers.serverError();
    defer if (skill_name) |value| allocator.free(value);

    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer args.deinit(allocator);

    args.append(allocator, "skills") catch return helpers.serverError();
    if (skill_name) |value| {
        if (value.len == 0) return helpers.badRequest("{\"error\":\"name is required\"}");
        args.append(allocator, "info") catch return helpers.serverError();
        args.append(allocator, value) catch return helpers.serverError();
    } else {
        args.append(allocator, "list") catch return helpers.serverError();
    }
    args.append(allocator, "--json") catch return helpers.serverError();
    return command_service.runInstanceCliJson(allocator, s, paths, component, name, args.items);
}

pub fn handleSkillsInstall(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, body: []const u8) ApiResponse {
    _ = s.getInstance(component, name) orelse return helpers.notFound();
    if (!std.mem.eql(u8, component, "nullclaw")) {
        return helpers.badRequest("{\"error\":\"skill installation is only supported for nullclaw instances\"}");
    }

    const parsed = std.json.parseFromSlice(struct {
        bundled: ?[]const u8 = null,
        clawhub_slug: ?[]const u8 = null,
        source: ?[]const u8 = null,
    }, allocator, body, .{
        .ignore_unknown_fields = true,
    }) catch return helpers.badRequest("{\"error\":\"invalid JSON body\"}");
    defer parsed.deinit();

    const bundled_name = if (parsed.value.bundled) |value| if (value.len > 0) value else null else null;
    const clawhub_slug = if (parsed.value.clawhub_slug) |value| if (value.len > 0) value else null else null;
    const source = if (parsed.value.source) |value| if (value.len > 0) value else null else null;

    var selected: usize = 0;
    if (bundled_name != null) selected += 1;
    if (clawhub_slug != null) selected += 1;
    if (source != null) selected += 1;
    if (selected != 1) {
        return helpers.badRequest("{\"error\":\"provide exactly one of bundled, clawhub_slug, or source\"}");
    }

    if (bundled_name) |value| {
        const workspace_dir = instanceWorkspaceDir(allocator, paths, component, name) catch return helpers.serverError();
        defer allocator.free(workspace_dir);
        const disposition = managed_skills.installBundledSkill(allocator, workspace_dir, value) catch |err| switch (err) {
            error.SkillNotFound => return helpers.notFound(),
            else => return helpers.serverError(),
        };
        const config_path = paths.instanceConfig(allocator, component, name) catch return helpers.serverError();
        defer allocator.free(config_path);
        const restart_required = managed_skills.syncBundledSkillRuntime(allocator, config_path, value) catch |err| switch (err) {
            error.SkillNotFound => return helpers.notFound(),
            else => return helpers.serverError(),
        };
        const resp_body = std.json.Stringify.valueAlloc(allocator, .{
            .status = @tagName(disposition),
            .bundled = value,
            .restart_required = restart_required,
        }, .{}) catch return helpers.serverError();
        return helpers.jsonOk(resp_body);
    }

    if (clawhub_slug) |value| {
        const workspace_dir = instanceWorkspaceDir(allocator, paths, component, name) catch return helpers.serverError();
        defer allocator.free(workspace_dir);

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "clawhub", "install", value },
            .cwd = workspace_dir,
            .max_output_bytes = 64 * 1024,
        }) catch |err| switch (err) {
            error.FileNotFound => return command_service.jsonCliConflict(
                allocator,
                "clawhub_not_available",
                "clawhub CLI is not installed on the nullhubx host",
                null,
                null,
            ),
            else => return command_service.jsonCliConflict(
                allocator,
                "clawhub_exec_failed",
                "Failed to execute clawhub install",
                null,
                null,
            ),
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }

        const success = switch (result.term) {
            .Exited => |code| code == 0,
            else => false,
        };
        if (!success) {
            return command_service.jsonCliConflict(
                allocator,
                "clawhub_install_failed",
                "clawhub install failed",
                result.stderr,
                result.stdout,
            );
        }

        const resp_body = std.json.Stringify.valueAlloc(allocator, .{
            .status = "installed",
            .clawhub_slug = value,
        }, .{}) catch return helpers.serverError();
        return helpers.jsonOk(resp_body);
    }

    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer args.deinit(allocator);
    args.append(allocator, "skills") catch return helpers.serverError();
    args.append(allocator, "install") catch return helpers.serverError();
    args.append(allocator, source.?) catch return helpers.serverError();

    const captured = command_service.runInstanceCliCaptured(allocator, s, paths, component, name, args.items);
    const result = switch (captured) {
        .response => |resp| {
            if (std.mem.eql(u8, resp.status, "200 OK")) {
                return .{
                    .status = "409 Conflict",
                    .content_type = resp.content_type,
                    .body = resp.body,
                };
            }
            return resp;
        },
        .result => |value| value,
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (!result.success) {
        return command_service.jsonCliConflict(
            allocator,
            "skills_install_failed",
            "Failed to install skill from source",
            result.stderr,
            result.stdout,
        );
    }

    const resp_body = std.json.Stringify.valueAlloc(allocator, .{
        .status = "installed",
        .source = source.?,
    }, .{}) catch return helpers.serverError();
    return helpers.jsonOk(resp_body);
}

pub fn handleSkillsRemove(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, target: []const u8) ApiResponse {
    if (!std.mem.eql(u8, component, "nullclaw")) {
        return helpers.badRequest("{\"error\":\"skill removal is only supported for nullclaw instances\"}");
    }
    const skill_name = legacy.queryParamValueAlloc(allocator, target, "name") catch return helpers.serverError();
    defer if (skill_name) |value| allocator.free(value);
    if (skill_name == null or skill_name.?.len == 0) {
        return helpers.badRequest("{\"error\":\"name is required\"}");
    }

    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer args.deinit(allocator);
    args.append(allocator, "skills") catch return helpers.serverError();
    args.append(allocator, "remove") catch return helpers.serverError();
    args.append(allocator, skill_name.?) catch return helpers.serverError();

    const captured = command_service.runInstanceCliCaptured(allocator, s, paths, component, name, args.items);
    const result = switch (captured) {
        .response => |resp| {
            if (std.mem.eql(u8, resp.status, "200 OK")) {
                return .{
                    .status = "409 Conflict",
                    .content_type = resp.content_type,
                    .body = resp.body,
                };
            }
            return resp;
        },
        .result => |value| value,
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    if (!result.success) {
        return command_service.jsonCliConflict(
            allocator,
            "skills_remove_failed",
            "Failed to remove skill",
            result.stderr,
            result.stdout,
        );
    }

    const resp_body = std.json.Stringify.valueAlloc(allocator, .{
        .status = "removed",
        .name = skill_name.?,
    }, .{}) catch return helpers.serverError();
    return helpers.jsonOk(resp_body);
}

fn instanceWorkspaceDir(allocator: std.mem.Allocator, paths: paths_mod.Paths, component: []const u8, name: []const u8) ![]u8 {
    const inst_dir = try paths.instanceDir(allocator, component, name);
    defer allocator.free(inst_dir);
    return try std.fs.path.join(allocator, &.{ inst_dir, "workspace" });
}

fn handleSkillsCatalog(allocator: std.mem.Allocator, component: []const u8) ApiResponse {
    const bundled = managed_skills.catalogForComponent(component);
    var entries = std.array_list.Managed(managed_skills.CatalogEntry).init(allocator);
    defer entries.deinit();
    for (bundled) |skill| {
        entries.append(skill.entry) catch return helpers.serverError();
    }
    const body = std.json.Stringify.valueAlloc(allocator, entries.items, .{
        .emit_null_optional_fields = false,
    }) catch return helpers.serverError();
    return helpers.jsonOk(body);
}
