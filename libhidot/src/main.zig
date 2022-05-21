const std = @import("std");
const builtin = @import("builtin");

const dif = @import("dif.zig");
const dot = @import("dot.zig");
const sema = @import("sema.zig");

const initBoundedArray = @import("utils.zig").initBoundedArray;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const tokenDump = @import("tokenizer.zig").dump;

pub const LIB_VERSION = blk: {
    if (builtin.mode != .Debug) {
        break :blk @embedFile("../VERSION");
    } else {
        break :blk @embedFile("../VERSION") ++ "-UNRELEASED";
    }
};

const debug = std.debug.print;

/// Full process from input-buffer of hidot-format to ouput-buffer of dot-format
pub fn hidotToDot(allocator: std.mem.Allocator, comptime Writer: type, writer: Writer, buf: []const u8, unit_name: []const u8) !void {
    var tokenizer = Tokenizer.init(buf[0..]);
    var node_pool = initBoundedArray(dif.DifNode, 1024);
    var root_node = try dif.tokensToDif(1024, &node_pool, &tokenizer, unit_name);
    // TODO: check for includes, and add new units accordingly
    // 1. Create a "Unit"-node, and add results of dif.tokensToDif() to this
    // 2. Iterate over this node immediate children and find all includes.
    // 3. Pr include; add as another top-level unit-sibling with parsed tokens
    // TBD: This method currently accepts the file as buffer, need to wrap it to accept path?
    // *-Unit -child-> <nodes from first compilation unit>
    // |-Unit2 -child-> <nodes frmo second compilation unit>
    //
    var sema_ctx = sema.SemaContext().init(allocator, root_node);
    errdefer sema_ctx.deinit();

    try sema.doSema(&sema_ctx);
    defer sema_ctx.deinit();

    var dot_ctx = dot.DotContext(Writer).init(writer);

    try dot.difToDot(Writer, &dot_ctx, root_node, dot.DifNodeMapSet{
        .node_map = &sema_ctx.node_map,
        .edge_map = &sema_ctx.edge_map,
        .instance_map = &sema_ctx.instance_map,
        .group_map = &sema_ctx.group_map,
    });
}

// TODO: Need to keep track of source filename, original file contents as tokens refer to it and we need it for sensical error messages.
//

const Unit = struct {
    const Self = @This();

    path: []const u8,
    contents: []const u8, // owned
    dif_root: ?*dif.DifNode = null, // ref to separate pool, not owned
    allocator: std.mem.Allocator,

    // contexts?

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        return Self{ .path = path, .allocator = allocator, .contents = try std.fs.cwd().readFileAlloc(allocator, path, 5 * 1024 * 1024) };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.contents);
    }
};

pub fn includeExploration(allocator: std.mem.Allocator, comptime Writer: type, writer:Writer, entry_file: []const u8) !void {
    // The actual buffers and path-references
    var units: [128]Unit = undefined;
    var units_idx: usize = 0;
    defer for(units[0..units_idx]) |*unit| unit.deinit();

    var node_pool = initBoundedArray(dif.DifNode, 1024);

    // Temporary storage for a single include-scan through a dif-tree
    var include_results_buf: [128]*dif.DifNode = undefined; // arbitrary sized... (TODO)

    // "Manually" set up first step, then later iterate over any includes
    units[units_idx] = try Unit.init(allocator, entry_file);
    var cur_unit = &units[units_idx];
    units_idx += 1;
    cur_unit.dif_root = try dif.bufToDif(1024, &node_pool, cur_unit.contents, cur_unit.path);

    var document_root = cur_unit.dif_root.?; // Keep to append the rest of includes to later

    var includes = try dif.findAllNodesOfType(include_results_buf[0..], cur_unit.dif_root.?, .Include);
    // TODO: Testing first with single level of includes. Later: add to queue/stack and iteratively include up until <max level>
    // TODO: Another strategy could also be to resolve includes as they appear, in-dif-tree wherever that might be
    for (includes) |include| {
        units[units_idx] = try Unit.init(allocator, include.name.?);
        cur_unit = &units[units_idx];
        units_idx += 1;
        cur_unit.dif_root = try dif.bufToDif(1024, &node_pool, cur_unit.contents, cur_unit.path);

        // join
        dif.join(document_root, cur_unit.dif_root.?);
    }

    // TBD: Could also do incremental sema on unit by unit as they are parsed
    var sema_ctx = sema.SemaContext().init(allocator, document_root);
    errdefer sema_ctx.deinit();

    try sema.doSema(&sema_ctx);
    defer sema_ctx.deinit();

    var dot_ctx = dot.DotContext(Writer).init(writer);

    try dot.difToDot(Writer, &dot_ctx, document_root, dot.DifNodeMapSet{
        .node_map = &sema_ctx.node_map,
        .edge_map = &sema_ctx.edge_map,
        .instance_map = &sema_ctx.instance_map,
        .group_map = &sema_ctx.group_map,
    });
}

test "includeExploration" {
    const bufwriter = @import("bufwriter.zig");
    var buf: [1024]u8 = undefined;
    var buf_context = bufwriter.ArrayBuf {
        .buf = buf[0..]
    };
    var writer = buf_context.writer();

    try (try std.fs.cwd().openDir("../testfiles", .{})).setAsCwd();
    try includeExploration(std.testing.allocator, @TypeOf(writer), writer, "include.hidot");

    debug("Contents: {s}\n", .{buf_context.slice()});
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
