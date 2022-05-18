const std = @import("std");
const utils = @import("utils.zig");
const dif = @import("dif.zig");
const testing = std.testing;

const DifNodeMap = std.StringHashMap(*dif.DifNode);

const SemaError = error {
    NodeWithNoName, Duplicate, OutOfMemory
};

/// TODO: Raise out of sema to be a generic document context?
fn SemaContext() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        dif_root: *dif.DifNode,

        node_map: DifNodeMap,
        edge_map: DifNodeMap,
        instance_map: DifNodeMap,
        group_map: DifNodeMap,

        src_buf: []const u8,

        fn init(allocator: std.mem.Allocator, dif_root: *dif.DifNode, src_buf: []const u8) Self {
            return Self{
                .allocator = allocator,
                .dif_root = dif_root,
                .node_map = DifNodeMap.init(allocator),
                .edge_map = DifNodeMap.init(allocator),
                .instance_map = DifNodeMap.init(allocator),
                .group_map = DifNodeMap.init(allocator),
                .src_buf = src_buf,
            };
        }

        pub fn deinit(self: *Self) void {
            self.node_map.deinit();
            self.edge_map.deinit();
            self.instance_map.deinit();
            self.group_map.deinit();
        }
    };
}


/// The sema (temporary name - not sure it's accurate enough, there's possibly processing happening at some point too) step will clean up and verify the integrity of the dif-tree.
/// 
/// Responsibilities:
///   Ensure there are no name-collisions (e.g. duplicate definitions, or collisions between nodes and groups)
///   Validate parameters for node-type (Node, Edge, Instance, Relationship, Group)
/// Possibly:
///   Support partials: name-collisions are allowed, fields will just be updated
///
/// It will also populate a set of indexes to look up the different node-types by name
/// The result shall either be error, or a well-defined tree that can be easily converted to
/// the desired output format (e.g. dot). 
/// 
/// Returned SemaContext must be .deinit()'ed
pub fn doSema(allocator: std.mem.Allocator, dif_root: *dif.DifNode, src_buf: []const u8) SemaError!SemaContext() {
    var ctx = SemaContext().init(allocator, dif_root, src_buf);
    errdefer ctx.deinit();
    // std.debug.assert(nodePool.len > 0);
    try processNoDupesRecursively(&ctx, dif_root);
    return ctx;
}


fn processNoDupesRecursively(ctx: *SemaContext(), node: *dif.DifNode) SemaError!void {
    var current = node;

    while(true) {
        var node_name = current.name orelse {
            // Found node with no name... is it even possible at this stage? Bug, most likely
            return error.NodeWithNoName;
        };

        switch (current.node_type) {
            .Node => {
                if(ctx.node_map.get(node_name)) |_| {
                    utils.analysisError(ctx.src_buf, current.initial_token.?.start, "Duplicate node definition, {s} already defined.", .{node_name});
                    return error.Duplicate;
                }
                try ctx.node_map.put(node_name, current);
            },
            .Edge => {
                if(ctx.edge_map.get(node_name)) |_| {
                    utils.analysisError(ctx.src_buf, current.initial_token.?.start, "Duplicate edge definition, {s} already defined.", .{node_name});
                    return error.Duplicate;
                }
                try ctx.edge_map.put(node_name, current);
            },
            .Instantiation => {
                if(ctx.instance_map.get(node_name)) |_| {
                    utils.analysisError(ctx.src_buf, current.initial_token.?.start, "Duplicate edge definition, {s} already defined.", .{node_name});
                    return error.Duplicate;
                } else if(ctx.group_map.get(node_name)) |_| {
                    utils.analysisError(ctx.src_buf, current.initial_token.?.start, "A group with name {s} already defined, can't create instance with same name.", .{node_name});
                    return error.Duplicate;
                }
                try ctx.instance_map.put(node_name, current);
            },
            .Group => {
                if(ctx.group_map.get(node_name)) |_| {
                    utils.analysisError(ctx.src_buf, current.initial_token.?.start, "Duplicate edge definition, {s} already defined.", .{node_name});
                    return error.Duplicate;
                } else if(ctx.instance_map.get(node_name)) |_| {
                    utils.analysisError(ctx.src_buf, current.initial_token.?.start, "An instance with name {s} already defined, can't create group with same name.", .{node_name});
                    return error.Duplicate;
                }
                try ctx.group_map.put(node_name, current);
            },
            else => {},
        }

        if (current.first_child) |child| {
            try processNoDupesRecursively(ctx, child);
        }
        
        if (current.next_sibling) |next| {
            current = next;
        } else {
            break;
        }
    }
}


// Yes, these tests are integration-y
// Might at some point rewrite them to use internal dif-format, but I find it more 
// likely that the dif will change (and the work connected to it) than the hidot-syntax.
fn testSema(buf: []const u8) !void {
    const tokenizer = @import("tokenizer.zig");

    var tok = tokenizer.Tokenizer.init(buf);
    var nodePool = utils.initBoundedArray(dif.DifNode, 1024);
    var rootNode = try dif.tokensToDif(1024, &nodePool, &tok);

    var ctx = try doSema(testing.allocator, rootNode, buf);
    defer ctx.deinit();
}

test "sema fails on duplicate edge" {
    try testing.expectError(error.Duplicate, testSema(
        \\edge owns;
        \\edge owns;
        ));
}

test "sema fails on duplicate node" {
    try testing.expectError(error.Duplicate, testSema(
        \\node Component;
        \\node Component;
        ));
}

test "sema fails on duplicate instantiation" {
    try testing.expectError(error.Duplicate, testSema(
        \\node Component;
        \\node Library;
        \\compA: Component;
        \\compA: Library;
        ));
}

test "sema fails on duplicate group" {
    try testing.expectError(error.Duplicate, testSema(
        \\group MyGroup;
        \\group MyGroup;
        ));
}

test "sema fails on group with same name as instance" {
    try testing.expectError(error.Duplicate, testSema(
        \\node Component;
        \\compA: Component;
        \\group compA;
        ));
}

test "sema fails on instance with same name as group" {
    try testing.expectError(error.Duplicate, testSema(
        \\node Component;
        \\group compA;
        \\compA: Component;
        ));
}

test "sema does not fail on well-formed hidot" {
    try testing.expectEqual({}, try testSema(
        \\node Component;
        \\node Library;
        \\edge uses;
        \\edge depends_on;
        \\compA: Component;
        \\compB: Component;
        \\libA: Library;
        \\compA uses libA;
        \\compB depends_on compA;
    ));
}