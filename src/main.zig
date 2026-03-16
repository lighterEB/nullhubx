const std = @import("std");
const builtin = @import("builtin");
pub const root = @import("root.zig");
const cli = root.cli;
const api_cli = root.api_cli;
const server = root.server;
const service = root.service;
const paths_mod = root.paths;
const manager_mod = root.manager;
const access = root.access;
const mdns_mod = root.mdns;
const routes_cli = @import("routes_cli.zig");
const status_cli = root.status_cli;
const version = root.version;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // skip program name

    const command = cli.parse(&args);

    switch (command) {
        .version => try printVersionLine(),
        .serve => |opts| {
            std.debug.print("nullhubx v{s}\n", .{version.string});

            var paths = try paths_mod.Paths.init(allocator, null);
            defer paths.deinit(allocator);
            try paths.ensureDirs();

            var mgr = manager_mod.Manager.init(allocator, paths);
            defer mgr.deinit();
            var mutex = std.Thread.Mutex{};

            var srv = try server.Server.init(allocator, opts.host, opts.port, &mgr, &mutex);
            defer srv.deinit();
            var mdns = try mdns_mod.Publisher.init(allocator, paths, opts.host, opts.port);
            defer mdns.deinit();
            mdns.start(opts.port);
            srv.setAccessOptions(mdns.accessOptions());
            srv.setAccessPublisher(&mdns);

            const sup_thread = try std.Thread.spawn(.{}, supervisorLoop, .{ &mgr, &mutex });
            sup_thread.detach();

            srv.autoStartAll();

            if (!opts.no_open) {
                const browser_thread = try std.Thread.spawn(.{}, delayedOpenBrowser, .{
                    allocator,
                    opts.host,
                    opts.port,
                    &mdns,
                });
                browser_thread.detach();
            }

            srv.run() catch |err| {
                if (err == error.PortAlreadyInUse) {
                    std.debug.print("error: port {d} is already in use\n", .{opts.port});
                    std.process.exit(1);
                }
                return err;
            };
        },
        .status => |opts| try status_cli.run(allocator, opts),
        .routes => |opts| try routes_cli.run(allocator, opts),
        .api => |opts| api_cli.run(allocator, opts) catch |err| {
            const any_err: anyerror = err;
            switch (any_err) {
                error.InvalidMethod => std.debug.print("Invalid HTTP method: {s}\n", .{opts.method}),
                error.InvalidTarget => std.debug.print("Invalid API target: {s}\n", .{opts.target}),
                error.FileNotFound => std.debug.print("Body file not found.\n", .{}),
                error.ConnectionRefused => std.debug.print("nullhubx is not running on http://{s}:{d}\n", .{ opts.host, opts.port }),
                error.RequestFailed => {},
                else => std.debug.print("API request failed: {s}\n", .{@errorName(any_err)}),
            }
            std.process.exit(1);
        },
        .install => |opts| {
            try handleInstallViaApi(allocator, opts);
        },
        .start => |ref| try handleInstanceActionViaApi(allocator, ref, "start"),
        .stop => |ref| try handleInstanceActionViaApi(allocator, ref, "stop"),
        .restart => |ref| try handleInstanceActionViaApi(allocator, ref, "restart"),
        .start_all => std.debug.print("start-all (not yet implemented)\n", .{}),
        .stop_all => std.debug.print("stop-all (not yet implemented)\n", .{}),
        .logs => |opts| {
            std.debug.print("logs {s}/{s}", .{ opts.instance.component, opts.instance.name });
            if (opts.follow) std.debug.print(" -f", .{});
            std.debug.print(" --lines {d} (not yet implemented)\n", .{opts.lines});
        },
        .check_updates => try callLocalApiAndPrint(allocator, "GET", "/api/updates", null),
        .update => |ref| try handleInstanceActionViaApi(allocator, ref, "update"),
        .update_all => std.debug.print("update-all (not yet implemented)\n", .{}),
        .config => |opts| try handleConfigViaApi(allocator, opts),
        .wizard => |opts| std.debug.print("wizard {s} (not yet implemented)\n", .{opts.component}),
        .service => |sc| handleServiceCommand(allocator, sc) catch |err| {
            const any_err: anyerror = err;
            switch (any_err) {
                error.UnsupportedPlatform => std.debug.print("Service management is not supported on this platform.\n", .{}),
                error.NoHomeDir => std.debug.print("Could not resolve home directory for service files.\n", .{}),
                error.SystemctlUnavailable => {
                    std.debug.print("`systemctl` is not available; Linux service commands require systemd user services.\n", .{});
                },
                error.SystemdUserUnavailable => {
                    std.debug.print("systemd user services are unavailable (`systemctl --user`).\n", .{});
                },
                error.CommandFailed => {
                    std.debug.print("Service command failed: {s}\n", .{@tagName(sc)});
                },
                else => return any_err,
            }
            std.process.exit(1);
        },
        .uninstall => |opts| {
            try handleUninstall(allocator, opts);
        },
        .add_source => |opts| std.debug.print("add-source {s} (not yet implemented)\n", .{opts.repo}),
        .help => cli.printUsage(),
    }
}

