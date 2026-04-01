const std = @import("std");
const channels_repo = @import("state/channels_repo.zig");
const instances_repo = @import("state/instances_repo.zig");
const providers_repo = @import("state/providers_repo.zig");

// ─── Types ───────────────────────────────────────────────────────────────────

pub const InstanceEntry = struct {
    version: []const u8,
    auto_start: bool = false,
    launch_mode: []const u8 = "gateway",
    verbose: bool = false,
};

pub const SavedProvider = struct {
    id: u32,
    name: []const u8,
    provider: []const u8,
    api_key: []const u8,
    model: []const u8 = "",
    validated_at: []const u8 = "",
    validated_with: []const u8 = "",
    last_validation_at: []const u8 = "",
    last_validation_ok: bool = false,
};

pub const SavedProviderInput = struct {
    provider: []const u8,
    api_key: []const u8,
    model: []const u8 = "",
    validated_with: []const u8 = "",
};

pub const SavedProviderUpdate = struct {
    name: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    model: ?[]const u8 = null,
    validated_at: ?[]const u8 = null,
    validated_with: ?[]const u8 = null,
    last_validation_at: ?[]const u8 = null,
    last_validation_ok: ?bool = null,
};

pub const SavedChannel = struct {
    id: u32,
    name: []const u8,
    channel_type: []const u8,
    account: []const u8,
    config: []const u8 = "", // serialized JSON string
    validated_at: []const u8 = "",
    validated_with: []const u8 = "",
};

pub const SavedChannelInput = struct {
    channel_type: []const u8,
    account: []const u8,
    config: []const u8 = "",
    validated_with: []const u8 = "",
    validated_at: []const u8 = "",
};

pub const SavedChannelUpdate = struct {
    name: ?[]const u8 = null,
    account: ?[]const u8 = null,
    config: ?[]const u8 = null,
    validated_at: ?[]const u8 = null,
    validated_with: ?[]const u8 = null,
};

fn providerLabel(provider: []const u8) []const u8 {
    const map = .{
        .{ "openrouter", "OpenRouter" },
        .{ "anthropic", "Anthropic" },
        .{ "openai", "OpenAI" },
        .{ "google", "Google" },
        .{ "mistral", "Mistral" },
        .{ "groq", "Groq" },
        .{ "deepseek", "DeepSeek" },
        .{ "cohere", "Cohere" },
        .{ "ollama", "Ollama" },
        .{ "lm-studio", "LM Studio" },
        .{ "claude-cli", "Claude CLI" },
        .{ "codex-cli", "Codex CLI" },
        .{ "openai-codex", "OpenAI Codex" },
        .{ "together", "Together" },
        .{ "fireworks", "Fireworks" },
        .{ "perplexity", "Perplexity" },
        .{ "xai", "xAI" },
    };
    inline for (map) |pair| {
        if (std.mem.eql(u8, provider, pair[0])) return pair[1];
    }
    return provider;
}

fn channelLabel(channel_type: []const u8) []const u8 {
    const map = .{
        .{ "telegram", "Telegram" },
        .{ "discord", "Discord" },
        .{ "slack", "Slack" },
        .{ "whatsapp", "WhatsApp" },
        .{ "matrix", "Matrix" },
        .{ "mattermost", "Mattermost" },
        .{ "irc", "IRC" },
        .{ "imessage", "iMessage" },
        .{ "email", "Email" },
        .{ "lark", "Lark/Feishu" },
        .{ "dingtalk", "DingTalk" },
        .{ "signal", "Signal" },
        .{ "line", "LINE" },
        .{ "qq", "QQ" },
        .{ "onebot", "OneBot" },
        .{ "maixcam", "MaixCam" },
        .{ "nostr", "Nostr" },
        .{ "webhook", "Webhook" },
    };
    inline for (map) |pair| {
        if (std.mem.eql(u8, channel_type, pair[0])) return pair[1];
    }
    return channel_type;
}

/// JSON-compatible shape used for serialization / deserialization.
/// `std.json.ArrayHashMap` carries `jsonStringify` and `jsonParse` so we can
/// round-trip through `std.json` without custom hooks.
const JsonState = struct {
    instances: std.json.ArrayHashMap(std.json.ArrayHashMap(InstanceEntry)),
    saved_providers: []const SavedProvider = &.{},
    saved_channels: []const SavedChannel = &.{},
};

/// Inner map type: instance-name → InstanceEntry.
const InstanceMap = std.StringArrayHashMap(InstanceEntry);

/// Outer map type: component-name → InstanceMap.
const ComponentMap = std.StringArrayHashMap(InstanceMap);

