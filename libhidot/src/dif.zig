/// Module responsible for parsing tokens to the Diagrammer Internal Format
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
    Edge,
    Node,
    Group,
    Layer,
    Instantiation,
    Relationship,
    Parameter, // key=value
    Value,
};

pub const DifNode = struct {
    const Self = @This();

    // // Common fields
    node_type: DifNodeType,
    first_child: ?*Self = null,
    next_sibling: ?*Self = null,
    initial_token: ?Token = null, // Reference back to source
    name: ?[]const u8 = null,
    // TODO: reference to source buffer (and source file name?), as nodes may origin from separate files.

    data: union(DifNodeType) {
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
        Parameter: struct {},
        Value: struct {
            value: []const u8,
        },
    },
};

// General strategy
// For text: We start with simply storing slices of the input-data in the Dif
// If we later find we need to preprocess something, we'll reconsider and add dedicated storage
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
    data, // To be used by any type supporting {}-sets
    definition, // Common type for any non-keyword-definition
};

/// Entry-function to module. Returns reference to first top-level node in graph, given a tokenizer.
pub fn tokensToDif(comptime MaxNodes: usize, nodePool: *std.BoundedArray(DifNode, MaxNodes), tokenizer: *Tokenizer) !*DifNode {
    var first_i = nodePool.slice().len;
    parseTokensRecursively(MaxNodes, nodePool, tokenizer, null) catch {
        return error.ParseError;
    };

    if (nodePool.slice().len <= first_i) {
        return error.NothingFound;
    }

    return &nodePool.slice()[first_i];
}

/// Entry-function to module. Returns reference to first top-level node in graph, given a text buffer.
pub fn bufToDif(comptime MaxNodes: usize, node_pool: *std.BoundedArray(DifNode, MaxNodes), buf: []const u8) !*DifNode {
    var tokenizer = Tokenizer.init(buf);
    return try tokensToDif(MaxNodes, node_pool, &tokenizer);
}

/// TODO: Implement support for a dynamicly allocatable nodepool
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
                            .keyword_edge => DifNode{ .node_type = .Edge, .name = tok.slice, .initial_token = initial_token, .data = .{ .Edge = .{} } },
                            .keyword_node => DifNode{ .node_type = .Node, .name = tok.slice, .initial_token = initial_token, .data = .{ .Node = .{} } },
                            .keyword_group => DifNode{ .node_type = .Group, .name = tok.slice, .initial_token = initial_token, .data = .{ .Group = .{} } },
                            .keyword_layer => DifNode{ .node_type = .Layer, .name = tok.slice, .initial_token = initial_token, .data = .{ .Layer = .{} } },
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
                        node.* = DifNode{ .node_type = .Instantiation, .name = token1.slice, .initial_token = token1, .data = .{
                            .Instantiation = .{
                                .target = token3.slice,
                            },
                        } };
                    },
                    .identifier => {
                        // relationship
                        node.* = DifNode{
                            .node_type = .Relationship,
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

/// Join two dif-graphs: adds second to end of first
/// TODO: This is in preparation for handling includes. Currently not in use.
fn join(base_root: *DifNode, to_join: *DifNode) void {
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
    );
    try testing.expectEqual(nodePool.slice().len, 2);
    try testing.expectEqualStrings("owns", nodePool.slice()[1].name.?);

    var root_b = try bufToDif(1024, &nodePool,
        \\compA: Component;
        \\compB: Component;
        \\compA owns compB;
    );

    join(root_a, root_b);

    try testing.expectEqual(nodePool.slice().len, 5);
    try testing.expectEqualStrings("compA", nodePool.slice()[4].name.?);
    try testing.expectEqual(DifNodeType.Relationship, nodePool.slice()[4].node_type);
}

// test/debug
pub fn dumpDifAst(node: *DifNode, level: u8) void {
    debug("{d} {s}: {s}\n", .{ level, @tagName(node.node_type), node.name });
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
