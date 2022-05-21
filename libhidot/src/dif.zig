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

const initBoundedArray = utils.initBoundedArray;

const ParseError = error{ UnexpectedToken, InvalidValue };

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
    parent: ?*Self = null,
    first_child: ?*Self = null,
    next_sibling: ?*Self = null,
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

/// Entry-function to module. Returns reference to first top-level node in graph, given a tokenizer.
pub fn tokensToDif(comptime MaxNodes: usize, node_pool: *std.BoundedArray(DifNode, MaxNodes), tokenizer: *Tokenizer, unit_name: []const u8) !*DifNode {
    var first_i = node_pool.slice().len;

    // Create top-level node for unit
    var unit_node = node_pool.addOneAssumeCapacity();
    unit_node.* = DifNode{ .node_type = .Unit, .name = unit_name, .initial_token = null, .data = .{ .Unit = .{ .src_buf = tokenizer.buf } } };

    parseTokensRecursively(MaxNodes, node_pool, tokenizer, unit_node) catch {
        return error.ParseError;
    };

    if (node_pool.slice().len <= first_i) {
        return error.NothingFound;
    }

    return &node_pool.slice()[first_i];
}

/// Entry-function to module. Returns reference to first top-level node in graph, given a text buffer.
pub fn bufToDif(comptime MaxNodes: usize, node_pool: *std.BoundedArray(DifNode, MaxNodes), buf: []const u8, unit_name: []const u8) !*DifNode {
    var tokenizer = Tokenizer.init(buf);
    return try tokensToDif(MaxNodes, node_pool, &tokenizer, unit_name);
}

