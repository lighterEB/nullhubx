const std = @import("std");
const state_mod = @import("state.zig");

/// Resolve _ref references in a config JSON by merging values from saved providers/channels.
/// Caller owns the returned memory.
pub fn resolveConfigRefs(
    allocator: std.mem.Allocator,
    config_json: []const u8,
    state: *state_mod.State,
) ![]const u8 {
    // Parse the config JSON
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, config_json, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    const arena = parsed.arena.allocator();

    // Resolve providers refs
    if (parsed.value == .object) {
        const root_obj = &parsed.value.object;
        
        if (root_obj.getPtr("models")) |models| {
            if (models.* == .object) {
                if (models.object.getPtr("providers")) |providers| {
                    if (providers.* == .object) {
                        try resolveProvidersRefs(&providers.object, state);
                    }
                }
            }
        }

        // Resolve channels refs
        if (root_obj.getPtr("channels")) |channels| {
            if (channels.* == .object) {
                    try resolveChannelsRefs(arena, &channels.object, state);
            }
        }
    }

    // Serialize back to JSON
    return try std.json.Stringify.valueAlloc(allocator, parsed.value, .{ .whitespace = .indent_2 });
}

fn resolveProvidersRefs(providers: *std.json.ObjectMap, state: *state_mod.State) !void {
    var it = providers.iterator();
    while (it.next()) |entry| {
        const provider_config = entry.value_ptr;
        if (provider_config.* != .object) continue;

        const obj = &provider_config.*.object;

        // Check for _ref field
        if (obj.get("_ref")) |ref_val| {
            if (ref_val == .integer) {
                const ref_id: u32 = @intCast(ref_val.integer);
                if (state.getSavedProvider(ref_id)) |saved| {
                    // Merge saved provider values (only if not already set in config)
                    if (!obj.contains("api_key") and saved.api_key.len > 0) {
                        try obj.put("api_key", .{ .string = saved.api_key });
                    }
                    if (!obj.contains("base_url") and saved.provider.len > 0) {
                        // Some providers use base_url instead of provider name
                    }
                }
            }
        }
    }
}

fn resolveChannelsRefs(
    allocator: std.mem.Allocator,
    channels: *std.json.ObjectMap,
    state: *state_mod.State,
) !void {
    var it = channels.iterator();
    while (it.next()) |entry| {
        const channel_config = entry.value_ptr;
        if (channel_config.* != .object) continue;

        const obj = &channel_config.*.object;

        // Check for _ref field
        if (obj.get("_ref")) |ref_val| {
            if (ref_val == .integer) {
                const ref_id: u32 = @intCast(ref_val.integer);
                if (state.getSavedChannel(ref_id)) |saved| {
                    // Parse saved.config JSON and merge
                    if (saved.config.len > 0) {
                        const config_parsed = std.json.parseFromSlice(std.json.Value, allocator, saved.config, .{
                            .allocate = .alloc_always,
                            .ignore_unknown_fields = true,
                        }) catch continue;
                        defer config_parsed.deinit();

                        if (config_parsed.value == .object) {
                            var config_it = config_parsed.value.object.iterator();
                            while (config_it.next()) |config_entry| {
                                if (!obj.contains(config_entry.key_ptr.*)) {
                                    try obj.put(
                                        try allocator.dupe(u8, config_entry.key_ptr.*),
                                        try cloneJsonValue(allocator, config_entry.value_ptr.*),
                                    );
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

fn cloneJsonValue(allocator: std.mem.Allocator, val: std.json.Value) !std.json.Value {
    return switch (val) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .number_string => |s| .{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| {
            var new_arr = std.json.Array.init(allocator);
            try new_arr.ensureTotalCapacity(arr.items.len);
            for (arr.items) |item| {
                try new_arr.append(try cloneJsonValue(allocator, item));
            }
            return .{ .array = new_arr };
        },
        .object => |obj| {
            var new_obj = std.json.ObjectMap.init(allocator);
            try new_obj.ensureTotalCapacity(@intCast(obj.count()));
            var it = obj.iterator();
            while (it.next()) |entry| {
                try new_obj.put(
                    try allocator.dupe(u8, entry.key_ptr.*),
                    try cloneJsonValue(allocator, entry.value_ptr.*),
                );
            }
            return .{ .object = new_obj };
        },
    };
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "resolveConfigRefs returns original config when no refs" {
    const allocator = std.testing.allocator;
    var state = state_mod.State.init(allocator, "/tmp/test-refs-no-refs.json");
    defer state.deinit();

    const config = "{\"port\":8080}";
    const result = try resolveConfigRefs(allocator, config, &state);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"port\": 8080") != null);
}

test "resolveConfigRefs resolves provider _ref" {
    const allocator = std.testing.allocator;
    var state = state_mod.State.init(allocator, "/tmp/test-refs-provider.json");
    defer state.deinit();

    // Add a saved provider
    try state.addSavedProvider(.{
        .provider = "openrouter",
        .api_key = "sk-test-key",
    });

    const config = "{\"models\":{\"providers\":{\"openrouter\":{\"_ref\":1}}}}";
    const result = try resolveConfigRefs(allocator, config, &state);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"api_key\": \"sk-test-key\"") != null);
}
