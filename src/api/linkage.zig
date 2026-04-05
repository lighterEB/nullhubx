const std = @import("std");
const paths_mod = @import("../core/paths.zig");
const state_mod = @import("../core/state.zig");

pub const LinkedInstance = struct {
    component: []const u8,
    name: []const u8,
};

pub const LinkSummary = struct {
    linked_instances: std.ArrayListUnmanaged(LinkedInstance) = .empty,
    orphaned: bool = true,

    fn deinit(self: *LinkSummary, allocator: std.mem.Allocator) void {
        for (self.linked_instances.items) |item| {
            allocator.free(item.component);
            allocator.free(item.name);
        }
        self.linked_instances.deinit(allocator);
    }
};

pub const LinkBundle = struct {
    provider_links: []LinkSummary,
    channel_links: []LinkSummary,

    pub fn deinit(self: *LinkBundle, allocator: std.mem.Allocator) void {
        for (self.provider_links) |*summary| summary.deinit(allocator);
        allocator.free(self.provider_links);
        for (self.channel_links) |*summary| summary.deinit(allocator);
        allocator.free(self.channel_links);
        self.* = undefined;
    }
};

pub fn buildLinkBundle(
    allocator: std.mem.Allocator,
    state: *state_mod.State,
    paths: paths_mod.Paths,
) !LinkBundle {
    const providers = state.savedProviders();
    const channels = state.savedChannels();

    const provider_links = try allocator.alloc(LinkSummary, providers.len);
    errdefer allocator.free(provider_links);
    @memset(provider_links, .{});

    const channel_links = try allocator.alloc(LinkSummary, channels.len);
    errdefer allocator.free(channel_links);
    @memset(channel_links, .{});

    var bundle = LinkBundle{
        .provider_links = provider_links,
        .channel_links = channel_links,
    };
    errdefer bundle.deinit(allocator);

    var component_it = state.instances.iterator();
    while (component_it.next()) |component_entry| {
        const component = component_entry.key_ptr.*;
        var instance_it = component_entry.value_ptr.iterator();
        while (instance_it.next()) |instance_entry| {
            const name = instance_entry.key_ptr.*;
            const config_path = paths.instanceConfig(allocator, component, name) catch continue;
            defer allocator.free(config_path);

            const file = std.fs.openFileAbsolute(config_path, .{}) catch continue;
            defer file.close();

            const contents = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch continue;
            defer allocator.free(contents);

            var parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            }) catch continue;
            defer parsed.deinit();

            if (parsed.value != .object) continue;
            const root_obj = parsed.value.object;

            for (providers, 0..) |provider, idx| {
                if (providerLinked(root_obj, providers, provider)) {
                    try appendLinkedInstance(allocator, &bundle.provider_links[idx], component, name);
                }
            }

            for (channels, 0..) |channel, idx| {
                if (channelLinked(root_obj, channels, channel)) {
                    try appendLinkedInstance(allocator, &bundle.channel_links[idx], component, name);
                }
            }
        }
    }

    return bundle;
}

fn appendLinkedInstance(
    allocator: std.mem.Allocator,
    summary: *LinkSummary,
    component: []const u8,
    name: []const u8,
) !void {
    for (summary.linked_instances.items) |item| {
        if (std.mem.eql(u8, item.component, component) and std.mem.eql(u8, item.name, name)) {
            summary.orphaned = false;
            return;
        }
    }

    try summary.linked_instances.append(allocator, .{
        .component = try allocator.dupe(u8, component),
        .name = try allocator.dupe(u8, name),
    });
    summary.orphaned = false;
}

fn providerLinked(
    root_obj: std.json.ObjectMap,
    providers: []const state_mod.SavedProvider,
    provider: state_mod.SavedProvider,
) bool {
    if (providerRefLinked(root_obj, provider.id)) return true;
    if (providerKeyCount(providers, provider.provider) != 1) return false;
    return providerNameLinked(root_obj, provider.provider) or
        providerPrimaryModelLinked(root_obj, provider.provider) or
        providerAgentListLinked(root_obj, provider.provider);
}

