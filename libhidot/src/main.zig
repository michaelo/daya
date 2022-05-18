const std = @import("std");
const builtin = @import("builtin");

const dif = @import("dif.zig");
const dot = @import("dot.zig");
const sema = @import("sema.zig");

const initBoundedArray = @import("utils.zig").initBoundedArray;
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub const LIB_VERSION = blk: {
    if (builtin.mode != .Debug) {
        break :blk @embedFile("../VERSION");
    } else {
        break :blk @embedFile("../VERSION") ++ "-UNRELEASED";
    }
};

const debug = std.debug.print;

/// Full process from input-buffer of hidot-format to ouput-buffer of dot-format
pub fn hidotToDot(comptime Writer: type, writer: Writer, buf: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var tokenizer = Tokenizer.init(buf[0..]);
    var node_pool = initBoundedArray(dif.DifNode, 1024);
    var root_node = try dif.tokensToDif(1024, &node_pool, &tokenizer);
    // TODO: check for includes, and add new units accordingly
    // 1. Create a "Unit"-node, and add results of dif.tokensToDif() to this
    // 2. Iterate over this node immediate children and find all includes.
    // 3. Pr include; add as another top-level unit-sibling with parsed tokens
    // TBD: This method currently accepts the file as buffer, need to wrap it to accept path?
    // *-Unit -child-> <nodes from first compilation unit>
    // |-Unit2 -child-> <nodes frmo second compilation unit>
    // 

    var sema_ctx = try sema.doSema(allocator, root_node, buf);
    defer sema_ctx.deinit();

    var dot_ctx = dot.DotContext(Writer).init(writer, buf);
    
    try dot.difToDot(Writer, &dot_ctx, root_node, dot.DifNodeMapSet{
        .node_map = &sema_ctx.node_map,
        .edge_map = &sema_ctx.edge_map,
        .instance_map = &sema_ctx.instance_map,
        .group_map = &sema_ctx.group_map,
    });
}

pub fn readFile(base_dir: std.fs.Dir, path: []const u8, target_buf: []u8) !usize {
    var file = try base_dir.openFile(path, .{ .read = true });
    defer file.close();

    return try file.readAll(target_buf[0..]);
}

pub fn writeFile(base_dir: std.fs.Dir, path: []const u8, target_buf: []u8) !void {
    var file = try base_dir.createFile(path, .{ .truncate = true });
    defer file.close();

    return try file.writeAll(target_buf[0..]);
}


test "test entry" {
    comptime {
        _ = @import("dif.zig");
        _ = @import("tokenizer.zig");
        _ = @import("utils.zig");
        _ = @import("bufwriter.zig");
        _ = @import("dot.zig");
        _ = @import("sema.zig");
    }
}