/// Module responsible for parsing tokens to the Diagrammer Internal Format
/// General strategy
/// For text: We start with simply storing slices of the input-data in the Dif
/// If we later find we need to preprocess something, we'll reconsider and add dedicated storage
const std = @import("std");
const utils = @import("utils.zig");
const Token = @import("tokenizer.zig").Token;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const tokenizerDump = @import("tokenizer.zig").dump;
const debug = std.debug.print;
const testing = std.testing;

const ial = @import("indexedarraylist.zig");

const ParseError = error{ UnexpectedToken, InvalidValue, OutOfMemory };

const DifNodeType = enum {
    Unit, // aka file - a top node intended to contain all the nodes parsed from the same source
    Edge,
    Node,
    Group,
    Layer, // TODO: Implement
    Instantiation,
    Relationship,
    Value, // key=value
    Include,
};

pub const DifNode = struct {
    const Self = @This();

    // Common fields
    node_type: DifNodeType,
    parent: ?ial.Entry(Self) = null,
    first_child: ?ial.Entry(Self) = null,
    next_sibling: ?ial.Entry(Self) = null,
    initial_token: ?Token = null, // Reference back to source
    name: ?[]const u8 = null,

    data: union(DifNodeType) {
        Unit: struct {
            src_buf: []const u8, // Reference to the source buffer, to e.g. look up surrounding code for error message etc.
        },
        Edge: struct {},
        Node: struct {},
        Group: struct {},
        Layer: struct {},
        Instantiation: struct {
            target: []const u8,
        },
        Relationship: struct {
            edge: []const u8,
            target: []const u8,
        },
        Value: struct {
            value: []const u8,
        },
        Include: struct {},
    },
};

pub const NodeShape = enum {
    box,
    circle,
    ellipse,
    diamond,
    polygon,
    cylinder,

    pub fn fromString(name: []const u8) !NodeShape {
        return std.meta.stringToEnum(NodeShape, name) orelse error.InvalidValue;
    }
};

pub const EdgeStyle = enum {
    solid,
    dotted,
    dashed,
    bold,

    pub fn fromString(name: []const u8) !EdgeStyle {
        return std.meta.stringToEnum(EdgeStyle, name) orelse error.InvalidValue;
    }
};

pub const EdgeEndStyle = enum {
    none,
    arrow_open,
    arrow_closed,
    arrow_filled,

    pub fn fromString(name: []const u8) !EdgeEndStyle {
        return std.meta.stringToEnum(EdgeEndStyle, name) orelse error.InvalidValue;
    }
};

const DififierState = enum {
    start,
    kwnode,
    kwedge,
    kwgroup,
    kwlayer,
    definition, // Common type for any non-keyword-definition
};

/// Entry-function to module. Returns reference to first top-level node in graph, given a text buffer.
pub fn bufToDif(node_pool: *ial.IndexedArrayList(DifNode), buf: []const u8, unit_name: []const u8) !ial.Entry(DifNode) {
    var tokenizer = Tokenizer.init(buf);
    return try tokensToDif(node_pool, &tokenizer, unit_name);
}

/// Entry-function to module. Returns reference to first top-level node in graph, given a tokenizer.
pub fn tokensToDif(node_pool: *ial.IndexedArrayList(DifNode), tokenizer: *Tokenizer, unit_name: []const u8) !ial.Entry(DifNode) {
    var initial_len = node_pool.storage.items.len;

    // Create top-level node for unit
    var unit_node = node_pool.addOne() catch {
        return error.OutOfMemory;
    };
    unit_node.get().* = DifNode{ .node_type = .Unit, .name = unit_name, .initial_token = null, .data = .{ .Unit = .{ .src_buf = tokenizer.buf } } };

    parseTokensRecursively(node_pool, tokenizer, unit_node) catch {
        return error.ParseError;
    };

    if (node_pool.storage.items.len <= initial_len) {
        return error.NothingFound;
    }

    return unit_node;
}