fn providerRefLinked(root_obj: std.json.ObjectMap, provider_id: u32) bool {
    const providers_obj = modelsProvidersObject(root_obj) orelse return false;
    var it = providers_obj.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .object) continue;
        if (entry.value_ptr.object.get("_ref")) |ref_val| {
            if (ref_val == .integer and ref_val.integer == provider_id) return true;
        }
    }
    return false;
}

fn providerNameLinked(root_obj: std.json.ObjectMap, provider_name: []const u8) bool {
    const providers_obj = modelsProvidersObject(root_obj) orelse return false;
    return providers_obj.contains(provider_name);
}

fn providerPrimaryModelLinked(root_obj: std.json.ObjectMap, provider_name: []const u8) bool {
    const agents_obj = root_obj.get("agents") orelse return false;
    if (agents_obj != .object) return false;
    const defaults_val = agents_obj.object.get("defaults") orelse return false;
    if (defaults_val != .object) return false;
    const primary_val = defaults_val.object.get("model_primary") orelse return false;
    if (primary_val != .string) return false;

    const primary = primary_val.string;
    const slash = std.mem.indexOfScalar(u8, primary, '/') orelse return false;
    return std.mem.eql(u8, primary[0..slash], provider_name);
}

fn providerAgentListLinked(root_obj: std.json.ObjectMap, provider_name: []const u8) bool {
    const agents_obj = root_obj.get("agents") orelse return false;
    if (agents_obj != .object) return false;
    const list_val = agents_obj.object.get("list") orelse return false;
    if (list_val != .array) return false;

    for (list_val.array.items) |item| {
        if (item != .object) continue;
        if (item.object.get("provider")) |provider_val| {
            if (provider_val == .string and std.mem.eql(u8, provider_val.string, provider_name)) return true;
        }
    }
    return false;
}

fn modelsProvidersObject(root_obj: std.json.ObjectMap) ?std.json.ObjectMap {
    const models_val = root_obj.get("models") orelse return null;
    if (models_val != .object) return null;
    const providers_val = models_val.object.get("providers") orelse return null;
    if (providers_val != .object) return null;
    return providers_val.object;
}

fn providerKeyCount(providers: []const state_mod.SavedProvider, provider_name: []const u8) usize {
    var count: usize = 0;
    for (providers) |item| {
        if (std.mem.eql(u8, item.provider, provider_name)) count += 1;
    }
    return count;
}

fn channelLinked(
    root_obj: std.json.ObjectMap,
    channels: []const state_mod.SavedChannel,
    channel: state_mod.SavedChannel,
) bool {
    if (channelPairCount(channels, channel.channel_type, channel.account) != 1) return false;

    const channels_val = root_obj.get("channels") orelse return false;
    if (channels_val != .object) return false;
    const type_val = channels_val.object.get(channel.channel_type) orelse return false;
    if (type_val != .object) return false;

    if (channelAccountDirectLinked(type_val.object, channel.account)) return true;
    if (channelAccountNestedLinked(type_val.object, channel.account)) return true;
    return false;
}

fn channelAccountDirectLinked(channel_obj: std.json.ObjectMap, account: []const u8) bool {
    if (channel_obj.get(account)) |account_val| {
        if (account_val == .object) return true;
    }
    if (channel_obj.get("account_id")) |account_id_val| {
        if (account_id_val == .string and std.mem.eql(u8, account_id_val.string, account)) return true;
    }
    return false;
}

fn channelAccountNestedLinked(channel_obj: std.json.ObjectMap, account: []const u8) bool {
    const accounts_val = channel_obj.get("accounts") orelse return false;
    if (accounts_val != .object) return false;
    if (accounts_val.object.get(account)) |account_val| {
        return account_val == .object;
    }
    return false;
}