// ─── State ───────────────────────────────────────────────────────────────────

pub const State = struct {
    allocator: std.mem.Allocator,
    /// instances[component][name] = InstanceEntry
    instances: ComponentMap,
    saved_providers: std.array_list.Managed(SavedProvider),
    saved_channels: std.array_list.Managed(SavedChannel),
    path: []const u8,

    /// Create an empty State that will persist to `path`.
    pub fn init(allocator: std.mem.Allocator, path: []const u8) State {
        return .{
            .allocator = allocator,
            .instances = ComponentMap.init(allocator),
            .saved_providers = std.array_list.Managed(SavedProvider).init(allocator),
            .saved_channels = std.array_list.Managed(SavedChannel).init(allocator),
            .path = allocator.dupe(u8, path) catch @panic("OOM"),
        };
    }

    pub fn freeSavedProviderStrings(self: *State, sp: SavedProvider) void {
        self.allocator.free(sp.name);
        self.allocator.free(sp.provider);
        self.allocator.free(sp.api_key);
        if (sp.model.len > 0) self.allocator.free(sp.model);
        if (sp.validated_at.len > 0) self.allocator.free(sp.validated_at);
        if (sp.validated_with.len > 0) self.allocator.free(sp.validated_with);
        if (sp.last_validation_at.len > 0) self.allocator.free(sp.last_validation_at);
    }

    pub fn freeSavedChannelStrings(self: *State, sc: SavedChannel) void {
        self.allocator.free(sc.name);
        self.allocator.free(sc.channel_type);
        self.allocator.free(sc.account);
        if (sc.config.len > 0) self.allocator.free(sc.config);
        if (sc.validated_at.len > 0) self.allocator.free(sc.validated_at);
        if (sc.validated_with.len > 0) self.allocator.free(sc.validated_with);
    }

    /// Free all owned strings and hashmaps.
    pub fn deinit(self: *State) void {
        channels_repo.deinitSavedChannels(self);
        providers_repo.deinitSavedProviders(self);
        instances_repo.deinitInstances(self.allocator, &self.instances);
        self.allocator.free(self.path);
    }

    /// Read state from disk. If the file doesn't exist, return an empty state.
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !State {
        const bytes = blk: {
            const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
                error.FileNotFound => return State.init(allocator, path),
                else => return err,
            };
            defer file.close();
            break :blk try file.readToEndAlloc(allocator, 4 * 1024 * 1024);
        };
        defer allocator.free(bytes);

        const parsed = try std.json.parseFromSlice(
            JsonState,
            allocator,
            bytes,
            .{ .allocate = .alloc_always },
        );
        defer parsed.deinit();

        // Copy into an owned State with duped strings.
        var state = State.init(allocator, path);
        errdefer state.deinit();

        var comp_it = parsed.value.instances.map.iterator();
        while (comp_it.next()) |comp_kv| {
            const comp_name = try allocator.dupe(u8, comp_kv.key_ptr.*);
            errdefer allocator.free(comp_name);

            var inner = InstanceMap.init(allocator);
            errdefer {
                var it = inner.iterator();
                while (it.next()) |e| {
                    allocator.free(e.value_ptr.version);
                    allocator.free(e.value_ptr.launch_mode);
                    allocator.free(e.key_ptr.*);
                }
                inner.deinit();
            }

            var inst_it = comp_kv.value_ptr.map.iterator();
            while (inst_it.next()) |inst_kv| {
                const inst_name = try allocator.dupe(u8, inst_kv.key_ptr.*);
                errdefer allocator.free(inst_name);
                const duped_launch_mode = try allocator.dupe(u8, inst_kv.value_ptr.launch_mode);
                errdefer allocator.free(duped_launch_mode);
                const entry = InstanceEntry{
                    .version = try allocator.dupe(u8, inst_kv.value_ptr.version),
                    .auto_start = inst_kv.value_ptr.auto_start,
                    .launch_mode = duped_launch_mode,
                    .verbose = inst_kv.value_ptr.verbose,
                };
                try inner.put(inst_name, entry);
            }

            try state.instances.put(comp_name, inner);
        }

        for (parsed.value.saved_providers) |sp| {
            const owned_name = try allocator.dupe(u8, sp.name);
            errdefer allocator.free(owned_name);
            const owned_provider = try allocator.dupe(u8, sp.provider);
            errdefer allocator.free(owned_provider);
            const owned_api_key = try allocator.dupe(u8, sp.api_key);
            errdefer allocator.free(owned_api_key);
            const owned_model = if (sp.model.len > 0) try allocator.dupe(u8, sp.model) else @as([]const u8, "");
            errdefer if (owned_model.len > 0) allocator.free(@constCast(owned_model));
            const owned_validated_at = if (sp.validated_at.len > 0) try allocator.dupe(u8, sp.validated_at) else @as([]const u8, "");
            errdefer if (owned_validated_at.len > 0) allocator.free(@constCast(owned_validated_at));
            const owned_validated_with = if (sp.validated_with.len > 0) try allocator.dupe(u8, sp.validated_with) else @as([]const u8, "");
            errdefer if (owned_validated_with.len > 0) allocator.free(@constCast(owned_validated_with));
            const owned_last_validation_at = if (sp.last_validation_at.len > 0) try allocator.dupe(u8, sp.last_validation_at) else @as([]const u8, "");
            errdefer if (owned_last_validation_at.len > 0) allocator.free(@constCast(owned_last_validation_at));

            try state.saved_providers.append(.{
                .id = sp.id,
                .name = owned_name,
                .provider = owned_provider,
                .api_key = owned_api_key,
                .model = owned_model,
                .validated_at = owned_validated_at,
                .validated_with = owned_validated_with,
                .last_validation_at = owned_last_validation_at,
                .last_validation_ok = sp.last_validation_ok,
            });
        }

        for (parsed.value.saved_channels) |sc| {
            const owned_name = try allocator.dupe(u8, sc.name);
            errdefer allocator.free(owned_name);
            const owned_channel_type = try allocator.dupe(u8, sc.channel_type);
            errdefer allocator.free(owned_channel_type);
            const owned_account = try allocator.dupe(u8, sc.account);
            errdefer allocator.free(owned_account);
            const owned_config = if (sc.config.len > 0) try allocator.dupe(u8, sc.config) else @as([]const u8, "");
            errdefer if (owned_config.len > 0) allocator.free(@constCast(owned_config));
            const owned_validated_at = if (sc.validated_at.len > 0) try allocator.dupe(u8, sc.validated_at) else @as([]const u8, "");
            errdefer if (owned_validated_at.len > 0) allocator.free(@constCast(owned_validated_at));
            const owned_validated_with = if (sc.validated_with.len > 0) try allocator.dupe(u8, sc.validated_with) else @as([]const u8, "");
            errdefer if (owned_validated_with.len > 0) allocator.free(@constCast(owned_validated_with));

            try state.saved_channels.append(.{
                .id = sc.id,
                .name = owned_name,
                .channel_type = owned_channel_type,
                .account = owned_account,
                .config = owned_config,
                .validated_at = owned_validated_at,
                .validated_with = owned_validated_with,
            });
        }

        return state;
    }

    /// Atomic save: serialize to JSON, write to `{path}.tmp`, rename over
    /// the real path. If NullHubX crashes mid-write the original is preserved.
    pub fn save(self: *State) !void {
        // Build the JSON-friendly structure. We reference the strings we
        // already own — they live long enough for serialization.
        var json_outer = std.json.ArrayHashMap(std.json.ArrayHashMap(InstanceEntry)){};
        defer {
            // Free inner maps first, then the outer map.
            for (json_outer.map.values()) |*inner| {
                inner.deinit(self.allocator);
            }
            json_outer.deinit(self.allocator);
        }

        var comp_it = self.instances.iterator();
        while (comp_it.next()) |comp_entry| {
            var json_inner = std.json.ArrayHashMap(InstanceEntry){};
            errdefer json_inner.deinit(self.allocator);

            var inst_it = comp_entry.value_ptr.iterator();
            while (inst_it.next()) |inst_entry| {
                try json_inner.map.put(self.allocator, inst_entry.key_ptr.*, inst_entry.value_ptr.*);
            }

            try json_outer.map.put(self.allocator, comp_entry.key_ptr.*, json_inner);
        }

        const json_state = JsonState{
            .instances = json_outer,
            .saved_providers = self.saved_providers.items,
            .saved_channels = self.saved_channels.items,
        };
        const json_bytes = try std.json.Stringify.valueAlloc(
            self.allocator,
            json_state,
            .{ .whitespace = .indent_2 },
        );
        defer self.allocator.free(json_bytes);

        // Write to temp file, then atomic rename.
        const tmp_path = try std.fmt.allocPrint(self.allocator, "{s}.tmp", .{self.path});
        defer self.allocator.free(tmp_path);

        {
            const file = try std.fs.createFileAbsolute(tmp_path, .{});
            defer file.close();
            try file.writeAll(json_bytes);
        }

        try std.fs.renameAbsolute(tmp_path, self.path);
    }

    /// Register a new instance under `component/name`. Dupes all strings.
    pub fn addInstance(
        self: *State,
        component: []const u8,
        name: []const u8,
        entry: InstanceEntry,
    ) !void {
        try instances_repo.addInstance(self, component, name, entry, InstanceMap.init);
    }

    /// Remove an instance. Returns `true` if the entry existed.
    pub fn removeInstance(self: *State, component: []const u8, name: []const u8) bool {
        return instances_repo.removeInstance(self, component, name);
    }

    /// Look up an instance.
    pub fn getInstance(self: *State, component: []const u8, name: []const u8) ?InstanceEntry {
        return instances_repo.getInstance(self, component, name);
    }

    /// Update an existing instance entry. Returns `true` if found, `false` otherwise.
    pub fn updateInstance(
        self: *State,
        component: []const u8,
        name: []const u8,
        entry: InstanceEntry,
    ) !bool {
        return instances_repo.updateInstance(self, component, name, entry);
    }

    /// Return all component names. Caller must free the returned slice
    /// (but NOT the strings themselves — they are owned by the State).
    pub fn componentNames(self: *State) ![][]const u8 {
        return instances_repo.componentNames(self);
    }

    /// Return all instance names under a component. Returns `null` if
    /// the component doesn't exist. Caller must free the returned slice.
    pub fn instanceNames(self: *State, component: []const u8) !?[][]const u8 {
        return instances_repo.instanceNames(self, component);
    }

    pub fn savedProviders(self: *State) []const SavedProvider {
        return self.saved_providers.items;
    }

    pub fn getSavedProvider(self: *State, id: u32) ?SavedProvider {
        return providers_repo.getSavedProvider(self, id);
    }

    pub fn addSavedProvider(self: *State, input: SavedProviderInput) !void {
        try providers_repo.addSavedProvider(self, input, providerLabel);
    }

    pub fn updateSavedProvider(self: *State, id: u32, update: SavedProviderUpdate) !bool {
        return providers_repo.updateSavedProvider(self, id, update);
    }

    pub fn removeSavedProvider(self: *State, id: u32) bool {
        return providers_repo.removeSavedProvider(self, id);
    }

    pub fn hasSavedProvider(self: *State, provider: []const u8, api_key: []const u8, model: []const u8) bool {
        return providers_repo.hasSavedProvider(self, provider, api_key, model);
    }

    pub fn findSavedProviderId(self: *State, provider: []const u8, api_key: []const u8, model: []const u8) ?u32 {
        return providers_repo.findSavedProviderId(self, provider, api_key, model);
    }

    // ─── SavedChannel CRUD ──────────────────────────────────────────────

    pub fn savedChannels(self: *State) []const SavedChannel {
        return self.saved_channels.items;
    }

    pub fn getSavedChannel(self: *State, id: u32) ?SavedChannel {
        return channels_repo.getSavedChannel(self, id);
    }

    pub fn addSavedChannel(self: *State, input: SavedChannelInput) !void {
        try channels_repo.addSavedChannel(self, input, channelLabel);
    }

    pub fn updateSavedChannel(self: *State, id: u32, update: SavedChannelUpdate) !bool {
        return channels_repo.updateSavedChannel(self, id, update);
    }

    pub fn removeSavedChannel(self: *State, id: u32) bool {
        return channels_repo.removeSavedChannel(self, id);
    }

    pub fn hasSavedChannel(self: *State, channel_type: []const u8, account: []const u8, config: []const u8) bool {
        return channels_repo.hasSavedChannel(self, channel_type, account, config);
    }
};