pub fn parseTokensRecursively(node_pool: *ial.IndexedArrayList(DifNode), tokenizer: *Tokenizer, maybe_parent: ?ial.Entry(DifNode)) ParseError!void {
    var state: DififierState = .start;

    var parent = maybe_parent;
    var prev_sibling: ?ial.Entry(DifNode) = null;

    var tok: Token = undefined;
    main: while (true) {
        switch (state) {
            .start => {
                tok = tokenizer.nextToken();
                switch (tok.typ) {
                    .eof => {
                        break :main;
                    },
                    .eos => {
                        state = .start;
                    },
                    .brace_end => {
                        // backing up, backing up...
                        break :main;
                    },
                    .identifier => {
                        // identifier can be relevant for either instantiation, relationship or key/value.
                        state = .definition;
                    },
                    .keyword_edge, .keyword_node, .keyword_layer, .keyword_group => {

                        // Create node for edge, with value=name-slice
                        // If data-chunk follows; recurse and pass current node as parent
                        var node = node_pool.addOne() catch {
                            return error.OutOfMemory;
                        };

                        // Get label
                        var initial_token = tok;
                        tok = tokenizer.nextToken();
                        if (tok.typ != .identifier) {
                            parseError(tokenizer.buf, tok.start, "Expected identifier, got token type '{s}'", .{@tagName(tok.typ)});
                            return error.UnexpectedToken;
                        }

                        node.get().* = switch (initial_token.typ) {
                            .keyword_edge => DifNode{ .node_type = .Edge, .parent = parent, .name = tok.slice, .initial_token = initial_token, .data = .{ .Edge = .{} } },
                            .keyword_node => DifNode{ .node_type = .Node, .parent = parent, .name = tok.slice, .initial_token = initial_token, .data = .{ .Node = .{} } },
                            .keyword_group => DifNode{ .node_type = .Group, .parent = parent, .name = tok.slice, .initial_token = initial_token, .data = .{ .Group = .{} } },
                            .keyword_layer => DifNode{ .node_type = .Layer, .parent = parent, .name = tok.slice, .initial_token = initial_token, .data = .{ .Layer = .{} } },
                            else => unreachable, // as long as this set of cases matches the ones leading to this branch
                        };

                        if (parent) |*realparent| {
                            if (realparent.get().first_child == null) {
                                realparent.get().first_child = node;
                            }
                        }

                        if (prev_sibling) |*prev| {
                            prev.get().next_sibling = node;
                        }
                        prev_sibling = node;

                        tok = tokenizer.nextToken();
                        switch (tok.typ) {
                            .eos => {},
                            .brace_start => {
                                // Recurse
                                try parseTokensRecursively(node_pool, tokenizer, node);
                            },
                            else => {
                                parseError(tokenizer.buf, tok.start, "Unexpected token type '{s}', expected {{ or ;", .{@tagName(tok.typ)});
                                return error.UnexpectedToken;
                            },
                        }
                        state = .start;
                    },
                    .include => {
                        var node = node_pool.addOne() catch {
                            return error.OutOfMemory;
                        };

                        node.get().* = DifNode{
                            .node_type = .Include,
                            .parent = parent,
                            .name = tok.slice[1..],
                            .initial_token = tok,
                            .data = .{
                                .Include = .{},
                            },
                        };

                        if (parent) |*realparent| {
                            if (realparent.get().first_child == null) {
                                realparent.get().first_child = node;
                            }
                        }

                        if (prev_sibling) |*prev| {
                            prev.get().next_sibling = node;
                        }
                        prev_sibling = node;
                    },
                    else => {
                        parseError(tokenizer.buf, tok.start, "Unexpected token type '{s}'", .{@tagName(tok.typ)});
                        return error.UnexpectedToken;
                    },
                }
            },
            .definition => {
                // Check for either instantiation, key/value or relationship
                // instantiation: identifier   colon    identifier        + ; or {}
                // key/value    : identifier   equal    identifier/string + ;
                // relationship : identifier identifier identifier        + ; or {}
                // Att! These can be followed by either ; or {  (e.g. can contain children-set), if so; recurse

                var token1 = tok;
                std.debug.assert(token1.typ == .identifier);

                var token2 = tokenizer.nextToken();
                var token3 = tokenizer.nextToken();

                // TODO: these pointers don't remain valid. Need either a persistant area, or discrete allocations
                //       could be resolved by storing indexes, then use those to traverse further. Perf?
                var node = node_pool.addOne() catch {
                    return error.OutOfMemory;
                };

                switch (token2.typ) {
                    .equal => {
                        // key/value
                        node.get().* = DifNode{
                            .node_type = .Value,
                            .parent = parent,
                            .name = token1.slice,
                            .initial_token = token1,
                            .data = .{
                                .Value = .{
                                    // TODO: Currently assuming single-token value for simplicity. This will likely not be the case for e.g. numbers with units
                                    .value = token3.slice,
                                },
                            },
                        };
                    },
                    .colon => {
                        // instantiation
                        node.get().* = DifNode{ .node_type = .Instantiation, .parent = parent, .name = token1.slice, .initial_token = token1, .data = .{
                            .Instantiation = .{
                                .target = token3.slice,
                            },
                        } };
                    },
                    .identifier => {
                        // relationship
                        node.get().* = DifNode{
                            .node_type = .Relationship,
                            .parent = parent,
                            .name = token1.slice, // source... Otherwise create an ID here, and keep source, edge and target all in .data? (TODO)
                            .initial_token = token1,
                            .data = .{
                                .Relationship = .{
                                    .edge = token2.slice,
                                    .target = token3.slice,
                                },
                            },
                        };
                    },
                    else => {
                        parseError(tokenizer.buf, token2.start, "Unexpected token type '{s}', expected =, : or an identifier", .{@tagName(token2.typ)});
                        return error.UnexpectedToken;
                    }, // invalid
                }

                if (parent) |*realparent| {
                    if (realparent.get().first_child == null) {
                        realparent.get().first_child = node;
                    }
                }

                if (prev_sibling) |*prev| {
                    prev.get().next_sibling = node;
                }
                prev_sibling = node;

                var token4 = tokenizer.nextToken();

                switch (token4.typ) {
                    // .brace_end,
                    .eos => {},
                    .brace_start => {
                        try parseTokensRecursively(node_pool, tokenizer, node);
                    },
                    else => {
                        parseError(tokenizer.buf, token4.start, "Unexpected token type '{s}', expected ; or {{", .{@tagName(token4.typ)});
                        return error.UnexpectedToken;
                    }, // invalid
                }
                state = .start;
                tok = token4;
            },
            else => {},
        }
    }
}

