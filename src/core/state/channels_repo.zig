const std = @import("std");

pub fn deinitSavedChannels(state: anytype) void {
    for (state.saved_channels.items) |sc| {
        state.freeSavedChannelStrings(sc);
    }
    state.saved_channels.deinit();
}

pub fn getSavedChannel(state: anytype, id: u32) ?@TypeOf(state.saved_channels.items[0]) {
    for (state.saved_channels.items) |sc| {
        if (sc.id == id) return sc;
    }
    return null;
}

pub fn addSavedChannel(state: anytype, input: anytype, label_fn: anytype) !void {
    const id = nextChannelId(state.saved_channels.items);
    const name = try generateChannelName(state.allocator, state.saved_channels.items, input.channel_type, label_fn);
    errdefer state.allocator.free(name);
    const channel_type = try state.allocator.dupe(u8, input.channel_type);
    errdefer state.allocator.free(channel_type);
    const account = try state.allocator.dupe(u8, input.account);
    errdefer state.allocator.free(account);
    const config = if (input.config.len > 0) try state.allocator.dupe(u8, input.config) else @as([]const u8, "");
    errdefer if (config.len > 0) state.allocator.free(@constCast(config));
    const validated_with = if (input.validated_with.len > 0) try state.allocator.dupe(u8, input.validated_with) else @as([]const u8, "");
    errdefer if (validated_with.len > 0) state.allocator.free(@constCast(validated_with));
    const validated_at = if (input.validated_at.len > 0) try state.allocator.dupe(u8, input.validated_at) else @as([]const u8, "");
    errdefer if (validated_at.len > 0) state.allocator.free(@constCast(validated_at));

    try state.saved_channels.append(.{
        .id = id,
        .name = name,
        .channel_type = channel_type,
        .account = account,
        .config = config,
        .validated_at = validated_at,
        .validated_with = validated_with,
    });
}

pub fn updateSavedChannel(state: anytype, id: u32, update: anytype) !bool {
    for (state.saved_channels.items) |*sc| {
        if (sc.id != id) continue;

        const new_name = if (update.name) |name| try state.allocator.dupe(u8, name) else null;
        errdefer if (new_name) |n| state.allocator.free(n);
        const new_account = if (update.account) |account| try state.allocator.dupe(u8, account) else null;
        errdefer if (new_account) |a| state.allocator.free(a);
        const new_config = if (update.config) |config|
            if (config.len > 0) try state.allocator.dupe(u8, config) else @as([]const u8, "")
        else
            null;
        errdefer if (new_config) |c| if (c.len > 0) state.allocator.free(@constCast(c));
        const new_validated_at = if (update.validated_at) |validated_at|
            if (validated_at.len > 0) try state.allocator.dupe(u8, validated_at) else @as([]const u8, "")
        else
            null;
        errdefer if (new_validated_at) |t| if (t.len > 0) state.allocator.free(@constCast(t));
        const new_validated_with = if (update.validated_with) |validated_with|
            if (validated_with.len > 0) try state.allocator.dupe(u8, validated_with) else @as([]const u8, "")
        else
            null;

        if (update.name != null) {
            const n = new_name.?;
            state.allocator.free(sc.name);
            sc.name = n;
        }
        if (update.account != null) {
            const a = new_account.?;
            state.allocator.free(sc.account);
            sc.account = a;
        }
        if (update.config != null) {
            const c = new_config.?;
            if (sc.config.len > 0) state.allocator.free(sc.config);
            sc.config = c;
        }
        if (update.validated_at != null) {
            const t = new_validated_at.?;
            if (sc.validated_at.len > 0) state.allocator.free(sc.validated_at);
            sc.validated_at = t;
        }
        if (update.validated_with != null) {
            const w = new_validated_with.?;
            if (sc.validated_with.len > 0) state.allocator.free(sc.validated_with);
            sc.validated_with = w;
        }

        return true;
    }
    return false;
}

pub fn removeSavedChannel(state: anytype, id: u32) bool {
    for (state.saved_channels.items, 0..) |sc, i| {
        if (sc.id == id) {
            state.freeSavedChannelStrings(sc);
            _ = state.saved_channels.orderedRemove(i);
            return true;
        }
    }
    return false;
}

pub fn hasSavedChannel(state: anytype, channel_type: []const u8, account: []const u8, config: []const u8) bool {
    for (state.saved_channels.items) |sc| {
        if (std.mem.eql(u8, sc.channel_type, channel_type) and
            std.mem.eql(u8, sc.account, account) and
            std.mem.eql(u8, sc.config, config))
        {
            return true;
        }
    }
    return false;
}

fn nextChannelId(items: anytype) u32 {
    var max_id: u32 = 0;
    for (items) |sc| {
        if (sc.id > max_id) max_id = sc.id;
    }
    return max_id + 1;
}

fn generateChannelName(allocator: std.mem.Allocator, items: anytype, channel_type: []const u8, label_fn: anytype) ![]const u8 {
    const label = label_fn(channel_type);
    var count: u32 = 0;
    for (items) |sc| {
        if (std.mem.eql(u8, sc.channel_type, channel_type)) count += 1;
    }
    return std.fmt.allocPrint(allocator, "{s} #{d}", .{ label, count + 1 });
}
