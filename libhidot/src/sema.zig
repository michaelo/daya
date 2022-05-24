const std = @import("std");
const utils = @import("utils.zig");
const dif = @import("dif.zig");
const ial = @import("indexedarraylist.zig");
const testing = std.testing;
const any = utils.any;

const DifNodeMap = std.StringHashMap(ial.Entry(dif.DifNode));

const SemaError = error {
    NodeWithNoName, Duplicate, OutOfMemory, InvalidField
};

pub fn SemaContext() type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        dif_root: ial.Entry(dif.DifNode),

        node_map: DifNodeMap,
        edge_map: DifNodeMap,
        instance_map: DifNodeMap,
        group_map: DifNodeMap,

        pub fn init(allocator: std.mem.Allocator, dif_root: ial.Entry(dif.DifNode)) Self {
            return Self{
                .allocator = allocator,
                .dif_root = dif_root,
                .node_map = DifNodeMap.init(allocator),
                .edge_map = DifNodeMap.init(allocator),
                .instance_map = DifNodeMap.init(allocator),
                .group_map = DifNodeMap.init(allocator),
            };
        }

        fn findUnit(node: *ial.Entry(dif.DifNode)) !*ial.Entry(dif.DifNode) {
            var current = node;
            while(current.get().node_type != .Unit) {
                if(current.get().parent) |*parent| {
                    current = parent;
                } else {
                    // Ending up here is a bug
                    return error.NoUnitFound;
                }
            }
            return current;
        }

        fn printError(self: *Self, node: *ial.Entry(dif.DifNode), comptime fmt: []const u8, args: anytype) void {
            _ = self;
            const err_writer = std.io.getStdErr().writer();
            const unit = findUnit(node) catch {
                err_writer.print("BUG: Could not find unit associated with node\n", .{}) catch {};
                unreachable;
            };
            const src_buf = unit.get().data.Unit.src_buf;
            const lc = utils.idxToLineCol(src_buf, node.get().initial_token.?.start);
            err_writer.print("{s}:{d}:{d}: error: ", .{unit.get().name.?, lc.line, lc.col}) catch {};
            err_writer.print(fmt, args) catch {};
            err_writer.print("\n", .{}) catch {};
            utils.dumpSrcChunkRef(@TypeOf(err_writer), err_writer, src_buf, node.get().initial_token.?.start);
            err_writer.print("\n", .{}) catch {};

            // Print ^ at start of symbol
            var i: usize = 0;
            if(lc.col > 0) while(i<lc.col-1): (i+=1) {
                err_writer.print(" ", .{}) catch {};
            };
            err_writer.print("^\n", .{}) catch {};
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
pub fn doSema(ctx: *SemaContext()) SemaError!void {
    try processNoDupesRecursively(ctx, &ctx.dif_root);
}

fn isValidNodeField(field: []const u8) bool {
    comptime var valid_fields = [_][]const u8{"label", "bgcolor", "fgcolor", "shape", "note"};
    return any(valid_fields[0..], field);
}

fn isValidEdgeField(field: []const u8) bool {
    comptime var valid_fields = [_][]const u8{"label", "edge_style", "source_symbol", "target_symbol", "source_label", "target_label"};
    return any(valid_fields[0..], field);
}

/// Verifies that all siblings' names passes the 'verificator'
fn verifyFields(ctx: *SemaContext(), first_sibling: *ial.Entry(dif.DifNode), verificator: fn(field: []const u8) bool) !void {
    var current = first_sibling;

    // Iterate over sibling set
    while(true) {
        switch(current.get().node_type) {
            .Value => {
                if(!verificator(current.get().name.?)) {
                    ctx.printError(current, "Unsupported parameter: '{s}'", .{current.get().name});
                    return error.InvalidField;
                }
            },
            else => {
                ctx.printError(current, "Unsupported child-type '{s}' for: {s}", .{@TypeOf(current.get().node_type), current.get().name});
                return error.InvalidField;
            }
        }

        if (current.get().next_sibling) |*next| {
            current = next;
        } else {
            break;
        }
    }
}

/// Verify integrity of dif-graph. Fails on duplicate definitions and invalid fields.
/// Aborts at first error.
fn processNoDupesRecursively(ctx: *SemaContext(), node: *ial.Entry(dif.DifNode)) SemaError!void {
    var current_ref = node;

    while(true) {
        const current = current_ref.get();
        const node_name = current.name orelse {
            // Found node with no name... is it even possible at this stage? Bug, most likely
            return error.NodeWithNoName;
        };

        switch (current.node_type) {
            .Node => {
                if(ctx.node_map.get(node_name)) |*conflict_ref| {
                    ctx.printError(current_ref, "Duplicate node definition, '{s}' already defined.", .{node_name});
                    ctx.printError(conflict_ref, "Previous definition was here.", .{});
                    return error.Duplicate;
                }

                if(current.first_child) |*child| {
                    try verifyFields(ctx, child, isValidNodeField);
                }

                try ctx.node_map.put(node_name, current_ref.*);
            },
            .Edge => {
                if(ctx.edge_map.get(node_name)) |*conflict_ref| {
                    ctx.printError(current_ref, "Duplicate edge definition, '{s}' already defined.", .{node_name});
                    ctx.printError(conflict_ref, "Previous definition was here.", .{});
                    return error.Duplicate;
                }

                if(current.first_child) |*child| {
                    try verifyFields(ctx, child, isValidEdgeField);
                }

                try ctx.edge_map.put(node_name, current_ref.*);
            },
            .Instantiation => {
                if(ctx.instance_map.get(node_name)) |*conflict_ref| {
                    ctx.printError(current_ref, "Duplicate edge definition, '{s}' already defined.", .{node_name});
                    ctx.printError(conflict_ref, "Previous definition was here.", .{});
                    return error.Duplicate;
                } else if(ctx.group_map.get(node_name)) |*conflict_ref| {
                    ctx.printError(current_ref, "A group with name '{s}' already defined, can't create instance with same name.", .{node_name});
                    ctx.printError(conflict_ref, "Previous definition was here.", .{});
                    return error.Duplicate;
                }

                if(current.first_child) |*child| {
                    try verifyFields(ctx, child, isValidNodeField);
                }

                try ctx.instance_map.put(node_name, current_ref.*);
            },
            .Group => {
                if(ctx.group_map.get(node_name)) |*conflict_ref| {
                    ctx.printError(current_ref, "Duplicate edge definition, {s} already defined.", .{node_name});
                    ctx.printError(conflict_ref, "Previous definition was here.", .{});
                    return error.Duplicate;
                } else if(ctx.instance_map.get(node_name)) |*conflict_ref| {
                    ctx.printError(current_ref, "An instance with name '{s}' already defined, can't create group with same name.", .{node_name});
                    ctx.printError(conflict_ref, "Previous definition was here.", .{});
                    return error.Duplicate;
                }
                // TODO: Verify valid group fields
                try ctx.group_map.put(node_name, current_ref.*);
            },
            .Relationship => {
                if(current.first_child) |*child| {
                    try verifyFields(ctx, child, isValidEdgeField);
                }
            },
            else => {},
        }

        if (current.first_child) |*child| {
            try processNoDupesRecursively(ctx, child);
        }
        
        if (current.next_sibling) |*next| {
            current_ref = next;
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
    var node_pool = ial.IndexedArrayList(dif.DifNode).init(std.testing.allocator);
    defer node_pool.deinit();

    var root_node = try dif.tokensToDif(&node_pool, &tok, "test");

    var ctx = SemaContext().init(std.testing.allocator, root_node);
    errdefer ctx.deinit();

    try doSema(&ctx);
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