test "dif (parseTokensRecursively) parses include statement" {
    {
        var node_pool = ial.IndexedArrayList(DifNode).init(std.testing.allocator);
        defer node_pool.deinit();

        var root_a = try bufToDif(&node_pool,
            \\@myfile.hidot
        , "test");

        try testing.expectEqual(DifNodeType.Include, root_a.get().first_child.?.get().node_type);
        try testing.expectEqualStrings("myfile.hidot", root_a.get().first_child.?.get().name.?);
    }

    {
        var node_pool = ial.IndexedArrayList(DifNode).init(std.testing.allocator);
        defer node_pool.deinit();

        var root_a = try bufToDif(&node_pool,
            \\@myfile.hidot
            \\node Node;
        , "test");

        try testing.expectEqual(DifNodeType.Include, root_a.get().first_child.?.get().node_type);
        try testing.expectEqualStrings("myfile.hidot", root_a.get().first_child.?.get().name.?);
        try testing.expectEqual(DifNodeType.Node, root_a.get().first_child.?.get().next_sibling.?.get().node_type);
    }
}

/// Join two dif-graphs: adds second to end of first
pub fn join(base_root: ial.Entry(DifNode), to_join: ial.Entry(DifNode)) void {
    var current = base_root;

    // Find last sibling
    while (true) {
        if (current.get().next_sibling) |next| {
            current = next;
        } else {
            break;
        }
    }

    // join to_join as as new sibling
    current.get().next_sibling = to_join;
}

