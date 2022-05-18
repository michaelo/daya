const std = @import("std");
const utils = @import("utils.zig");
const dif = @import("dif.zig");
const testing = std.testing;

const DifNodeMap = std.StringHashMap(*dif.DifNode);

const SemaError = error {
    NodeWithNoName, Duplicate, OutOfMemory, InvalidField
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

        fn printError(self: *Self, node: *dif.DifNode, comptime fmt: []const u8, args: anytype) void {
            const errPrint = std.io.getStdErr().writer().print;
            var lc = utils.idxToLineCol(self.src_buf, node.initial_token.?.start);
            errPrint("ERROR ({d}:{d}): ", .{lc.line, lc.col}) catch {};
            errPrint(fmt, args) catch {};
            errPrint("\n", .{}) catch {};
            utils.dumpSrcChunkRef(self.src_buf, node.initial_token.?.start);
            errPrint("\n", .{}) catch {};

            // Print ^ at start of symbol
            var i: usize = 0;
            if(lc.col > 0) while(i<lc.col-1): (i+=1) {
                errPrint(" ", .{}) catch {};
            };
            errPrint("^\n", .{}) catch {};
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

fn any(haystack: [][]const u8, needle: []const u8) bool {
    var found_any = false;
    for(haystack) |candidate| {
        if(std.mem.eql(u8, candidate, needle)) {
            found_any = true;
        }
    }
    return found_any;
}

test "any" {
    comptime var haystack = [_][]const u8{"label"};
    try testing.expect(any(haystack[0..], "label"));
    try testing.expect(!any(haystack[0..], "lable"));
}

fn isValidNodeField(field: []const u8) bool {
    comptime var valid_fields = [_][]const u8{"label", "bgcolor", "fgcolor", "shape", "node"};
    return any(valid_fields[0..], field);
}

fn isValidEdgeField(field: []const u8) bool {
    comptime var valid_fields = [_][]const u8{"label", "edge_style", "source_symbol", "target_symbol", "source_label", "target_label"};
    return any(valid_fields[0..], field);
}

/// Verifies that all siblings' names passes the 'verificator'
fn verifyFields(ctx: *SemaContext(), first_sibling: *dif.DifNode, verificator: fn(field: []const u8) bool) !void {
    var current = first_sibling;

    // Iterate over sibling set
    while(true) {
        switch(current.node_type) {
            .Value => {
                if(!verificator(current.name.?)) {
                    ctx.printError(current, "Unsupported parameter: '{s}'", .{current.name});
                    return error.InvalidField;
                }
            },
            else => {
                ctx.printError(current, "Unsupported child-type '{s}' for: {s}", .{@TypeOf(current.node_type), current.name});
                return error.InvalidField;
            }
        }

        if (current.next_sibling) |next| {
            current = next;
        } else {
            break;
        }
    }
}

/// Verify integrity of dif-graph. Fails on duplicate definitions and invalid fields.
/// Aborts at first error.
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
                    ctx.printError(current, "Duplicate node definition, {s} already defined.", .{node_name});
                    return error.Duplicate;
                }

                if(current.first_child) |child| {
                    try verifyFields(ctx, child, isValidNodeField);
                }

                try ctx.node_map.put(node_name, current);
            },
            .Edge => {
                if(ctx.edge_map.get(node_name)) |_| {
                    ctx.printError(current, "Duplicate edge definition, {s} already defined.", .{node_name});
                    return error.Duplicate;
                }

                if(current.first_child) |child| {
                    try verifyFields(ctx, child, isValidEdgeField);
                }

                try ctx.edge_map.put(node_name, current);
            },
            .Instantiation => {
                if(ctx.instance_map.get(node_name)) |_| {
                    ctx.printError(current, "Duplicate edge definition, {s} already defined.", .{node_name});
                    return error.Duplicate;
                } else if(ctx.group_map.get(node_name)) |_| {
                    ctx.printError(current, "A group with name {s} already defined, can't create instance with same name.", .{node_name});
                    return error.Duplicate;
                }

                if(current.first_child) |child| {
                    try verifyFields(ctx, child, isValidNodeField);
                }

                try ctx.instance_map.put(node_name, current);
            },
            .Group => {
                if(ctx.group_map.get(node_name)) |_| {
                    ctx.printError(current, "Duplicate edge definition, {s} already defined.", .{node_name});
                    return error.Duplicate;
                } else if(ctx.instance_map.get(node_name)) |_| {
                    ctx.printError(current, "An instance with name {s} already defined, can't create group with same name.", .{node_name});
                    return error.Duplicate;
                }
                // TODO: Verify valid group fields
                try ctx.group_map.put(node_name, current);
            },
            .Relationship => {
                if(current.first_child) |child| {
                    try verifyFields(ctx, child, isValidEdgeField);
                }
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

test "sema fails on invalid fields for node" {
    try testing.expectError(error.InvalidField, testSema(
        \\node Component {
        \\    lable="misspelled";
        \\}
        ));
}

test "sema fails on invalid fields for instance" {
    try testing.expectError(error.InvalidField, testSema(
        \\node Component {
        \\    label="label here";
        \\}
        \\mynode: Component {
        \\    lable="misspelled";
        \\}
        ));
}

test "sema fails on invalid fields for edge" {
    try testing.expectError(error.InvalidField, testSema(
        \\edge owns {
        \\    lable="misspelled";
        \\}
        ));
}

test "sema fails on invalid fields for relationship" {
    try testing.expectError(error.InvalidField, testSema(
        \\node Component;
        \\edge owns;
        \\mynode: Component;
        \\mynode2: Component;
        \\mynode owns mynode2 {
        \\    lable="misspelled";
        \\}
        ));
}
