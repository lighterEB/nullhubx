const std = @import("std");

pub fn deinitSavedProviders(state: anytype) void {
    for (state.saved_providers.items) |sp| {
        state.freeSavedProviderStrings(sp);
    }
    state.saved_providers.deinit();
}

pub fn getSavedProvider(state: anytype, id: u32) ?@TypeOf(state.saved_providers.items[0]) {
    for (state.saved_providers.items) |sp| {
        if (sp.id == id) return sp;
    }
    return null;
}

pub fn addSavedProvider(state: anytype, input: anytype, label_fn: anytype) !void {
    const id = nextProviderId(state.saved_providers.items);
    const name = try generateProviderName(state.allocator, state.saved_providers.items, input.provider, label_fn);
    errdefer state.allocator.free(name);
    const provider = try state.allocator.dupe(u8, input.provider);
    errdefer state.allocator.free(provider);
    const api_key = try state.allocator.dupe(u8, input.api_key);
    errdefer state.allocator.free(api_key);
    const model = if (input.model.len > 0) try state.allocator.dupe(u8, input.model) else @as([]const u8, "");
    errdefer if (model.len > 0) state.allocator.free(@constCast(model));
    const validated_with = if (input.validated_with.len > 0) try state.allocator.dupe(u8, input.validated_with) else @as([]const u8, "");
    errdefer if (validated_with.len > 0) state.allocator.free(@constCast(validated_with));

    try state.saved_providers.append(.{
        .id = id,
        .name = name,
        .provider = provider,
        .api_key = api_key,
        .model = model,
        .validated_at = "",
        .validated_with = validated_with,
        .last_validation_at = "",
        .last_validation_ok = false,
    });
}

pub fn updateSavedProvider(state: anytype, id: u32, update: anytype) !bool {
    for (state.saved_providers.items) |*sp| {
        if (sp.id != id) continue;

        const new_name = if (update.name) |name| try state.allocator.dupe(u8, name) else null;
        errdefer if (new_name) |n| state.allocator.free(n);
        const new_api_key = if (update.api_key) |api_key| try state.allocator.dupe(u8, api_key) else null;
        errdefer if (new_api_key) |k| state.allocator.free(k);
        const new_model = if (update.model) |model|
            if (model.len > 0) try state.allocator.dupe(u8, model) else @as([]const u8, "")
        else
            null;
        errdefer if (new_model) |m| if (m.len > 0) state.allocator.free(@constCast(m));
        const new_validated_at = if (update.validated_at) |validated_at|
            if (validated_at.len > 0) try state.allocator.dupe(u8, validated_at) else @as([]const u8, "")
        else
            null;
        errdefer if (new_validated_at) |t| if (t.len > 0) state.allocator.free(@constCast(t));
        const new_validated_with = if (update.validated_with) |validated_with|
            if (validated_with.len > 0) try state.allocator.dupe(u8, validated_with) else @as([]const u8, "")
        else
            null;
        errdefer if (new_validated_with) |w| if (w.len > 0) state.allocator.free(@constCast(w));
        const new_last_validation_at = if (update.last_validation_at) |last_validation_at|
            if (last_validation_at.len > 0) try state.allocator.dupe(u8, last_validation_at) else @as([]const u8, "")
        else
            null;
        errdefer if (new_last_validation_at) |t| if (t.len > 0) state.allocator.free(@constCast(t));

        if (update.name != null) {
            const n = new_name.?;
            state.allocator.free(sp.name);
            sp.name = n;
        }
        if (update.api_key != null) {
            const k = new_api_key.?;
            state.allocator.free(sp.api_key);
            sp.api_key = k;
        }
        if (update.model != null) {
            const m = new_model.?;
            if (sp.model.len > 0) state.allocator.free(sp.model);
            sp.model = m;
        }
        if (update.validated_at != null) {
            const t = new_validated_at.?;
            if (sp.validated_at.len > 0) state.allocator.free(sp.validated_at);
            sp.validated_at = t;
        }
        if (update.validated_with != null) {
            const w = new_validated_with.?;
            if (sp.validated_with.len > 0) state.allocator.free(sp.validated_with);
            sp.validated_with = w;
        }
        if (update.last_validation_at != null) {
            const t = new_last_validation_at.?;
            if (sp.last_validation_at.len > 0) state.allocator.free(sp.last_validation_at);
            sp.last_validation_at = t;
        }
        if (update.last_validation_ok) |ok| {
            sp.last_validation_ok = ok;
        }

        return true;
    }
    return false;
}

pub fn removeSavedProvider(state: anytype, id: u32) bool {
    for (state.saved_providers.items, 0..) |sp, i| {
        if (sp.id == id) {
            state.freeSavedProviderStrings(sp);
            _ = state.saved_providers.orderedRemove(i);
            return true;
        }
    }
    return false;
}

pub fn hasSavedProvider(state: anytype, provider: []const u8, api_key: []const u8, model: []const u8) bool {
    for (state.saved_providers.items) |sp| {
        if (std.mem.eql(u8, sp.provider, provider) and
            std.mem.eql(u8, sp.api_key, api_key) and
            std.mem.eql(u8, sp.model, model))
        {
            return true;
        }
    }
    return false;
}

pub fn findSavedProviderId(state: anytype, provider: []const u8, api_key: []const u8, model: []const u8) ?u32 {
    for (state.saved_providers.items) |sp| {
        if (std.mem.eql(u8, sp.provider, provider) and
            std.mem.eql(u8, sp.api_key, api_key) and
            std.mem.eql(u8, sp.model, model))
        {
            return sp.id;
        }
    }
    return null;
}

fn nextProviderId(items: anytype) u32 {
    var max_id: u32 = 0;
    for (items) |sp| {
        if (sp.id > max_id) max_id = sp.id;
    }
    return max_id + 1;
}

fn generateProviderName(allocator: std.mem.Allocator, items: anytype, provider: []const u8, label_fn: anytype) ![]const u8 {
    const label = label_fn(provider);
    var count: u32 = 0;
    for (items) |sp| {
        if (std.mem.eql(u8, sp.provider, provider)) count += 1;
    }
    return std.fmt.allocPrint(allocator, "{s} #{d}", .{ label, count + 1 });
}
