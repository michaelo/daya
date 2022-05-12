/// Module responsible for parsing tokens to the Diagrammer Internal Format
const std = @import("std");
const utils = @import("utils.zig");
// const mod_tokenizer = @import("tokenizer.zig");
const Token = @import("tokenizer.zig").Token;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const tokenizerDump = @import("tokenizer.zig").dump;
const assert = std.debug.assert;
const debug = std.debug.print;
const testing = std.testing;

const initBoundedArray = utils.initBoundedArray;

const ParseError = error {
    UnexpectedToken
};
// test

/// ...
pub const NodeDefinition = struct {
    name: []const u8,
    label: ?[]const u8 = null,
    shape: ?NodeShape = .box,
    // TODO: Add more style-stuff
    bg_color: ?[]const u8 = null,
    fg_color: ?[]const u8 = null,
};

pub const EdgeDefinition = struct {
    name: []const u8,
    label: ?[]const u8 = null,
    edge_style: ?EdgeStyle = EdgeStyle.solid,
    source_symbol: EdgeEndStyle = EdgeEndStyle.none,
    source_label: ?[]const u8 = null,
    target_symbol: EdgeEndStyle = EdgeEndStyle.arrow_open,
    target_label: ?[]const u8 = null,
};

pub const Relationship = struct {
    // TBD: This is currently pointers, but could just as well be idx to the respective arrays. Benchmark later on.
    //source: *NodeInstance, // Necessary? Or simple store them at the source-NodeInstance and point out?
    target: *NodeInstance,
    edge: *EdgeDefinition,
};

pub const NodeInstance = struct {
    type: *const NodeDefinition,
    name: []const u8,
    // label: ?[]const u8 = null,
    relationships: std.BoundedArray(Relationship, 64) = initBoundedArray(Relationship, 64),
};

/// Diagrammer Internal Format / Representation
pub const Dif = struct {
    // Definitions / types
    nodeDefinitions: std.BoundedArray(NodeDefinition, 64) = initBoundedArray(NodeDefinition, 64),
    edgeDefinitions: std.BoundedArray(EdgeDefinition, 64) = initBoundedArray(EdgeDefinition, 64),

    // The actual nodes and edges
    nodeInstance: std.BoundedArray(NodeInstance, 256) = initBoundedArray(NodeInstance, 256),
};

pub const Color = struct {
    r: f16,
    g: f16,
    b: f16,
    a: f16,

    fn hexToFloat(color: []const u8) f16 {
        assert(color.len == 2);
        var buf: [1]u8 = undefined;
        _ = std.fmt.hexToBytes(buf[0..], color) catch 0;
        return @intToFloat(f16, buf[0]) / 255;
    }

    pub fn fromHexstring(color: []const u8) Color {
        assert(color.len == 7 or color.len == 9);
        // const
        if (color.len == 7) {
            return .{
                .r = hexToFloat(color[1..3]),
                .g = hexToFloat(color[3..5]),
                .b = hexToFloat(color[5..7]),
                .a = 1.0,
            };
        } else {
            return .{
                .r = hexToFloat(color[1..3]),
                .g = hexToFloat(color[3..5]),
                .b = hexToFloat(color[5..7]),
                .a = hexToFloat(color[7..9]),
            };
        }
    }

    pub fn write(_: *Color, writer: anytype) void {
        writer.print("#{s}{s}{s}", .{ "FF", "00", "00" }) catch unreachable;
    }
};

test "Color.fromHexstring" {
    var c1 = Color.fromHexstring("#FFFFFF");
    try testing.expectApproxEqAbs(@as(f16, 1.0), c1.r, 0.01);
    try testing.expectApproxEqAbs(@as(f16, 1.0), c1.g, 0.01);
    try testing.expectApproxEqAbs(@as(f16, 1.0), c1.b, 0.01);
    try testing.expectApproxEqAbs(@as(f16, 1.0), c1.a, 0.01);

    var c2 = Color.fromHexstring("#006699FF");
    try testing.expectApproxEqAbs(@as(f16, 0.0), c2.r, 0.01);
    try testing.expectApproxEqAbs(@as(f16, 0.4), c2.g, 0.01);
    try testing.expectApproxEqAbs(@as(f16, 0.6), c2.b, 0.01);
    try testing.expectApproxEqAbs(@as(f16, 1.0), c2.a, 0.01);
}