// ─── Tests ───────────────────────────────────────────────────────────────────

fn testPath(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const tmp = "/tmp/nullhubx-state-test";
    std.fs.deleteTreeAbsolute(tmp) catch {};
    try std.fs.makeDirAbsolute(tmp);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ tmp, name });
}

fn cleanupTestDir() void {
    std.fs.deleteTreeAbsolute("/tmp/nullhubx-state-test") catch {};
}

test "add instances, save, load, verify round-trip" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    // Create and populate
    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addInstance("nullclaw", "my-agent", .{ .version = "2026.3.1", .auto_start = true });
        try s.addInstance("nullclaw", "staging", .{ .version = "2026.3.1", .auto_start = false });
        try s.addInstance("nulltickets", "tracker", .{ .version = "0.1.0", .auto_start = true });

        try s.save();
    }

    // Load and verify
    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        const agent = s.getInstance("nullclaw", "my-agent");
        try std.testing.expect(agent != null);
        try std.testing.expectEqualStrings("2026.3.1", agent.?.version);
        try std.testing.expect(agent.?.auto_start == true);

        const staging = s.getInstance("nullclaw", "staging");
        try std.testing.expect(staging != null);
        try std.testing.expectEqualStrings("2026.3.1", staging.?.version);
        try std.testing.expect(staging.?.auto_start == false);

        const tracker = s.getInstance("nulltickets", "tracker");
        try std.testing.expect(tracker != null);
        try std.testing.expectEqualStrings("0.1.0", tracker.?.version);
        try std.testing.expect(tracker.?.auto_start == true);
    }
}

