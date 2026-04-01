const std = @import("std");
const helpers = @import("../helpers.zig");
const legacy = @import("../instances.zig");
const state_mod = @import("../../core/state.zig");
const paths_mod = @import("../../core/paths.zig");

pub const ApiResponse = helpers.ApiResponse;

pub fn handleUsage(allocator: std.mem.Allocator, s: *state_mod.State, paths: paths_mod.Paths, component: []const u8, name: []const u8, target: []const u8) ApiResponse {
    _ = s.getInstance(component, name) orelse return helpers.notFound();

    const now_ts = std.time.timestamp();
    const window = legacy.parseUsageWindow(target);
    const min_ts = legacy.usageWindowMinTs(window, now_ts);

    const inst_dir = paths.instanceDir(allocator, component, name) catch return helpers.serverError();
    defer allocator.free(inst_dir);
    const ledger_path = legacy.resolveUsageLedgerPath(allocator, inst_dir) catch return helpers.serverError();
    defer allocator.free(ledger_path);
    const cache_path = legacy.usageCachePath(allocator, paths, component, name) catch return helpers.serverError();
    defer allocator.free(cache_path);

    var snapshot = legacy.emptyUsageCache(now_ts);
    defer snapshot.deinit(allocator);
    var has_cache = false;
    if (legacy.loadUsageCacheSnapshot(allocator, cache_path, now_ts) catch null) |loaded| {
        snapshot = loaded;
        has_cache = true;
    }

    var ledger_exists = false;
    var ledger_size: u64 = 0;
    var ledger_mtime_ns: i64 = 0;
    const ledger_file = std.fs.openFileAbsolute(ledger_path, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return helpers.serverError(),
    };
    if (ledger_file) |file| {
        defer file.close();
        const stat = file.stat() catch return helpers.serverError();
        ledger_exists = true;
        ledger_size = stat.size;
        ledger_mtime_ns = @intCast(stat.mtime);
    }

    var should_rebuild = false;
    if (ledger_exists) {
        if (!has_cache) {
            should_rebuild = true;
        } else if (snapshot.ledger_size != ledger_size or snapshot.ledger_mtime_ns != ledger_mtime_ns) {
            should_rebuild = true;
        }
    } else if (has_cache) {
        snapshot.deinit(allocator);
        snapshot = legacy.emptyUsageCache(now_ts);
        has_cache = false;
    }

    if (should_rebuild) {
        if (has_cache) snapshot.deinit(allocator);
        snapshot = legacy.rebuildUsageCacheSnapshot(allocator, ledger_path, ledger_size, ledger_mtime_ns, now_ts) catch return helpers.serverError();
        has_cache = true;
        legacy.writeUsageCacheSnapshot(allocator, cache_path, &snapshot) catch {};
    }

    var aggregates: std.StringHashMapUnmanaged(legacy.UsageAggregate) = .{};
    defer {
        var it_cleanup = aggregates.iterator();
        while (it_cleanup.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.provider);
            allocator.free(entry.value_ptr.model);
        }
        aggregates.deinit(allocator);
    }

    var total_prompt: u64 = 0;
    var total_completion: u64 = 0;
    var total_tokens: u64 = 0;
    var total_requests: u64 = 0;

    const source_buckets = if (legacy.isShortUsageWindow(window)) snapshot.hourly else snapshot.daily;
    for (source_buckets) |record| {
        if (min_ts) |cutoff| {
            if (record.last_used < cutoff) continue;
        }

        const provider = if (record.provider.len > 0) record.provider else "unknown";
        const model = if (record.model.len > 0) record.model else "unknown";
        const record_total: u64 = if (record.total_tokens > 0)
            record.total_tokens
        else
            record.prompt_tokens + record.completion_tokens;

        total_prompt += record.prompt_tokens;
        total_completion += record.completion_tokens;
        total_tokens += record_total;
        const req_count: u64 = if (record.requests > 0) record.requests else 1;
        total_requests += req_count;

        const key = std.fmt.allocPrint(allocator, "{s}\x1f{s}", .{ provider, model }) catch continue;
        if (aggregates.getPtr(key)) |agg| {
            allocator.free(key);
            agg.prompt_tokens += record.prompt_tokens;
            agg.completion_tokens += record.completion_tokens;
            agg.total_tokens += record_total;
            agg.requests += req_count;
            if (record.last_used > agg.last_used) agg.last_used = record.last_used;
        } else {
            const provider_copy = allocator.dupe(u8, provider) catch {
                allocator.free(key);
                continue;
            };
            errdefer allocator.free(provider_copy);
            const model_copy = allocator.dupe(u8, model) catch {
                allocator.free(key);
                allocator.free(provider_copy);
                continue;
            };
            errdefer allocator.free(model_copy);

            aggregates.put(allocator, key, .{
                .provider = provider_copy,
                .model = model_copy,
                .prompt_tokens = record.prompt_tokens,
                .completion_tokens = record.completion_tokens,
                .total_tokens = record_total,
                .requests = req_count,
                .last_used = record.last_used,
            }) catch {
                allocator.free(key);
                allocator.free(provider_copy);
                allocator.free(model_copy);
            };
        }
    }

    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    buf.appendSlice("{\"window\":\"") catch return helpers.serverError();
    helpers.appendEscaped(&buf, window) catch return helpers.serverError();
    buf.writer().print("\",\"generated_at\":{d},\"rows\":[", .{now_ts}) catch return helpers.serverError();

    var it = aggregates.iterator();
    var first_row = true;
    while (it.next()) |entry| {
        if (!first_row) buf.append(',') catch return helpers.serverError();
        first_row = false;

        const row = entry.value_ptr.*;
        buf.appendSlice("{\"provider\":\"") catch return helpers.serverError();
        helpers.appendEscaped(&buf, row.provider) catch return helpers.serverError();
        buf.appendSlice("\",\"model\":\"") catch return helpers.serverError();
        helpers.appendEscaped(&buf, row.model) catch return helpers.serverError();
        buf.appendSlice("\",\"prompt_tokens\":") catch return helpers.serverError();
        buf.writer().print("{d}", .{row.prompt_tokens}) catch return helpers.serverError();
        buf.appendSlice(",\"completion_tokens\":") catch return helpers.serverError();
        buf.writer().print("{d}", .{row.completion_tokens}) catch return helpers.serverError();
        buf.appendSlice(",\"total_tokens\":") catch return helpers.serverError();
        buf.writer().print("{d}", .{row.total_tokens}) catch return helpers.serverError();
        buf.appendSlice(",\"requests\":") catch return helpers.serverError();
        buf.writer().print("{d}", .{row.requests}) catch return helpers.serverError();
        buf.appendSlice(",\"last_used\":") catch return helpers.serverError();
        buf.writer().print("{d}", .{row.last_used}) catch return helpers.serverError();
        buf.appendSlice("}") catch return helpers.serverError();
    }

    buf.appendSlice("],\"totals\":{\"prompt_tokens\":") catch return helpers.serverError();
    buf.writer().print("{d}", .{total_prompt}) catch return helpers.serverError();
    buf.appendSlice(",\"completion_tokens\":") catch return helpers.serverError();
    buf.writer().print("{d}", .{total_completion}) catch return helpers.serverError();
    buf.appendSlice(",\"total_tokens\":") catch return helpers.serverError();
    buf.writer().print("{d}", .{total_tokens}) catch return helpers.serverError();
    buf.appendSlice(",\"requests\":") catch return helpers.serverError();
    buf.writer().print("{d}", .{total_requests}) catch return helpers.serverError();
    buf.appendSlice("}}") catch return helpers.serverError();

    const body = buf.toOwnedSlice() catch return helpers.serverError();
    return helpers.jsonOk(body);
}