// General strategy
// For text: We start with simply storing slices of the input-data in the Dif
// If we later find we need to preprocess something, we'll reconsider and add dedicated storage
// TODO: Store the string for simple passthrough for dot?
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

// TODO: Store the string for simple passthrough for dot?
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

// Parse strategy:
// Can create a variant of the tokanizer, but working on the tokens. Then have a struct/union based on a Type-enum (Definition (node, edge), Instantiation (MyObj: SomeNode), Property (key:value), Relation (<nodeinstance> <edgetype> <nodeinstance>)
// Can be run nested as well?

/// Take the tokenized input and parse/convert it to the internal format
/// We don't need/use a full AST (in the PL-form), but we need to parse to an internal format we can work with
/// Get the following complete block of tokens as identified by braces. Assumes first entry is a brace_start

fn parseLabel(tokens: []const Token) []const u8 {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .string);
    return tokens[2].slice;
}

fn parseColor(tokens: []const Token) []const u8 {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    // assert(tokens[2].typ == .hash_color);
    // return Color.fromHexstring(tokens[2].slice);
    return tokens[2].slice;
}

// TODO: Delete/replace
fn parseNodeDefinition(name: []const u8, tokens: []const Token) !NodeDefinition {
    var result = NodeDefinition{
        .name = name,
    };

    // TODO: Iterate over tokens to find properties
    // now: label, shape
    // later: bgcolor, fgcolor, border, ...
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        // Assume identifier, colon, then some kind of value
        const token = tokens[idx];
        if (std.mem.eql(u8, token.slice, "label")) {
            result.label = parseLabel(tokens[idx .. idx + 3]);
        } else if (std.mem.eql(u8, token.slice, "shape")) {
            result.shape = try parseNodeShape(tokens[idx .. idx + 3]);
        } else if (std.mem.eql(u8, token.slice, "color")) {
            result.fg_color = parseColor(tokens[idx .. idx + 3]);
        } else if (std.mem.eql(u8, token.slice, "background")) {
            result.bg_color = parseColor(tokens[idx .. idx + 3]);
        }
    }
    return result;
}

// TODO: Delete/replace
fn parseNodeShape(tokens: []const Token) !NodeShape {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    return try NodeShape.fromString(tokens[2].slice);
}

// TODO: Delete/replace
fn parseEdgeStyle(tokens: []const Token) !EdgeStyle {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    return try EdgeStyle.fromString(tokens[2].slice);
}

// TODO: Delete/replace
fn parseEdgeEdgeEndStyle(tokens: []const Token) !EdgeEndStyle {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    return try EdgeEndStyle.fromString(tokens[2].slice);
}

// TODO: Delete/replace
fn parseEdgeDefinition(name: []const u8, tokens: []const Token) !EdgeDefinition {
    var result = EdgeDefinition{
        .name = name,
    };

    // TODO: Iterate over tokens to find properties
    // label, sourcearrow, endarrow...
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        // Not very safe - currently spins until it finds anything recognizable
        const token = tokens[idx];
        // debug("checking: {s}\n", .{token.slice});
        if (std.mem.eql(u8, token.slice, "label")) {
            result.label = parseLabel(tokens[idx .. idx + 3]);
            idx += 3;
        } else if (std.mem.eql(u8, token.slice, "style")) {
            result.edge_style = try parseEdgeStyle(tokens[idx .. idx + 3]);
            idx += 3;
        } else if (std.mem.eql(u8, token.slice, "targetSymbol")) {
            // debug("parsing targetSymbol\n", .{});
            result.target_symbol = try parseEdgeEdgeEndStyle(tokens[idx .. idx + 3]);
            idx += 3;
        } else if (std.mem.eql(u8, token.slice, "sourceSymbol")) {
            result.source_symbol = try parseEdgeEdgeEndStyle(tokens[idx .. idx + 3]);
            idx += 3;
        }
    }
    return result;
}

const DifNodeType = enum {
    Unknown,
    Edge,
    Node,
    Group,
    Layer,
    Layout,
    Instantiation,
    Relationship,
    Parameter, // key=value
    Value,
};

const DifNode = struct {
    const Self = @This();

    // // Common fields
    node_type: DifNodeType,
    first_child: ?*Self = null,
    parent: ?*Self = null,
    next_sibling: ?*Self = null,
    initial_token: ?Token = null, // Reference back to source
    name: ?[]const u8 = null,

    data: union(DifNodeType) {
        Edge: struct {},
        Node: struct {},
        Group: struct {},
        Layout: struct {},
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
        Unknown: struct {},
    },
};