/// TODO: Implement support for a dynamicly allocatable nodepool (simply use ArrayList?)
pub fn parseTokensRecursively(comptime MaxNodes: usize, node_pool: *std.BoundedArray(DifNode, MaxNodes), tokenizer: *Tokenizer, parent: ?*DifNode) ParseError!void {
    var state: DififierState = .start;

    var prev_sibling: ?*DifNode = null;

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
                        var node = node_pool.addOneAssumeCapacity();

                        if (parent) |realparent| {
                            if (realparent.first_child == null) {
                                realparent.first_child = node;
                            }
                        }

                        // Get label
                        var initial_token = tok;
                        tok = tokenizer.nextToken();
                        if (tok.typ != .identifier) {
                            utils.parseError(tokenizer.buf, tok.start, "Expected identifier, got token type '{s}'", .{@tagName(tok.typ)});
                            return error.UnexpectedToken;
                        }

                        node.* = switch (initial_token.typ) {
                            .keyword_edge => DifNode{ .node_type = .Edge, .parent=parent, .name = tok.slice, .initial_token = initial_token, .data = .{ .Edge = .{} } },
                            .keyword_node => DifNode{ .node_type = .Node, .parent=parent, .name = tok.slice, .initial_token = initial_token, .data = .{ .Node = .{} } },
                            .keyword_group => DifNode{ .node_type = .Group, .parent=parent, .name = tok.slice, .initial_token = initial_token, .data = .{ .Group = .{} } },
                            .keyword_layer => DifNode{ .node_type = .Layer, .parent=parent, .name = tok.slice, .initial_token = initial_token, .data = .{ .Layer = .{} } },
                            else => unreachable, // as long as this set of cases matches the ones leading to this branch
                        };

                        if (prev_sibling) |prev| {
                            prev.next_sibling = node;
                        }
                        prev_sibling = node;

                        tok = tokenizer.nextToken();
                        switch (tok.typ) {
                            .eos => {},
                            .brace_start => {
                                // Recurse
                                try parseTokensRecursively(MaxNodes, node_pool, tokenizer, node);
                            },
                            else => {
                                utils.parseError(tokenizer.buf, tok.start, "Unexpected token type '{s}', expected {{ or ;", .{@tagName(tok.typ)});
                                return error.UnexpectedToken;
                            },
                        }
                        state = .start;
                    },
                    .include => {
                        var node = node_pool.addOneAssumeCapacity();

                        node.* = DifNode{
                            .node_type = .Include,
                            .parent=parent,
                            .name = tok.slice[1..],
                            .initial_token = tok,
                            .data = .{
                                .Include = .{},
                            },
                        };

                        if (parent) |realparent| {
                            if (realparent.first_child == null) {
                                realparent.first_child = node;
                            }
                        }

                        if (prev_sibling) |prev| {
                            prev.next_sibling = node;
                        }
                        prev_sibling = node;
                    },
                    else => {
                        utils.parseError(tokenizer.buf, tok.start, "Unexpected token type '{s}'", .{@tagName(tok.typ)});
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

                var node = node_pool.addOneAssumeCapacity();

                if (parent) |realparent| {
                    if (realparent.first_child == null) {
                        realparent.first_child = node;
                    }
                }

                switch (token2.typ) {
                    .equal => {
                        // key/value
                        node.* = DifNode{
                            .node_type = .Value,
                            .parent=parent,
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
                        node.* = DifNode{ .node_type = .Instantiation, .parent=parent, .name = token1.slice, .initial_token = token1, .data = .{
                            .Instantiation = .{
                                .target = token3.slice,
                            },
                        } };
                    },
                    .identifier => {
                        // relationship
                        node.* = DifNode{
                            .node_type = .Relationship,
                            .parent=parent,
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
                        utils.parseError(tokenizer.buf, token2.start, "Unexpected token type '{s}', expected =, : or an identifier", .{@tagName(token2.typ)});
                        return error.UnexpectedToken;
                    }, // invalid
                }

                if (prev_sibling) |prev| {
                    prev.next_sibling = node;
                }
                prev_sibling = node;

                var token4 = tokenizer.nextToken();

                switch (token4.typ) {
                    // .brace_end,
                    .eos => {},
                    .brace_start => {
                        try parseTokensRecursively(MaxNodes, node_pool, tokenizer, node);
                    },
                    else => {
                        utils.parseError(tokenizer.buf, token4.start, "Unexpected token type '{s}', expected ; or {{", .{@tagName(token4.typ)});
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
        var nodePool = initBoundedArray(DifNode, 1024);
        var root_a = try bufToDif(1024, &nodePool,
            \\@myfile.hidot
        , "test");

        try testing.expectEqual(DifNodeType.Include, root_a.first_child.?.node_type);
        try testing.expectEqualStrings("myfile.hidot", root_a.first_child.?.name.?);
    }

    {
        var nodePool = initBoundedArray(DifNode, 1024);
        var root_a = try bufToDif(1024, &nodePool,
            \\@myfile.hidot
            \\node Node;
        , "test");

        try testing.expectEqual(DifNodeType.Include, root_a.first_child.?.node_type);
        try testing.expectEqualStrings("myfile.hidot", root_a.first_child.?.name.?);
        try testing.expectEqual(DifNodeType.Node, root_a.first_child.?.next_sibling.?.node_type);
    }
}

/// Join two dif-graphs: adds second to end of first
/// TODO: This is in preparation for handling includes. Currently not in use.
pub fn join(base_root: *DifNode, to_join: *DifNode) void {
    var current = base_root;

    // Find last sibling
    while (true) {
        if (current.next_sibling) |next| {
            current = next;
        } else {
            break;
        }
    }

    // join to_join as as new sibling
    current.next_sibling = to_join;
}

test "join" {
    var nodePool = initBoundedArray(DifNode, 1024);
    var root_a = try bufToDif(1024, &nodePool,
        \\node Component;
        \\edge owns;
    , "test");
    try testing.expectEqual(nodePool.slice().len, 3);
    try testing.expectEqualStrings("owns", nodePool.slice()[2].name.?);

    var root_b = try bufToDif(1024, &nodePool,
        \\compA: Component;
        \\compB: Component;
        \\compA owns compB;
    , "test");

    join(root_a, root_b);

    try testing.expectEqual(nodePool.slice().len, 7);
    try testing.expectEqualStrings("compA", nodePool.slice()[6].name.?);
    try testing.expectEqual(DifNodeType.Relationship, nodePool.slice()[6].node_type);
}

// test/debug
pub fn dumpDifAst(node: *DifNode, level: u8) void {
    var i: usize = 0;
    while (i < level) : (i += 1) debug("  ", .{});
    debug("{s}: {s}\n", .{ @tagName(node.node_type), node.name });

    if (node.first_child) |child| {
        dumpDifAst(child, level + 1);
    }

    if (node.next_sibling) |next| {
        dumpDifAst(next, level);
    }
}

// test/debug
fn parseAndDump(buf: []const u8) void {
    tokenizerDump(buf);
    var tokenizer = Tokenizer.init(buf[0..]);
    var nodePool = initBoundedArray(DifNode, 1024);

    parseTokensRecursively(1024, &nodePool, &tokenizer, null) catch {
        debug("Got error parsing\n", .{});
    };
    dumpDifAst(&nodePool.slice()[0], 0);
}

/// Traverse through DifNode-tree as identified by node. For all nodes matching node_type: add to result_buf.
/// Will fail with .TooManyMatches if num matches exceeds result_buf.len
pub fn findAllNodesOfType(result_buf: []*DifNode, node: *DifNode, node_type: DifNodeType) error{TooManyMatches}![]*DifNode {
    var current = node;

    var next_idx: usize = 0;

    while (true) {
        // Got match?
        if (current.node_type == node_type) {
            if (next_idx >= result_buf.len) return error.TooManyMatches;

            result_buf[next_idx] = current;
            next_idx += 1;
        }

        // Recurse into children sets
        if (current.first_child) |child| {
            next_idx += (try findAllNodesOfType(result_buf[next_idx..], child, node_type)).len;
        }

        // Iterate the sibling set
        if (current.next_sibling) |next| {
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
        var node_pool = initBoundedArray(DifNode, 16);
        var root_a = try bufToDif(16, &node_pool,
            \\node Component;
            \\edge owns;
            \\edge uses;
        , "test");

        var result_buf: [16]*DifNode = undefined;

        try testing.expectEqual((try findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Node)).len, 1);
        try testing.expectEqual((try findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Edge)).len, 2);
    }

    // Advanced case: siblings and children
    {
        var node_pool = initBoundedArray(DifNode, 16);
        var root_a = try bufToDif(16, &node_pool,
            \\edge woop;
            \\group mygroup {
            \\  edge owns;
            \\  node Component;
            \\  node Lib;
            \\}
        , "test");

        var result_buf: [16]*DifNode = undefined;

        try testing.expectEqual((try findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Edge)).len, 2);
        try testing.expectEqual((try findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Node)).len, 2);
    }
}

test "findAllNodesOfType fails with error.TooManyMatches if buffer too small" {
    var node_pool = initBoundedArray(DifNode, 16);
    var root_a = try bufToDif(16, &node_pool,
        \\node Component;
    , "test");

    var result_buf: [0]*DifNode = undefined;

    try testing.expectError(error.TooManyMatches, findAllNodesOfType(result_buf[0..], root_a, DifNodeType.Node));
}

// Att! This will require .parent on DifNode to allow for simple iteration
// const DifTraverser = struct {
//     const Self = @This();

//     var current: *DifNode;
//     var node_type: DifNodeType;

//     pub fn init(root: *DifNode, node_type: DifNodeType) Self {
//         return Self {
//             .current = root,
//             .node_type = node_type
//         };
//     }

//     pub fn next(self: *Self) ?*DifNode {

//     }
// };