fn handleServiceCommand(allocator: std.mem.Allocator, command: cli.ServiceCommand) !void {
    switch (command) {
        .install => {
            try service.install(allocator);
            try printStdout("Service installed and started.\n");
        },
        .uninstall => {
            try service.uninstall(allocator);
            try printStdout("Service uninstalled.\n");
        },
        .status => try service.printStatus(allocator),
    }
}

fn handleUninstall(allocator: std.mem.Allocator, opts: cli.UninstallOptions) !void {
    const state_mod = @import("core/state.zig");
    const instances_api = @import("api/instances.zig");

    var paths = try paths_mod.Paths.init(allocator, null);
    defer paths.deinit(allocator);

    const state_path = try paths.state(allocator);
    defer allocator.free(state_path);

    var state = try state_mod.State.load(allocator, state_path);
    defer state.deinit();

    var manager = manager_mod.Manager.init(allocator, paths);
    defer manager.deinit();

    const component = opts.instance.component;
    const name = opts.instance.name;

    // Check if instance exists
    if (state.getInstance(component, name) == null) {
        std.debug.print("Instance {s}/{s} not found.\n", .{ component, name });
        std.process.exit(1);
    }

    std.debug.print("Uninstalling {s}/{s}...\n", .{ component, name });

    const resp = instances_api.handleDelete(allocator, &state, &manager, paths, component, name);
    // Note: resp.body is a static string, don't free it

    if (std.mem.eql(u8, resp.status, "200 OK")) {
        std.debug.print("Instance {s}/{s} uninstalled successfully.\n", .{ component, name });
    } else if (std.mem.eql(u8, resp.status, "404 Not Found")) {
        std.debug.print("Instance {s}/{s} not found.\n", .{ component, name });
        std.process.exit(1);
    } else {
        std.debug.print("Failed to uninstall: {s}\n", .{resp.status});
        if (resp.body.len > 0) {
            std.debug.print("{s}\n", .{resp.body});
        }
        std.process.exit(1);
    }
}

fn printVersionLine() !void {
    var line_buf: [128]u8 = undefined;
    const line = try std.fmt.bufPrint(&line_buf, "nullhubx v{s}\n", .{version.string});
    try printStdout(line);
}

fn printStdout(text: []const u8) !void {
    var stdout_buf: [1024]u8 = undefined;
    var bw = std.fs.File.stdout().writer(&stdout_buf);
    const w = &bw.interface;
    try w.writeAll(text);
    try w.flush();
}

fn handleInstallViaApi(allocator: std.mem.Allocator, opts: cli.InstallOptions) !void {
    const body = try buildInstallWizardBodyAlloc(allocator, opts);
    defer allocator.free(body);

    const target = try std.fmt.allocPrint(allocator, "/api/wizard/{s}", .{opts.component});
    defer allocator.free(target);

    try callLocalApiAndPrint(allocator, "POST", target, body);
}

fn handleInstanceActionViaApi(
    allocator: std.mem.Allocator,
    ref: cli.InstanceRef,
    action: []const u8,
) !void {
    const target = try buildInstanceActionTargetAlloc(allocator, ref, action);
    defer allocator.free(target);

    try callLocalApiAndPrint(allocator, "POST", target, null);
}

fn handleConfigViaApi(allocator: std.mem.Allocator, opts: cli.ConfigOptions) !void {
    if (opts.edit) {
        try printStdout("config --edit is not implemented yet; showing current config instead.\n");
    }
    const target = try buildInstanceActionTargetAlloc(allocator, opts.instance, "config");
    defer allocator.free(target);
    try callLocalApiAndPrint(allocator, "GET", target, null);
}

fn buildInstallWizardBodyAlloc(allocator: std.mem.Allocator, opts: cli.InstallOptions) ![]u8 {
    const instance_name = opts.name orelse "default";
    const install_version = opts.version orelse "latest";
    return std.json.Stringify.valueAlloc(allocator, .{
        .instance_name = instance_name,
        .version = install_version,
        .provider = opts.provider,
        .api_key = opts.api_key,
        .model = opts.model,
        .memory = opts.memory,
        .build_from_source = opts.build_from_source,
    }, .{ .emit_null_optional_fields = false });
}

fn buildInstanceActionTargetAlloc(
    allocator: std.mem.Allocator,
    ref: cli.InstanceRef,
    action: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "/api/instances/{s}/{s}/{s}",
        .{ ref.component, ref.name, action },
    );
}