const DififierState = enum {
    start,
    kwnode,
    kwedge,
    data, // To be used by any type supporting {}-sets
    kwgroup,
    kwlayout,
    kwlayer,
    definition, // Common type for any non-keyword-definition
};

/// Entry-function to module. Returns reference to first top-level node in graph
/// TODO: Implement support for a dynamicly allocatable nodepool
pub fn tokensToDif(comptime MaxNodes: usize, nodePool: *std.BoundedArray(DifNode, MaxNodes), tokenizer: *Tokenizer) !*DifNode {
    parseTokensRecursively(MaxNodes, nodePool, tokenizer, null) catch {
        return error.ParseError;
    };

    if(nodePool.slice().len < 1) {
        return error.NothingFound;
    }

    return &nodePool.slice()[0];
}

/// TODO: Experimental.
pub fn parseTokensRecursively(comptime MaxNodes: usize, nodePool: *std.BoundedArray(DifNode, MaxNodes), tokenizer: *Tokenizer, parent: ?*DifNode) ParseError!void {
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
                        var node = nodePool.addOneAssumeCapacity();

                        // TODO: Should most likely be refactored
                        if(parent) |realparent| {
                            if(realparent.first_child == null) {
                                realparent.first_child = node;
                            }
                        }

                        // TBD: Split to different states?

                        // Get label
                        var initial_token = tok;
                        tok = tokenizer.nextToken();
                        if(tok.typ != .identifier) {
                            utils.parseError(tokenizer.buf, tok.start, "Expected identifier, got token type '{s}'", .{@tagName(tok.typ)});
                            return error.UnexpectedToken;
                        }

                        node.* =  switch(initial_token.typ) {
                            .keyword_edge => DifNode{
                                .node_type = .Edge,
                                .parent = parent,
                                .name = tok.slice,
                                .initial_token = initial_token,
                                .data = .{ .Edge = .{} } },
                            .keyword_node => DifNode{
                                .node_type = .Node,
                                .parent = parent,
                                .name = tok.slice,
                                .initial_token = initial_token,
                                .data = .{ .Node = .{} } },
                            .keyword_group => DifNode{
                                .node_type = .Group,
                                .parent = parent,
                                .name = tok.slice,
                                .initial_token = initial_token,
                                .data = .{ .Group = .{} } },
                            .keyword_layer => DifNode{
                                .node_type = .Layer,
                                .parent = parent,
                                .name = tok.slice,
                                .initial_token = initial_token,
                                .data = .{ .Layer = .{} } },
                            else => unreachable // as long as this set of cases matches the ones leading to this branch
                        };

                        if(prev_sibling) |prev| {
                            prev.next_sibling = node;
                        }
                        prev_sibling = node;

                        tok = tokenizer.nextToken();
                        switch (tok.typ) {
                            .eos => {},
                            .brace_start => {
                                // Recurse
                                try parseTokensRecursively(MaxNodes, nodePool, tokenizer, node);
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
                assert(token1.typ == .identifier);
                var token2 = tokenizer.nextToken();
                var token3 = tokenizer.nextToken();

                var node = nodePool.addOneAssumeCapacity();

                // TODO: Should most likely be refactored
                if(parent) |realparent| {
                    if(realparent.first_child == null) {
                        realparent.first_child = node;
                    }
                }

                switch(token2.typ) {
                    .equal => {
                        // key/value
                        node.* = DifNode {
                            .node_type = .Value,
                            .name = token1.slice,
                            .initial_token = token1,
                            .parent = parent,
                            .data = .{
                                .Value = .{
                                    // TODO: Currently assuming single-token value for simplicity. This will likely not be the case for e.g. numbers with units
                                    .value = token3.slice,
                                },
                            }
                        };
                    },
                    .colon => {
                        // instantiation
                        node.* = DifNode {
                            .node_type = .Instantiation,
                            .name = token1.slice,
                            .initial_token = token1,
                            .parent = parent,
                            .data = .{
                                .Instantiation = .{
                                    .target = token3.slice,
                                },
                            }
                        };
                    },
                    .identifier => {
                        // relationship
                        node.* = DifNode {
                            .node_type = .Relationship,
                            .name = token1.slice,
                            .initial_token = token1,
                            .parent = parent,
                            .data = .{
                                .Relationship = .{
                                    .edge = token2.slice,
                                    .target = token3.slice,
                                },
                            }
                        };
                    },
                    else => {
                        utils.parseError(tokenizer.buf, token2.start, "Unexpected token type '{s}', expected =, : or an identifier", .{@tagName(token2.typ)});
                        return error.UnexpectedToken;
                    } // invalid
                }

                // TODO: Verify correctness
                if(prev_sibling) |prev| {
                    prev.next_sibling = node;
                }
                prev_sibling = node;

                var token4 = tokenizer.nextToken();
                
                switch(token4.typ) {
                    // TBD: treat } also as an eos?
                    // .brace_end
                    .eos => {
                    },
                    .brace_start => {
                        try parseTokensRecursively(MaxNodes, nodePool, tokenizer, node);
                    },
                    else => {
                        utils.parseError(tokenizer.buf, token4.start, "Unexpected token type '{s}', expected ; or {{", .{@tagName(token4.typ)});
                        return error.UnexpectedToken;
                    } // invalid
                }
                state = .start;
                tok = token4;
            },
            else => {
                
            }
        }
    }
}