test "handleUsage aggregates provider/model rows" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = @import("../instances.zig").TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "usage-agent", .{ .version = "1.0.0" });

    try mctx.paths.ensureDirs();
    const comp_dir = try std.fs.path.join(allocator, &.{ mctx.paths.root, "instances", "nullclaw" });
    defer allocator.free(comp_dir);
    std.fs.makeDirAbsolute(comp_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "usage-agent");
    defer allocator.free(inst_dir);
    std.fs.makeDirAbsolute(inst_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const ledger_path = try std.fs.path.join(allocator, &.{ inst_dir, "llm_usage.jsonl" });
    defer allocator.free(ledger_path);
    var ledger = try std.fs.createFileAbsolute(ledger_path, .{ .truncate = true });
    defer ledger.close();
    var writer_buf: [512]u8 = undefined;
    var fw = ledger.writer(&writer_buf);
    const w = &fw.interface;
    const usage_base_ts = std.time.timestamp() - 60;
    try w.print("{{\"ts\":{d},\"provider\":\"openrouter\",\"model\":\"anthropic/claude-sonnet-4\",\"prompt_tokens\":100,\"completion_tokens\":50,\"total_tokens\":150,\"success\":true}}\n", .{usage_base_ts});
    try w.print("{{\"ts\":{d},\"provider\":\"openrouter\",\"model\":\"anthropic/claude-sonnet-4\",\"prompt_tokens\":20,\"completion_tokens\":10,\"total_tokens\":30,\"success\":true}}\n", .{usage_base_ts + 1});
    try w.flush();

    const resp = handleUsage(allocator, &s, mctx.paths, "nullclaw", "usage-agent", "/api/instances/nullclaw/usage-agent/usage?window=all");
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"provider\":\"openrouter\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"total_tokens\":180") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"requests\":2") != null);
}

