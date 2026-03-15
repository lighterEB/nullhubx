const std = @import("std");

pub const CatalogEntry = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8 = "",
    recommended: bool = false,
    install_kind: []const u8,
    source: ?[]const u8 = null,
    homepage_url: ?[]const u8 = null,
    clawhub_slug: ?[]const u8 = null,
    always: bool = false,
};

pub const InstallDisposition = enum {
    installed,
    updated,
};

const BundledSkill = struct {
    entry: CatalogEntry,
    instructions: []const u8,
};

const clawhub_url = "https://clawhub.ai";

const bundled_skills = [_]BundledSkill{
    .{
        .entry = .{
            .name = "nullhub-admin",
            .version = "0.1.0",
            .description = "Teach managed nullclaw agents to discover NullHub routes first and then use nullhub api for instance, provider, component, and orchestration tasks.",
            .recommended = true,
            .install_kind = "bundled",
            .homepage_url = clawhub_url,
            .always = true,
        },
        .instructions = @embedFile("bundled_skills/nullhub-admin/SKILL.md"),
    },
};

pub fn catalogForComponent(component: []const u8) []const BundledSkill {
    if (std.mem.eql(u8, component, "nullclaw")) return bundled_skills[0..];
    return &.{};
}

pub fn installBundledSkill(
    allocator: std.mem.Allocator,
    workspace_dir: []const u8,
    skill_name: []const u8,
) !InstallDisposition {
    const bundled = findBundledSkill(skill_name) orelse return error.SkillNotFound;

    const skills_dir = try std.fs.path.join(allocator, &.{ workspace_dir, "skills" });
    defer allocator.free(skills_dir);
    try ensurePathAbsolute(skills_dir);

    const skill_dir = try std.fs.path.join(allocator, &.{ skills_dir, bundled.entry.name });
    defer allocator.free(skill_dir);
    try ensurePathAbsolute(skill_dir);

    const skill_md_path = try std.fs.path.join(allocator, &.{ skill_dir, "SKILL.md" });
    defer allocator.free(skill_md_path);

    const existing = readOptionalFileAlloc(allocator, skill_md_path, bundled.instructions.len + 4096) catch null;
    defer if (existing) |bytes| allocator.free(bytes);

    const file = try std.fs.createFileAbsolute(skill_md_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bundled.instructions);

    if (existing) |bytes| {
        if (std.mem.eql(u8, bytes, bundled.instructions)) return .installed;
        return .updated;
    }
    return .installed;
}

fn ensurePathAbsolute(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn findBundledSkill(name: []const u8) ?BundledSkill {
    for (bundled_skills) |bundled| {
        if (std.mem.eql(u8, bundled.entry.name, name)) return bundled;
    }
    return null;
}

fn readOptionalFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) !?[]u8 {
    const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();
    return try file.readToEndAlloc(allocator, max_bytes);
}

test "catalogForComponent returns nullclaw recommendations" {
    const catalog = catalogForComponent("nullclaw");
    try std.testing.expect(catalog.len > 0);
    try std.testing.expectEqualStrings("nullhub-admin", catalog[0].entry.name);
    try std.testing.expect(catalog[0].entry.recommended);
}

test "installBundledSkill writes embedded skill to workspace" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const cwd_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);

    const disposition = try installBundledSkill(allocator, cwd_path, "nullhub-admin");
    try std.testing.expectEqual(.installed, disposition);

    const skill_path = try std.fs.path.join(allocator, &.{ cwd_path, "skills", "nullhub-admin", "SKILL.md" });
    defer allocator.free(skill_path);

    const content = try std.fs.readFileAbsolute(allocator, skill_path, 64 * 1024);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "nullhub routes --json") != null);
}