test "remove instance, save, load, verify gone" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0", .auto_start = true });
        try s.addInstance("nullclaw", "staging", .{ .version = "1.0.0", .auto_start = false });

        try std.testing.expect(s.removeInstance("nullclaw", "my-agent"));
        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        try std.testing.expect(s.getInstance("nullclaw", "my-agent") == null);

        const staging = s.getInstance("nullclaw", "staging");
        try std.testing.expect(staging != null);
        try std.testing.expectEqualStrings("1.0.0", staging.?.version);
    }
}

test "update instance version, save, load, verify" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0", .auto_start = false });
        const updated = try s.updateInstance("nullclaw", "my-agent", .{ .version = "2.0.0", .auto_start = true });
        try std.testing.expect(updated);
        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        const entry = s.getInstance("nullclaw", "my-agent");
        try std.testing.expect(entry != null);
        try std.testing.expectEqualStrings("2.0.0", entry.?.version);
        try std.testing.expect(entry.?.auto_start == true);
    }
}

test "load non-existent file returns empty state" {
    const allocator = std.testing.allocator;
    const path = "/tmp/nullhubx-state-test-nonexistent/state.json";

    var s = try State.load(allocator, path);
    defer s.deinit();

    try std.testing.expectEqual(@as(usize, 0), s.instances.count());
}