test "handleUsage refreshes cache immediately when ledger changes" {
    const allocator = std.testing.allocator;
    var s = state_mod.State.init(allocator, "/tmp/nullhubx-test-instances-api.json");
    defer s.deinit();
    var mctx = @import("../instances.zig").TestManagerCtx.init(allocator);
    defer mctx.deinit(allocator);

    try s.addInstance("nullclaw", "usage-agent-cache", .{ .version = "1.0.0" });

    try mctx.paths.ensureDirs();
    const comp_dir = try std.fs.path.join(allocator, &.{ mctx.paths.root, "instances", "nullclaw" });
    defer allocator.free(comp_dir);
    std.fs.makeDirAbsolute(comp_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const inst_dir = try mctx.paths.instanceDir(allocator, "nullclaw", "usage-agent-cache");
    defer allocator.free(inst_dir);
    std.fs.makeDirAbsolute(inst_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const ledger_path = try std.fs.path.join(allocator, &.{ inst_dir, legacy.TOKEN_USAGE_LEDGER_FILENAME });
    defer allocator.free(ledger_path);
    var ledger = try std.fs.createFileAbsolute(ledger_path, .{ .truncate = true });
    defer ledger.close();
    var writer_buf: [512]u8 = undefined;
    var fw = ledger.writer(&writer_buf);
    const w = &fw.interface;
    const usage_cache_base_ts = std.time.timestamp() - 60;
    try w.print("{{\"ts\":{d},\"provider\":\"openrouter\",\"model\":\"anthropic/claude-sonnet-4\",\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2,\"success\":true}}\n", .{usage_cache_base_ts});
    try w.flush();

    const first = handleUsage(allocator, &s, mctx.paths, "nullclaw", "usage-agent-cache", "/api/instances/nullclaw/usage-agent-cache/usage?window=all");
    defer allocator.free(first.body);
    try std.testing.expectEqualStrings("200 OK", first.status);
    try std.testing.expect(std.mem.indexOf(u8, first.body, "\"requests\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.body, "\"total_tokens\":2") != null);

    try ledger.seekFromEnd(0);
    try w.print("{{\"ts\":{d},\"provider\":\"openrouter\",\"model\":\"anthropic/claude-sonnet-4\",\"prompt_tokens\":2,\"completion_tokens\":1,\"total_tokens\":3,\"success\":true}}\n", .{usage_cache_base_ts + 1});
    try w.flush();

    const second = handleUsage(allocator, &s, mctx.paths, "nullclaw", "usage-agent-cache", "/api/instances/nullclaw/usage-agent-cache/usage?window=all");
    defer allocator.free(second.body);
    try std.testing.expectEqualStrings("200 OK", second.status);
    try std.testing.expect(std.mem.indexOf(u8, second.body, "\"requests\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, second.body, "\"total_tokens\":5") != null);
}