// test/debug
fn dumpDifAst(node: *DifNode, level: u8) void {
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

test "parseTokensRecursively" {
    {
        const buf = "edge owns;";
        parseAndDump(buf[0..]);
    }

    {
        const buf =
            \\edge owns_with_label { label="my label"; }
            \\edge owns_with_empty_set { }
        ;
        parseAndDump(buf[0..]);
    }

    {
        const buf =
            \\node Component { label="my label"; }
        ;
        parseAndDump(buf[0..]);
    }


    {
        const buf =
            \\//Definitions
            \\node Component { label="<Component>"; }
            \\node Actor { label="<Actor>"; }
            \\edge uses { label="uses"; }
            \\
            \\// Groups / instantiations
            \\group Externals {
            \\  user: Actor { label="User"; };
            \\}
            \\group App {
            \\  label="My app";
            \\  group Interfaces {
            \\    cli: Component;
            \\  }
            \\
            \\  group Internals {
            \\    core: Component;
            \\  }
            \\}
            \\layer Main {
            \\  user uses cli;
            \\  cli uses core;
            \\}
            \\
        ;
        parseAndDump(buf[0..]);
    }

    {
        const buf =
            \\node Module {
            \\  label=unquotedvalue;
            \\//  width=300px;
            \\}
            \\
            \\edge uses;
            \\edge contains {
            \\  label="contains for realz";
            \\  color="black";
            \\}
            \\edge owns;
            \\
            \\group Components {
            \\    
            \\    group LibComponents {
            \\        LibCompA: Component;
            \\        LibCompB: Component;
            \\    };
            \\    
            \\    group ApiComponents {
            \\        ApiCompA: Component;
            \\        ApiCompB: Component;
            \\    };
            \\
            \\    ApiComponents uses LibComponents;
            \\
            \\    ApiCompA uses LibCompA;
            \\    ApiCompA uses LibCompB;
            \\};
            \\
        ;
        parseAndDump(buf[0..]);
    }

    // TODO: Start testing vertical slices of entire functionality  with new structure
    // Test: A node type, an edge type, two instantiations and a relationship between them
    // TODO: Determine the valid attributes for nodes and edges. Determine how overrides shall be done. E.g concats of labels vs replacements.
}

const DifNodeMap = std.StringHashMap(*DifNode);

test "Map" {
    var map = std.StringHashMap([]const u8).init(testing.allocator);
    defer map.deinit();
    try map.put("key", "value");
    debug("key: {s}\n", .{map.get("key")});
    debug("key2: {s}\n", .{map.get("key2")});
}

fn findAllEdgesAndNodes(node: *DifNode, nodeMap: *DifNodeMap, edgeMap: *DifNodeMap) error{OutOfMemory}!void {
    switch(node.node_type) {
        .Node => {
            try nodeMap.put(node.name.?, node);
        },
        .Edge => {
            try edgeMap.put(node.name.?, node);
        },
        else => {}
    }
    
    if (node.first_child) |child| {
        try findAllEdgesAndNodes(child, nodeMap, edgeMap);
    }

    if (node.next_sibling) |next| {
        try findAllEdgesAndNodes(next, nodeMap, edgeMap);
    }
}

// fn renderNode() void {
//     // check node and immediate children
// }

const RenderError = error {
    NoSuchNode,
    NoSuchEdge,
    OutOfMemory
};

// TODO: Extract the relevant, valid fields from base-node to use in instantiations
// fn getNodeFields(instance: *DifNode, label: ?*[]const u8, fgcolor: ?*[]const u8) void {

// }
// 

fn renderInstantiation(instance: *DifNode, nodeMap: *DifNodeMap) RenderError!void {
    const w = debug;
    var label = instance.name;
    var nodeName = instance.data.Instantiation.target;

    // label: default name of instance + label of node type
    //        if children: look for label there and replace instance.name if found

    var node = nodeMap.get(nodeName) orelse {
        w("ERROR: No node {s} found\n", .{nodeName});
        return RenderError.NoSuchNode;
    };
    _ = node;

    // Extract relevant fields from immediate children: label, fgcolor, bgcolor, edge, shape
    // TODO: Fault on detected grandchildren? No, this should be solved elsewhere...

    // Extract fields from node
    
    w("    \"{s}\"[label=\"{s}\"];\n", .{instance.name, label});
    
    // compose a node by instance name, instance type(node), + immediate children-values, if any.

}

// fn renderEdge() void {
//     // Takes both edge-ref and (optional) children-ref
// }

fn renderRelationship(instance: *DifNode, nodeMap: *DifNodeMap, edgeMap: *DifNodeMap) RenderError!void {
    _ = instance;
    _ = nodeMap;
    _ = edgeMap;
}

/// Recursive?
fn renderGeneration(instance: *DifNode, nodeMap: *DifNodeMap, edgeMap: *DifNodeMap) RenderError!void {
    const w = debug;

    // TODO: Are there any dot-requirements re ordering? E.g. can we e..g define a relationship, then describe the nodes?
    switch(instance.node_type) {
        .Instantiation => {
            try renderInstantiation(instance, nodeMap);
        },
        .Relationship => {
            try renderRelationship(instance, nodeMap, edgeMap);
        },
        .Group => {
            w("subgraph cluster_{s} {{\n", .{instance.name});
            if(instance.first_child) |child| {
                try renderGeneration(child, nodeMap, edgeMap);
            }
            w("}}\n", .{});
        },
        else => {}
    }

    // if (node.first_child) |child| {
    //     try findAllEdgesAndNodes(child, nodeMap, edgeMap);
    // }

    if (instance.next_sibling) |next| {
        try renderGeneration(next, nodeMap, edgeMap);
    }
}

fn experimentalDotWriter(rootNode: *DifNode) !void {
    const w = debug;
    _ = rootNode;

    // TODO: Currently no scoping of node-types
    var nodeMap = DifNodeMap.init(testing.allocator);
    defer nodeMap.deinit();

    var edgeMap = DifNodeMap.init(testing.allocator);
    defer edgeMap.deinit();

    try findAllEdgesAndNodes(rootNode, &nodeMap, &edgeMap);

    // TODO: Need to find all nodes (TBD: scoped by groups?)
    // TODO: Need to find all edges (global)
    // Then, instantiate by group
    // Relationships can be defined at last? At least if there's no scoping-concerns for DOT
    // w("hello: {s}!\n", .{rootNode.name});
    w("strict digraph {{\n", .{});

    // TODO: Implement "include"-support


    // var nodeI = nodeMap.iterator();
    // while(nodeI.next()) |node| {
    //     w("node: {s}\n", .{node.key_ptr.*});
    // }
    try renderGeneration(rootNode, &nodeMap, &edgeMap);
    
    // remove, edges are looked up on demand: TODO: Generate predefined strings? or what about when overridden?
    // var edgeI = edgeMap.iterator();
    // while(edgeI.next()) |edge| {
    //     w("edge: {s}\n", .{edge.key_ptr.*});
    // }


    w("}}\n", .{});
}

test "dotifier exploration" {
    // Exploration
    const buf = 
        \\node Component;
        \\edge owns;
        \\group Silly {
        \\compA: Component;
        \\compB: Component;
        \\}
        \\compA owns compB;
    ;
    var tokenizer = Tokenizer.init(buf[0..]);
    var nodePool = initBoundedArray(DifNode, 1024);
    var rootNode = try tokensToDif(1024, &nodePool, &tokenizer);
    try experimentalDotWriter(rootNode);
}