test "join" {
    var node_pool = ial.IndexedArrayList(DifNode).init(std.testing.allocator);
    defer node_pool.deinit();

    var root_a = try bufToDif(&node_pool,
        \\node Component;
        \\edge owns;
    , "test");
    try testing.expectEqual(node_pool.storage.items.len, 3);
    try testing.expectEqualStrings("owns", node_pool.storage.items[2].name.?);

    var root_b = try bufToDif(&node_pool,
        \\compA: Component;
        \\compB: Component;
        \\compA owns compB;
    , "test");

    join(root_a, root_b);

    try testing.expectEqual(node_pool.storage.items.len, 7);
    try testing.expectEqualStrings("compA", node_pool.storage.items[6].name.?);
    try testing.expectEqual(DifNodeType.Relationship, node_pool.storage.items[6].node_type);
}

// test/debug
pub fn dumpDifAst(node: *DifNode, level: u8) void {
    var i: usize = 0;
    while (i < level) : (i += 1) debug("  ", .{});
    debug("{s}: {s}\n", .{ @tagName(node.node_type), node.name });

    if (node.first_child) |*child| {
        dumpDifAst(child.get(), level + 1);
    }

    if (node.next_sibling) |*next| {
        dumpDifAst(next.get(), level);
    }
}

// test/debug
fn parseAndDump(buf: []const u8) void {
    tokenizerDump(buf);
    var tokenizer = Tokenizer.init(buf[0..]);
    var node_pool = ial.IndexedArrayList(DifNode).init(std.testing.allocator);
    defer node_pool.deinit();

    parseTokensRecursively(1024, &node_pool, &tokenizer, null) catch {
        debug("Got error parsing\n", .{});
    };
    dumpDifAst(&node_pool.storage.items[0], 0);
}

pub fn parseError(src: []const u8, start_idx: usize, comptime fmt: []const u8, args: anytype) void {
    const writer = std.io.getStdErr().writer();

    var lc = utils.idxToLineCol(src, start_idx);
    writer.print("PARSE ERROR ({d}:{d}): ", .{ lc.line, lc.col }) catch {};
    writer.print(fmt, args) catch {};
    writer.print("\n", .{}) catch {};
    utils.dumpSrcChunkRef(@TypeOf(writer), writer, src, start_idx);
    writer.print("\n", .{}) catch {};
    var i: usize = 0;
    if (lc.col > 0) while (i < lc.col - 1) : (i += 1) {
        writer.print(" ", .{}) catch {};
    };
    writer.print("^\n", .{}) catch {};
}

/// Traverse through DifNode-tree as identified by node. For all nodes matching node_type: add to result_buf.
/// Will fail with .TooManyMatches if num matches exceeds result_buf.len
pub fn findAllNodesOfType(result_buf: []ial.Entry(DifNode), node: ial.Entry(DifNode), node_type: DifNodeType) error{TooManyMatches}![]ial.Entry(DifNode) {
    var current = node;

    var next_idx: usize = 0;

    while (true) {
        // Got match?
        if (current.get().node_type == node_type) {
            if (next_idx >= result_buf.len) return error.TooManyMatches;

            result_buf[next_idx] = current;
            next_idx += 1;
        }

        // Recurse into children sets
        if (current.get().first_child) |child| {
            next_idx += (try findAllNodesOfType(result_buf[next_idx..], child, node_type)).len;
        }

        // Iterate the sibling set
        if (current.get().next_sibling) |next| {
            current = next;
        } else {
            break;
        }
    }

    return result_buf[0..next_idx];
}