test "atomic save writes via temp file" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addInstance("comp", "inst", .{ .version = "1.0.0" });
    try s.save();

    // The temp file should NOT still exist after a successful save.
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
    defer allocator.free(tmp_path);

    const tmp_exists = blk: {
        const f = std.fs.openFileAbsolute(tmp_path, .{}) catch |err| switch (err) {
            error.FileNotFound => break :blk false,
            else => return err,
        };
        f.close();
        break :blk true;
    };
    try std.testing.expect(!tmp_exists);

    // The real file should exist and be valid JSON.
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);

    const parsed = try std.json.parseFromSlice(JsonState, allocator, bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();

    const entry = parsed.value.instances.map.get("comp").?.map.get("inst");
    try std.testing.expect(entry != null);
    try std.testing.expectEqualStrings("1.0.0", entry.?.version);
}

test "multiple components with multiple instances" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addInstance("alpha", "a1", .{ .version = "0.1.0", .auto_start = true });
        try s.addInstance("alpha", "a2", .{ .version = "0.2.0", .auto_start = false });
        try s.addInstance("beta", "b1", .{ .version = "1.0.0", .auto_start = true });
        try s.addInstance("beta", "b2", .{ .version = "1.1.0", .auto_start = false });
        try s.addInstance("gamma", "g1", .{ .version = "3.0.0", .auto_start = true });

        const comps = try s.componentNames();
        defer allocator.free(comps);
        try std.testing.expectEqual(@as(usize, 3), comps.len);

        const alpha_names = (try s.instanceNames("alpha")).?;
        defer allocator.free(alpha_names);
        try std.testing.expectEqual(@as(usize, 2), alpha_names.len);

        const beta_names = (try s.instanceNames("beta")).?;
        defer allocator.free(beta_names);
        try std.testing.expectEqual(@as(usize, 2), beta_names.len);

        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        // Verify everything round-tripped.
        try std.testing.expectEqualStrings("0.1.0", s.getInstance("alpha", "a1").?.version);
        try std.testing.expectEqualStrings("0.2.0", s.getInstance("alpha", "a2").?.version);
        try std.testing.expectEqualStrings("1.0.0", s.getInstance("beta", "b1").?.version);
        try std.testing.expectEqualStrings("1.1.0", s.getInstance("beta", "b2").?.version);
        try std.testing.expectEqualStrings("3.0.0", s.getInstance("gamma", "g1").?.version);

        // Non-existent lookups.
        try std.testing.expect(s.getInstance("alpha", "nope") == null);
        try std.testing.expect(s.getInstance("nope", "a1") == null);

        const missing = try s.instanceNames("nonexistent");
        try std.testing.expect(missing == null);

        // Update non-existent returns false.
        const nope = try s.updateInstance("nope", "nope", .{ .version = "0.0.0" });
        try std.testing.expect(!nope);

        // Remove non-existent returns false.
        try std.testing.expect(!s.removeInstance("nope", "nope"));
    }
}