fn callLocalApiAndPrint(
    allocator: std.mem.Allocator,
    method: []const u8,
    target: []const u8,
    body: ?[]const u8,
) !void {
    var result = api_cli.execute(allocator, .{
        .method = method,
        .target = target,
        .host = access.default_bind_host,
        .port = access.default_port,
        .body = body,
        .content_type = "application/json",
    }) catch |err| {
        const any_err: anyerror = err;
        switch (any_err) {
            error.ConnectionRefused => {
                std.debug.print(
                    "nullhubx is not running on http://{s}:{d}; run `nullhubx serve` first.\n",
                    .{ access.default_bind_host, access.default_port },
                );
                std.process.exit(1);
            },
            else => return any_err,
        }
    };
    defer result.deinit(allocator);

    if (result.body.len > 0) {
        try printStdout(result.body);
        if (result.body[result.body.len - 1] != '\n') try printStdout("\n");
    }

    const code = @intFromEnum(result.status);
    if (code < 200 or code >= 300) {
        std.debug.print("HTTP {d}\n", .{code});
        std.process.exit(1);
    }
}

fn supervisorLoop(manager: *manager_mod.Manager, mutex: *std.Thread.Mutex) void {
    while (true) {
        {
            mutex.lock();
            defer mutex.unlock();
            manager.tick();
        }
        std.Thread.sleep(1_000_000_000); // 1 second
    }
}

fn openBrowser(allocator: std.mem.Allocator, host: []const u8, port: u16, access_options: access.Options) void {
    var urls = access.buildAccessUrlsWithOptions(allocator, host, port, access_options) catch return;
    defer urls.deinit(allocator);

    var child = switch (builtin.os.tag) {
        .macos => std.process.Child.init(&.{ "open", urls.browser_open_url }, allocator),
        .windows => std.process.Child.init(&.{ "cmd", "/c", "start", "", urls.browser_open_url }, allocator),
        else => std.process.Child.init(&.{ "xdg-open", urls.browser_open_url }, allocator),
    };
    _ = child.spawnAndWait() catch return;
}

fn delayedOpenBrowser(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    publisher: *const mdns_mod.Publisher,
) void {
    std.Thread.sleep(750 * std.time.ns_per_ms);
    openBrowser(allocator, host, port, publisher.accessOptions());
}

test "buildInstallWizardBodyAlloc includes optional install fields" {
    const body = try buildInstallWizardBodyAlloc(std.testing.allocator, .{
        .component = "nullclaw",
        .name = "mini-agent",
        .version = "latest",
        .provider = "openrouter",
        .api_key = "sk-test",
        .model = "anthropic/claude-sonnet-4",
        .memory = "sqlite",
        .build_from_source = true,
    });
    defer std.testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .object);
    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("mini-agent", obj.get("instance_name").?.string);
    try std.testing.expectEqualStrings("latest", obj.get("version").?.string);
    try std.testing.expectEqualStrings("openrouter", obj.get("provider").?.string);
    try std.testing.expectEqualStrings("sk-test", obj.get("api_key").?.string);
    try std.testing.expectEqualStrings("anthropic/claude-sonnet-4", obj.get("model").?.string);
    try std.testing.expectEqualStrings("sqlite", obj.get("memory").?.string);
    try std.testing.expect(obj.get("build_from_source").?.bool);
}

test "buildInstallWizardBodyAlloc omits null optional install fields" {
    const body = try buildInstallWizardBodyAlloc(std.testing.allocator, .{
        .component = "nullclaw",
    });
    defer std.testing.allocator.free(body);

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    try std.testing.expect(parsed.value == .object);
    const obj = parsed.value.object;
    try std.testing.expectEqualStrings("default", obj.get("instance_name").?.string);
    try std.testing.expectEqualStrings("latest", obj.get("version").?.string);
    try std.testing.expect(obj.get("provider") == null);
    try std.testing.expect(obj.get("api_key") == null);
    try std.testing.expect(obj.get("model") == null);
    try std.testing.expect(obj.get("memory") == null);
}

test "buildInstanceActionTargetAlloc formats instance action route" {
    const route = try buildInstanceActionTargetAlloc(std.testing.allocator, .{
        .component = "nullclaw",
        .name = "mini-agent",
    }, "start");
    defer std.testing.allocator.free(route);
    try std.testing.expectEqualStrings("/api/instances/nullclaw/mini-agent/start", route);
}

test "buildInstanceActionTargetAlloc supports config action route" {
    const route = try buildInstanceActionTargetAlloc(std.testing.allocator, .{
        .component = "nullclaw",
        .name = "mini-agent",
    }, "config");
    defer std.testing.allocator.free(route);
    try std.testing.expectEqualStrings("/api/instances/nullclaw/mini-agent/config", route);
}