test "findAllNodesOfType find all nodes of given type" {

    // Simple case: only sibling set
    {
        var node_pool = ial.IndexedArrayList(DifNode).init(std.testing.allocator);
        defer node_pool.deinit();

        var root_a = try bufToDif(&node_pool,
            \\node Component;
            \\edge owns;
            \\edge uses;
        , "test");

        var result_buf: [16]ial.Entry(DifNode) = undefined;

        try testing.expectEqual((try findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Node)).len, 1);
        try testing.expectEqual((try findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Edge)).len, 2);
    }

    // Advanced case: siblings and children
    {
        var node_pool = ial.IndexedArrayList(DifNode).init(std.testing.allocator);
        defer node_pool.deinit();

        var root_a = try bufToDif(&node_pool,
            \\edge woop;
            \\group mygroup {
            \\  edge owns;
            \\  node Component;
            \\  node Lib;
            \\}
        , "test");

        var result_buf: [16]ial.Entry(DifNode) = undefined;

        try testing.expectEqual((try findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Edge)).len, 2);
        try testing.expectEqual((try findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Node)).len, 2);
    }
}

test "findAllNodesOfType fails with error.TooManyMatches if buffer too small" {
    var node_pool = ial.IndexedArrayList(DifNode).init(std.testing.allocator);
    defer node_pool.deinit();

    var root_a = try bufToDif(&node_pool,
        \\node Component;
    , "test");

    var result_buf: [0]ial.Entry(DifNode) = undefined;

    try testing.expectError(error.TooManyMatches, findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Node));
}

/// Iterator-like interface for searching a dif-tree. Depth-first.
pub const DifTraverser = struct {
    const Self = @This();

    next_node: ?*ial.Entry(DifNode),
    node_type: DifNodeType,

    pub fn init(root: *ial.Entry(DifNode), node_type: DifNodeType) Self {
        return Self {
            .next_node = root,
            .node_type = node_type
        };
    }

    /// Will traverse each node in a well-formed dif-graph, depth-first, returning any
    /// nodes of the desired node-type specified at .init().
    /// Assumed that the .init()-specified root-node is the actual root of the dif-tree.
    pub fn next(self: *Self) ?*DifNode {
        while(self.next_node) |next_node| {
            var to_check = next_node.get();

            // Traverse tree
            if(to_check.first_child) |*child| {
                self.next_node = child;
            } else if (to_check.next_sibling) |*sibling| {
                self.next_node = sibling;
            } else if(to_check.parent) |*parent| {
                // Any parent was already checked before traversing down, so:
                // check if parent has sibling, otherwise go further up
                var up_parent = parent;
                blk: while(true) {
                    if(up_parent.get().next_sibling) |*sibling| {
                        self.next_node = sibling;
                        break :blk;
                    } else if(up_parent.get().parent) |*up_parent_parent| {
                        up_parent = up_parent_parent;
                    } else {
                        // ingen parent, ingen sibling... The End!
                        self.next_node = null;
                        break :blk;
                    }
                }
            } else {
                // Reached end
                self.next_node = null;
            }

            // Check current
            if(to_check.node_type == self.node_type) {
                return to_check;
            }
        }

        return null;
    }
};

test "DifTraverser" {
    var node_pool = ial.IndexedArrayList(DifNode).init(std.testing.allocator);
    defer node_pool.deinit();

    var dif_root = try bufToDif(&node_pool, 
    \\node Comp;
    \\edge uses;
    \\node Lib;
    \\edge owns;
    \\myComp: Comp;
    \\group mygroup { node InGroupNode; }
    \\myLib: Lib;
    \\myComp uses myLib;
    \\node Framework;
    , "test");

    var trav = DifTraverser.init(&dif_root, DifNodeType.Node);

    try testing.expectEqual(DifNodeType.Node, trav.next().?.node_type);
    try testing.expectEqual(DifNodeType.Node, trav.next().?.node_type);
    try testing.expectEqualStrings("InGroupNode", trav.next().?.name.?);
    try testing.expectEqualStrings("Framework", trav.next().?.name.?);
    try testing.expect(trav.next() == null);
}