test "launch_mode defaults to gateway, persists through save/load" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        // Default launch_mode
        try s.addInstance("nullclaw", "default-mode", .{ .version = "1.0.0" });
        const entry = s.getInstance("nullclaw", "default-mode").?;
        try std.testing.expectEqualStrings("gateway", entry.launch_mode);

        // Explicit launch_mode
        try s.addInstance("nullclaw", "agent-mode", .{ .version = "1.0.0", .launch_mode = "agent" });
        const agent_entry = s.getInstance("nullclaw", "agent-mode").?;
        try std.testing.expectEqualStrings("agent", agent_entry.launch_mode);

        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        const entry = s.getInstance("nullclaw", "default-mode").?;
        try std.testing.expectEqualStrings("gateway", entry.launch_mode);

        const agent_entry = s.getInstance("nullclaw", "agent-mode").?;
        try std.testing.expectEqualStrings("agent", agent_entry.launch_mode);
    }
}

test "update launch_mode persists" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addInstance("nullclaw", "my-agent", .{ .version = "1.0.0" });
        const updated = try s.updateInstance("nullclaw", "my-agent", .{ .version = "1.0.0", .launch_mode = "agent" });
        try std.testing.expect(updated);

        const entry = s.getInstance("nullclaw", "my-agent").?;
        try std.testing.expectEqualStrings("agent", entry.launch_mode);

        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        const entry = s.getInstance("nullclaw", "my-agent").?;
        try std.testing.expectEqualStrings("agent", entry.launch_mode);
    }
}

test "verbose defaults to false and persists through save/load" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addInstance("nullclaw", "default-verbose", .{ .version = "1.0.0" });
        try s.addInstance("nullclaw", "verbose-on", .{
            .version = "1.0.0",
            .verbose = true,
        });

        try std.testing.expect(!s.getInstance("nullclaw", "default-verbose").?.verbose);
        try std.testing.expect(s.getInstance("nullclaw", "verbose-on").?.verbose);

        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        try std.testing.expect(!s.getInstance("nullclaw", "default-verbose").?.verbose);
        try std.testing.expect(s.getInstance("nullclaw", "verbose-on").?.verbose);
    }
}

test "remove last instance removes component" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addInstance("comp", "only", .{ .version = "1.0.0" });
    try std.testing.expect(s.removeInstance("comp", "only"));

    // Component should be gone entirely.
    try std.testing.expectEqual(@as(usize, 0), s.instances.count());
    try std.testing.expect(s.getInstance("comp", "only") == null);
}

test "add saved provider, save, load, verify round-trip" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addSavedProvider(.{
            .provider = "openrouter",
            .api_key = "sk-or-xxx",
            .model = "anthropic/claude-sonnet-4",
            .validated_with = "nullclaw",
        });

        const providers = s.savedProviders();
        try std.testing.expectEqual(@as(usize, 1), providers.len);
        try std.testing.expectEqualStrings("openrouter", providers[0].provider);
        try std.testing.expectEqualStrings("sk-or-xxx", providers[0].api_key);
        try std.testing.expectEqualStrings("anthropic/claude-sonnet-4", providers[0].model);
        try std.testing.expectEqualStrings("OpenRouter #1", providers[0].name);
        try std.testing.expectEqual(@as(u32, 1), providers[0].id);

        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        const providers = s.savedProviders();
        try std.testing.expectEqual(@as(usize, 1), providers.len);
        try std.testing.expectEqualStrings("openrouter", providers[0].provider);
        try std.testing.expectEqualStrings("sk-or-xxx", providers[0].api_key);
        try std.testing.expectEqualStrings("OpenRouter #1", providers[0].name);
        try std.testing.expectEqual(@as(u32, 1), providers[0].id);
    }
}

test "auto-generated name increments per provider type" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedProvider(.{ .provider = "openrouter", .api_key = "key1" });
    try s.addSavedProvider(.{ .provider = "openrouter", .api_key = "key2" });
    try s.addSavedProvider(.{ .provider = "anthropic", .api_key = "key3" });

    const providers = s.savedProviders();
    try std.testing.expectEqual(@as(usize, 3), providers.len);
    try std.testing.expectEqualStrings("OpenRouter #1", providers[0].name);
    try std.testing.expectEqualStrings("OpenRouter #2", providers[1].name);
    try std.testing.expectEqualStrings("Anthropic #1", providers[2].name);
}

