const std = @import("std");

pub fn deinitInstances(allocator: std.mem.Allocator, instances: anytype) void {
    var comp_it = instances.iterator();
    while (comp_it.next()) |comp_entry| {
        var inst_it = comp_entry.value_ptr.iterator();
        while (inst_it.next()) |inst_entry| {
            allocator.free(inst_entry.value_ptr.version);
            allocator.free(inst_entry.value_ptr.launch_mode);
            allocator.free(inst_entry.key_ptr.*);
        }
        comp_entry.value_ptr.deinit();
        allocator.free(comp_entry.key_ptr.*);
    }
    instances.deinit();
}

pub fn addInstance(state: anytype, component: []const u8, name: []const u8, entry: anytype, instance_map_init: anytype) !void {
    const inner_ptr = blk: {
        if (state.instances.getPtr(component)) |ptr| break :blk ptr;
        const owned_comp = try state.allocator.dupe(u8, component);
        errdefer state.allocator.free(owned_comp);
        try state.instances.put(owned_comp, instance_map_init(state.allocator));
        break :blk state.instances.getPtr(component).?;
    };

    const owned_name = try state.allocator.dupe(u8, name);
    errdefer state.allocator.free(owned_name);
    const owned_launch_mode = try state.allocator.dupe(u8, entry.launch_mode);
    errdefer state.allocator.free(owned_launch_mode);
    const owned_entry = @TypeOf(entry){
        .version = try state.allocator.dupe(u8, entry.version),
        .auto_start = entry.auto_start,
        .launch_mode = owned_launch_mode,
        .verbose = entry.verbose,
    };
    try inner_ptr.put(owned_name, owned_entry);
}

pub fn removeInstance(state: anytype, component: []const u8, name: []const u8) bool {
    const inner = state.instances.getPtr(component) orelse return false;
    const entry = inner.fetchSwapRemove(name) orelse return false;

    state.allocator.free(entry.value.version);
    state.allocator.free(entry.value.launch_mode);
    state.allocator.free(entry.key);

    if (inner.count() == 0) {
        const comp = state.instances.fetchSwapRemove(component).?;
        var map = comp.value;
        map.deinit();
        state.allocator.free(comp.key);
    }

    return true;
}

pub fn getInstance(state: anytype, component: []const u8, name: []const u8) ?@TypeOf(state.instances.values()[0].values()[0]) {
    const inner = state.instances.get(component) orelse return null;
    return inner.get(name);
}

pub fn updateInstance(state: anytype, component: []const u8, name: []const u8, entry: anytype) !bool {
    const inner = state.instances.getPtr(component) orelse return false;
    const ptr = inner.getPtr(name) orelse return false;

    const new_version = try state.allocator.dupe(u8, entry.version);
    errdefer state.allocator.free(new_version);
    const new_launch_mode = try state.allocator.dupe(u8, entry.launch_mode);
    errdefer state.allocator.free(new_launch_mode);

    state.allocator.free(ptr.version);
    state.allocator.free(ptr.launch_mode);
    ptr.version = new_version;
    ptr.launch_mode = new_launch_mode;
    ptr.auto_start = entry.auto_start;
    ptr.verbose = entry.verbose;
    return true;
}

pub fn componentNames(state: anytype) ![][]const u8 {
    const keys = state.instances.keys();
    const result = try state.allocator.alloc([]const u8, keys.len);
    @memcpy(result, keys);
    return result;
}

pub fn instanceNames(state: anytype, component: []const u8) !?[][]const u8 {
    const inner = state.instances.getPtr(component) orelse return null;
    const keys = inner.keys();
    const result = try state.allocator.alloc([]const u8, keys.len);
    @memcpy(result, keys);
    return result;
}
