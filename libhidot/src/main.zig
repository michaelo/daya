const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

const dif = @import("dif.zig");
const dot = @import("dot.zig");
const sema = @import("sema.zig");
const ial = @import("indexedarraylist.zig");

const initBoundedArray = @import("utils.zig").initBoundedArray;

pub const LIB_VERSION = blk: {
    if (builtin.mode != .Debug) {
        break :blk @embedFile("../VERSION");
    } else {
        break :blk @embedFile("../VERSION") ++ "-UNRELEASED";
    }
};

/// Represents a file w/ contents
const Unit = struct {
    const Self = @This();

    path: []const u8,
    contents: []const u8, // owned
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        return Self{ .path = path, .allocator = allocator, .contents = try std.fs.cwd().readFileAlloc(allocator, path, 5 * 1024 * 1024) };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.contents);
    }
};

/// Converts hidot data to dot, written to passed writer. If includes are found, it will attempt to read those files.
/// Accepts a buf to allow simple entry-point to parse arbitrary strings and not requiring actual files.
pub fn hidotToDot(allocator: std.mem.Allocator, comptime Writer: type, writer:Writer, buf: []const u8, entry_file: []const u8) !void {
    // The actual buffers and path-references TBD: Doesn't need to allocate before we've found any actual includes
    var units: [128]Unit = undefined;
    var units_idx: usize = 0;
    defer for(units[0..units_idx]) |*unit| unit.deinit();

    var node_pool = ial.IndexedArrayList(dif.DifNode).init(allocator);
    defer node_pool.deinit();

    // Temporary storage for a single include-scan through a dif-tree
    var include_results_buf: [128]ial.Entry(dif.DifNode) = undefined; // arbitrary sized... (TODO)

    // Keep to append the rest of includes to later
    var document_root = try dif.bufToDif(&node_pool, buf, entry_file);

    // Include-handling
    var includes = try dif.findAllNodesOfType(include_results_buf[0..], document_root, .Include);
    // TODO: Testing first with single level of includes. Later: add to queue/stack and iteratively include up until <max level>
    for (includes) |*include| {
        // Read and tokenize
        units[units_idx] = try Unit.init(allocator, include.get().name.?);
        var cur_unit = &units[units_idx];
        units_idx += 1;

        // Convert to dif
        var dif_root = try dif.bufToDif(&node_pool, cur_unit.contents, cur_unit.path);

        // Join with main document
        // dif.join(document_root, dif_root);
        // Join in at location of include-node
        dif_root.get().next_sibling = include.get().next_sibling;
        include.get().next_sibling = dif_root;
    }

    // TBD: Could also do incremental sema on unit by unit as they are parsed
    var sema_ctx = sema.SemaContext().init(allocator, document_root);
    errdefer sema_ctx.deinit();

    try sema.doSema(&sema_ctx);
    defer sema_ctx.deinit();

    var dot_ctx = dot.DotContext(Writer).init(writer);

    try dot.difToDot(Writer, &dot_ctx, &document_root, dot.DifNodeMapSet{
        .node_map = &sema_ctx.node_map,
        .edge_map = &sema_ctx.edge_map,
        .instance_map = &sema_ctx.instance_map,
        .group_map = &sema_ctx.group_map,
    });
}

test "hidotToDot w/ includes" {
    const bufwriter = @import("bufwriter.zig");
    var out_buf: [1024]u8 = undefined;
    var out_buf_context = bufwriter.ArrayBuf {
        .buf = out_buf[0..]
    };
    var writer = out_buf_context.writer();

    try (try std.fs.cwd().openDir("testfiles", .{})).setAsCwd();
    var file_buf = try std.fs.cwd().readFileAlloc(std.testing.allocator, "include.hidot", 5*1024*1024);
    defer std.testing.allocator.free(file_buf);

    try hidotToDot(std.testing.allocator, @TypeOf(writer), writer, file_buf, "include.hidot");
    try testing.expect(out_buf_context.slice().len > 0);
    // std.debug.print("Contents: {s}\n", .{out_buf_context.slice()});
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