test "update saved provider name only" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedProvider(.{ .provider = "openrouter", .api_key = "key1" });
    const updated = try s.updateSavedProvider(1, .{ .name = "My Work Key" });
    try std.testing.expect(updated);

    const providers = s.savedProviders();
    try std.testing.expectEqualStrings("My Work Key", providers[0].name);
}

test "update saved provider api_key" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedProvider(.{ .provider = "openrouter", .api_key = "old-key" });
    const updated = try s.updateSavedProvider(1, .{ .api_key = "new-key" });
    try std.testing.expect(updated);

    const providers = s.savedProviders();
    try std.testing.expectEqualStrings("new-key", providers[0].api_key);
}

test "update saved provider clears model" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedProvider(.{
        .provider = "openrouter",
        .api_key = "key1",
        .model = "anthropic/claude-sonnet-4",
    });
    const updated = try s.updateSavedProvider(1, .{ .model = "" });
    try std.testing.expect(updated);

    const providers = s.savedProviders();
    try std.testing.expectEqualStrings("", providers[0].model);
}

test "saved provider validation metadata persists through update and load" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addSavedProvider(.{
            .provider = "openrouter",
            .api_key = "key1",
            .validated_with = "nullclaw",
        });
        const updated = try s.updateSavedProvider(1, .{
            .validated_at = "2026-03-11T18:59:00Z",
            .validated_with = "nullclaw",
            .last_validation_at = "2026-03-14T11:22:33Z",
            .last_validation_ok = false,
        });
        try std.testing.expect(updated);
        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        const provider = s.getSavedProvider(1).?;
        try std.testing.expectEqualStrings("2026-03-11T18:59:00Z", provider.validated_at);
        try std.testing.expectEqualStrings("2026-03-14T11:22:33Z", provider.last_validation_at);
        try std.testing.expect(!provider.last_validation_ok);
    }
}

test "remove saved provider" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedProvider(.{ .provider = "openrouter", .api_key = "key1" });
    try s.addSavedProvider(.{ .provider = "anthropic", .api_key = "key2" });

    try std.testing.expect(s.removeSavedProvider(1));
    try std.testing.expect(!s.removeSavedProvider(99));

    const providers = s.savedProviders();
    try std.testing.expectEqual(@as(usize, 1), providers.len);
    try std.testing.expectEqualStrings("anthropic", providers[0].provider);
}

test "find saved provider by id" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedProvider(.{ .provider = "openrouter", .api_key = "key1" });
    try s.addSavedProvider(.{ .provider = "anthropic", .api_key = "key2" });

    const found = s.getSavedProvider(2);
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("anthropic", found.?.provider);

    try std.testing.expect(s.getSavedProvider(99) == null);
}

test "saved providers coexist with instances in save/load" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addInstance("nullclaw", "bot1", .{ .version = "1.0.0" });
        try s.addSavedProvider(.{ .provider = "openrouter", .api_key = "key1" });
        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        try std.testing.expect(s.getInstance("nullclaw", "bot1") != null);
        try std.testing.expectEqual(@as(usize, 1), s.savedProviders().len);
    }
}

test "next provider id after removals" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedProvider(.{ .provider = "openrouter", .api_key = "key1" }); // id=1
    try s.addSavedProvider(.{ .provider = "anthropic", .api_key = "key2" }); // id=2
    _ = s.removeSavedProvider(1);
    try s.addSavedProvider(.{ .provider = "ollama", .api_key = "" }); // id=3 (not 1)

    const providers = s.savedProviders();
    try std.testing.expectEqual(@as(usize, 2), providers.len);
    try std.testing.expectEqual(@as(u32, 2), providers[0].id);
    try std.testing.expectEqual(@as(u32, 3), providers[1].id);
}

// ─── SavedChannel Tests ─────────────────────────────────────────────────────

test "add saved channel, save, load, verify round-trip" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addSavedChannel(.{
            .channel_type = "telegram",
            .account = "@mybot",
            .config = "{\"token\":\"abc\"}",
            .validated_with = "nullclaw",
        });

        const channels = s.savedChannels();
        try std.testing.expectEqual(@as(usize, 1), channels.len);
        try std.testing.expectEqualStrings("telegram", channels[0].channel_type);
        try std.testing.expectEqualStrings("@mybot", channels[0].account);
        try std.testing.expectEqualStrings("{\"token\":\"abc\"}", channels[0].config);
        try std.testing.expectEqualStrings("Telegram #1", channels[0].name);
        try std.testing.expectEqual(@as(u32, 1), channels[0].id);

        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        const channels = s.savedChannels();
        try std.testing.expectEqual(@as(usize, 1), channels.len);
        try std.testing.expectEqualStrings("telegram", channels[0].channel_type);
        try std.testing.expectEqualStrings("@mybot", channels[0].account);
        try std.testing.expectEqualStrings("Telegram #1", channels[0].name);
        try std.testing.expectEqual(@as(u32, 1), channels[0].id);
    }
}