fn channelPairCount(channels: []const state_mod.SavedChannel, channel_type: []const u8, account: []const u8) usize {
    var count: usize = 0;
    for (channels) |item| {
        if (std.mem.eql(u8, item.channel_type, channel_type) and std.mem.eql(u8, item.account, account)) {
            count += 1;
        }
    }
    return count;
}

test "buildLinkBundle links provider via provider name and model primary when unique" {
    const allocator = std.testing.allocator;
    const root = "/tmp/nullhubx-linkage-provider";
    std.fs.deleteTreeAbsolute(root) catch {};
    defer std.fs.deleteTreeAbsolute(root) catch {};

    var paths = try paths_mod.Paths.init(allocator, root);
    defer paths.deinit(allocator);
    try paths.ensureDirs();

    const state_path = try paths.state(allocator);
    defer allocator.free(state_path);
    var state = state_mod.State.init(allocator, state_path);
    defer state.deinit();

    try state.addSavedProvider(.{
        .provider = "openrouter",
        .api_key = "sk-test",
        .model = "gpt-5-mini",
    });
    try state.addInstance("nullclaw", "alpha", .{ .version = "v1" });

    const inst_dir = try paths.instanceDir(allocator, "nullclaw", "alpha");
    defer allocator.free(inst_dir);
    try std.fs.cwd().makePath(inst_dir);

    const config_path = try paths.instanceConfig(allocator, "nullclaw", "alpha");
    defer allocator.free(config_path);
    var file = try std.fs.createFileAbsolute(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(
        \\{
        \\  "models": {
        \\    "providers": {
        \\      "openrouter": {}
        \\    }
        \\  },
        \\  "agents": {
        \\    "defaults": {
        \\      "model_primary": "openrouter/openai/gpt-5-mini"
        \\    }
        \\  }
        \\}
    );

    var bundle = try buildLinkBundle(allocator, &state, paths);
    defer bundle.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), bundle.provider_links[0].linked_instances.items.len);
    try std.testing.expect(!bundle.provider_links[0].orphaned);
    try std.testing.expectEqualStrings("nullclaw", bundle.provider_links[0].linked_instances.items[0].component);
    try std.testing.expectEqualStrings("alpha", bundle.provider_links[0].linked_instances.items[0].name);
}

test "buildLinkBundle links channel via channel type and account" {
    const allocator = std.testing.allocator;
    const root = "/tmp/nullhubx-linkage-channel";
    std.fs.deleteTreeAbsolute(root) catch {};
    defer std.fs.deleteTreeAbsolute(root) catch {};

    var paths = try paths_mod.Paths.init(allocator, root);
    defer paths.deinit(allocator);
    try paths.ensureDirs();

    const state_path = try paths.state(allocator);
    defer allocator.free(state_path);
    var state = state_mod.State.init(allocator, state_path);
    defer state.deinit();

    try state.addSavedChannel(.{
        .channel_type = "telegram",
        .account = "bot-a",
        .config = "{\"bot_token\":\"secret\"}",
    });
    try state.addInstance("nullclaw", "alpha", .{ .version = "v1" });

    const inst_dir = try paths.instanceDir(allocator, "nullclaw", "alpha");
    defer allocator.free(inst_dir);
    try std.fs.cwd().makePath(inst_dir);

    const config_path = try paths.instanceConfig(allocator, "nullclaw", "alpha");
    defer allocator.free(config_path);
    var file = try std.fs.createFileAbsolute(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(
        \\{
        \\  "channels": {
        \\    "telegram": {
        \\      "bot-a": {
        \\        "bot_token": "secret"
        \\      }
        \\    }
        \\  }
        \\}
    );

    var bundle = try buildLinkBundle(allocator, &state, paths);
    defer bundle.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), bundle.channel_links[0].linked_instances.items.len);
    try std.testing.expect(!bundle.channel_links[0].orphaned);
}