test "channel auto-generated name increments per type" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedChannel(.{ .channel_type = "telegram", .account = "bot1" });
    try s.addSavedChannel(.{ .channel_type = "telegram", .account = "bot2" });
    try s.addSavedChannel(.{ .channel_type = "discord", .account = "srv1" });

    const channels = s.savedChannels();
    try std.testing.expectEqual(@as(usize, 3), channels.len);
    try std.testing.expectEqualStrings("Telegram #1", channels[0].name);
    try std.testing.expectEqualStrings("Telegram #2", channels[1].name);
    try std.testing.expectEqualStrings("Discord #1", channels[2].name);
}

test "update saved channel name only" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedChannel(.{ .channel_type = "telegram", .account = "bot1" });
    const updated = try s.updateSavedChannel(1, .{ .name = "My Bot" });
    try std.testing.expect(updated);

    const channels = s.savedChannels();
    try std.testing.expectEqualStrings("My Bot", channels[0].name);
}

test "remove saved channel" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedChannel(.{ .channel_type = "telegram", .account = "bot1" });
    try s.addSavedChannel(.{ .channel_type = "discord", .account = "srv1" });

    try std.testing.expect(s.removeSavedChannel(1));
    try std.testing.expect(!s.removeSavedChannel(99));

    const channels = s.savedChannels();
    try std.testing.expectEqual(@as(usize, 1), channels.len);
    try std.testing.expectEqualStrings("discord", channels[0].channel_type);
}

test "find saved channel by id" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedChannel(.{ .channel_type = "telegram", .account = "bot1" });
    try s.addSavedChannel(.{ .channel_type = "discord", .account = "srv1" });

    const found = s.getSavedChannel(2);
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("discord", found.?.channel_type);

    try std.testing.expect(s.getSavedChannel(99) == null);
}

test "hasSavedChannel detects duplicates" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedChannel(.{
        .channel_type = "telegram",
        .account = "bot1",
        .config = "{\"token\":\"abc\"}",
    });

    try std.testing.expect(s.hasSavedChannel("telegram", "bot1", "{\"token\":\"abc\"}"));
    try std.testing.expect(!s.hasSavedChannel("telegram", "bot1", ""));
    try std.testing.expect(!s.hasSavedChannel("telegram", "bot2", "{\"token\":\"abc\"}"));
    try std.testing.expect(!s.hasSavedChannel("discord", "bot1", "{\"token\":\"abc\"}"));
}

test "saved channels coexist with providers and instances" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    {
        var s = State.init(allocator, path);
        defer s.deinit();

        try s.addInstance("nullclaw", "bot1", .{ .version = "1.0.0" });
        try s.addSavedProvider(.{ .provider = "openrouter", .api_key = "key1" });
        try s.addSavedChannel(.{ .channel_type = "telegram", .account = "bot1" });
        try s.save();
    }

    {
        var s = try State.load(allocator, path);
        defer s.deinit();

        try std.testing.expect(s.getInstance("nullclaw", "bot1") != null);
        try std.testing.expectEqual(@as(usize, 1), s.savedProviders().len);
        try std.testing.expectEqual(@as(usize, 1), s.savedChannels().len);
    }
}

test "next channel id after removals" {
    const allocator = std.testing.allocator;
    const path = try testPath(allocator, "state.json");
    defer allocator.free(path);
    defer cleanupTestDir();

    var s = State.init(allocator, path);
    defer s.deinit();

    try s.addSavedChannel(.{ .channel_type = "telegram", .account = "bot1" }); // id=1
    try s.addSavedChannel(.{ .channel_type = "discord", .account = "srv1" }); // id=2
    _ = s.removeSavedChannel(1);
    try s.addSavedChannel(.{ .channel_type = "slack", .account = "ws1" }); // id=3 (not 1)

    const channels = s.savedChannels();
    try std.testing.expectEqual(@as(usize, 2), channels.len);
    try std.testing.expectEqual(@as(u32, 2), channels[0].id);
    try std.testing.expectEqual(@as(u32, 3), channels[1].id);
}
