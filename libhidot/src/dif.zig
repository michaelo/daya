/// Module responsible for parsing tokens to the Diagrammer Internal Format

const std = @import("std");
const utils = @import("utils.zig");
const Token = @import("tokenizer.zig").Token;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const TokenType = @import("tokenizer.zig").TokenType;
const tokenizerDump = @import("tokenizer.zig").dump;
const assert = std.debug.assert;
const debug = std.debug.print;
const testing = std.testing;

const initBoundedArray = utils.initBoundedArray;
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
        return @intToFloat(f16, buf[0])/255;
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
        writer.print("#{s}{s}{s}", .{"FF", "00", "00"}) catch unreachable;
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
        return std.meta.stringToEnum(NodeShape, name)  orelse error.InvalidValue;
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
fn getBlock(
    tokens: []const Token,
) ![]const Token {
    var brace_depth: usize = 0;
    return for (tokens) |token, i| {
        switch (token.typ) {
            .brace_start => brace_depth += 1,
            .brace_end => brace_depth -= 1,
            else => {},
        }
        // debug("  now at: {d} {d}\n",.{idx, i});
        if (brace_depth == 0) break tokens[0..i];
    } else {
        // Found no matching brace_end?
        debug("ERROR: No closing brace found\n", .{});
        return error.MissingClosingBrace;
    };
}

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
        if(std.mem.eql(u8, token.slice, "label")) {
            result.label = parseLabel(tokens[idx..idx+3]);
        } else if(std.mem.eql(u8, token.slice, "shape")) {
            result.shape = try parseNodeShape(tokens[idx..idx+3]);
        } else if(std.mem.eql(u8, token.slice, "color")) {
            result.fg_color = parseColor(tokens[idx..idx+3]);
        } else if(std.mem.eql(u8, token.slice, "background")) {
            result.bg_color = parseColor(tokens[idx..idx+3]);
        }
    }
    return result;
}

fn parseNodeShape(tokens: []const Token) !NodeShape {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    return try NodeShape.fromString(tokens[2].slice);
}

fn parseEdgeStyle(tokens: []const Token) !EdgeStyle {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    return try EdgeStyle.fromString(tokens[2].slice);
}

fn parseEdgeEdgeEndStyle(tokens: []const Token) !EdgeEndStyle {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    return try EdgeEndStyle.fromString(tokens[2].slice);
}


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
        if(std.mem.eql(u8, token.slice, "label")) {
            result.label = parseLabel(tokens[idx..idx+3]);
            idx += 3;
        } else if(std.mem.eql(u8, token.slice, "style")) {
            result.edge_style = try parseEdgeStyle(tokens[idx..idx+3]);
            idx += 3;
        } else if(std.mem.eql(u8, token.slice, "targetSymbol")) {
            // debug("parsing targetSymbol\n", .{});
            result.target_symbol = try parseEdgeEdgeEndStyle(tokens[idx..idx+3]);
            idx += 3;
        } else if(std.mem.eql(u8, token.slice, "sourceSymbol")) {
            result.source_symbol = try parseEdgeEdgeEndStyle(tokens[idx..idx+3]);
            idx += 3;
        }
    }
    return result;
}

fn testForSequence(tokens: []const Token, sequence: []const TokenType) bool {
    if(tokens.len < sequence.len) return false;
    for(sequence) |sequence_type, i| {
        if(tokens[i].typ != sequence_type) return false;
    }

    return true;
}


pub fn tokensToDif(tokens: []const Token, out_dif: *Dif) !void {
    _ = tokens;
    _ = out_dif;
    // Find all 'node'-blocks and add to out_dif.nodeDefinitions
    // Find all 'edge'-blocks and add to out_dif.edgeDefinitions
    // Find all node-instances (entries in top-level matching <identifier><colon><identifier>) and add to nodeinstances
    // Find all entries matching format: <identifier> <identifier> <identifier> <nl> where first and last identifier is nodeInstance, and the middle is edgeInstance
    var idx: usize = 0;
    while (idx < tokens.len) : (idx += 1) {
        const token = tokens[idx];
        switch (token.typ) {
            .eof => {
                // debug("End of file\n", .{});
            },
            .keyword_node => {
                // debug("Found node: {s}\n", .{tokens[idx + 1].slice});
                idx += 1; // Get to the name
                const node_name = tokens[idx].slice;
                idx += 1; // Get to the {
                assert(tokens[idx].typ == .brace_start); // TODO: better error
                const block = try getBlock(tokens[idx..]);
                try out_dif.nodeDefinitions.append(try parseNodeDefinition(node_name, block));
                idx += block.len;
            },
            .keyword_edge => {
                // debug("Found edge: {s}\n", .{tokens[idx + 1].slice});
                idx += 1;
                const edge_name = tokens[idx].slice;
                idx += 1; // Get to the {
                assert(tokens[idx].typ == .brace_start); // TODO: better error
                const block = try getBlock(tokens[idx..]);
                try out_dif.edgeDefinitions.append(try parseEdgeDefinition(edge_name, block));
                idx += block.len;
            },
            .nl => {
                // debug("Testing sequence: {s} {s} {s} {s} {s}\n", .{tokens[idx].typ, tokens[idx+1].typ, tokens[idx+2].typ, tokens[idx+3].typ, tokens[idx+4].typ});
                if(testForSequence(tokens[idx..], &[_]TokenType{.nl, .identifier, .colon, .identifier, .nl})) {
                    // debug("Found sequence\n", .{});
                    const nodeId = tokens[idx+1].slice;
                    const nodeDefinitionId = tokens[idx+3].slice;

                    // Store
                    // Check if nodeDefinitionId exists, fail if not
                    // 
                    var nodeDefinition = for(out_dif.nodeDefinitions.constSlice()) |*item| {
                        if(std.mem.eql(u8, item.name, nodeDefinitionId)) {
                            break item;
                        }
                    } else {
                        debug("Could not finde any NodeDefinition '{s}'\n", .{nodeDefinitionId});
                        return error.NoSuchNodeDefinition;
                    };

                    try out_dif.nodeInstance.append(NodeInstance{
                        .type = nodeDefinition,
                        .name = nodeId,
                        // .relationships = undefined
                    });

                    // Proceed
                    idx += 2;
                } else if (testForSequence(tokens[idx..], &[_]TokenType{.nl, .identifier, .identifier, .identifier, .nl})) {
                    // debug("Found relationship\n", .{});
                    const srcNode = for(out_dif.nodeInstance.slice()) |*item| {
                        if(std.mem.eql(u8, item.name, tokens[idx+1].slice)) {
                            break item;
                        }
                    } else {
                        debug("Could not finde any NodeDefinition '{s}'\n", .{tokens[idx+1].slice});
                        return error.NoSuchNodeDefinition;
                    };

                    const edge = for(out_dif.edgeDefinitions.slice()) |*item| {
                        if(std.mem.eql(u8, item.name, tokens[idx+2].slice)) {
                            break item;
                        }
                    } else {
                        debug("Could not finde any EdgeDefinition '{s}'\n", .{tokens[idx+2].slice});
                        return error.NoSuchEdgeDefinition;
                    };

                    const dstNode = for(out_dif.nodeInstance.slice()) |*item| {
                        if(std.mem.eql(u8, item.name, tokens[idx+3].slice)) {
                            break item;
                        }
                    } else {
                        debug("Could not finde any NodeDefinition '{s}'\n", .{tokens[idx+3].slice});
                        return error.NoSuchNodeDefinition;
                    };

                    try srcNode.relationships.append(Relationship {
                        .target = dstNode,
                        .edge = edge,
                    });

                    idx += 3;
                }
            },
            else => {},
        }
    }

    // Naive strategy: separate pass for each step
    // Optimized strategy: parse as we go, and lazily fill up if something's out of order. Can start with requirement that defs must be top-down for simplicity, but it also enforces readability
}

const DifNodeType = enum {
    Edge,
    Node,
    Group,
    Layout,
    Instantiation,
    Relationship,
    Parameter, // key=value
    Value,
};

// const DifNodeData = union(DifNodeType) {
//     Edge: struct {

//     },
//     Node: struct {

//     },
//     Group: struct {

//     },
//     Layout: struct {

//     },
//     Instantiation: struct {

//     },
//     Relationship: struct {

//     },
//     Parameter: struct {

//     }
// };

const DifNode = struct {
    const Self = @This();
    
    // // Common fields
    node_type: DifNodeType,
    child: ?*Self = null,
    parent: ?*Self = null,
    next_sibling: ?*Self = null,
    initial_token: ?Token = null, // Reference back to source
    name: ?[]const u8 = null,
    // // TODO: Establish how to refer back to source
    // // source_start_idx: ?u8,
    // // source_slice: ?[]const u8,

    data: union(DifNodeType) {
        Edge: struct {

        },
        Node: struct {

        },
        Group: struct {

        },
        Layout: struct {

        },
        Instantiation: struct {

        },
        Relationship: struct {

        },
        Parameter: struct {

        },
        Value: struct {
            // TBD: Can also be solved as a data-field for Parameter if that's the only value-keeping type
        }
    }
};

fn expectDifNodes(nodes: []const DifNode, expected_nodes: []const DifNodeType) !void {
    
    for (expected_nodes) |expected_node, i| {
        const found_node = nodes[i];
        testing.expectEqual(expected_node, found_node.data) catch |e| {
            debug("Expected node[{d}] {s}, got {s}:\n\n", .{ i, expected_node, @TypeOf(found_node.data) });
            // debug("  ({d}-{d}): '{s}'\n", .{ found_node.start, found_node.end, buf[found_node.start..found_node.end] });
            return e;
        };
    }
}

test "expectDifNodes" {
    try expectDifNodes(&[_]DifNode{
        DifNode { .node_type = .Edge, .data = .{.Edge=.{}} },
        DifNode { .node_type = .Parameter, .data = .{.Parameter=.{}} },
    }, &[_]DifNodeType{.Edge, .Parameter});
}

// Used mid-parse
const DifNodeWIP = struct {

};


const Dififier = struct {
    const Self = @This();

    fn init(tokenizer: Tokenizer) Self {
        _ = tokenizer;
        return .{};
    }
};

// TODO: splitte opp slik at vi alltid popper token for hver iterasjon og _alt_ håndteres av parse-state?
// TODO: lag en semi-rekursiv løsning, men med felles "allokator" (BoundedArray) og tokenizer.
const DififierState = enum {
    start,
    kwnode,
    // node_w_data,
    kwedge,
    // edge_w_data,
    data, // To be used by any type supporting {}-sets
    relationship, // any statement found without initial keyword is assumed to be a relationship
    kwgroup,
    kwlayout,
    kwlayer,
    parameter,
};

fn expectToken(token: Token, tokenType: TokenType) bool {
    if(token.typ != tokenType) {
        debug("ERROR: Expected token-type {s}, got {s}: {s}\n", .{tokenType, token.typ, token.slice});
        return false;
    }
    return true;
}

test "state" {
    var buf =
        \\node Module {
        \\  label=unquotedvalue;
        \\//  width=300px;
        \\}
        \\
        \\edge uses;
        \\edge contains {
        \\  label="contains for realz";
        \\}
        \\
        \\group Components {
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
    tokenizerDump(buf);

    var tokenizer = Tokenizer.init(buf[0..]);
    var nodes = initBoundedArray(DifNode, 2048); // TODO: dynamically allocate to support arbitrary sizes of documents
    var state = DififierState.start;
    var parent_node: ?*DifNode = null;
    var current_node: *DifNode = undefined;
    
    debug("START\n", .{});
    var token: Token = undefined;
    main: while(true) {
        if(token.typ == .eof) break;

        switch(state) {
            .start => {
                token = tokenizer.nextToken();
                switch(token.typ) {
                    .keyword_edge => {
                        debug("start, found edge\n", .{});
                        state = DififierState.kwedge;
                    },

                    // .keyword_node => {

                    // },

                    // .keyword_layout => {

                    // },

                    // .keyword_layer => {

                    // },

                    // .keyword_group => {

                    // },
                    else => {}
                }
            },
            // Edge parsing
            .kwedge => {
                debug("Adding edge\n", .{});
                current_node = nodes.addOneAssumeCapacity();

                // Expect identifier
                token = tokenizer.nextToken();
                if(token.typ != .identifier) {
                    debug("FATAL: 1 Expected identifier, got: {s}\n", .{token.slice});
                    break :main;
                }

                current_node.* = DifNode{
                    .node_type = .Edge,
                    .parent = parent_node,
                    .name = token.slice,
                    .data = .{
                        .Edge = .{}
                    }
                };
        
                token = tokenizer.nextToken();
                switch(token.typ) {
                    .eos => {
                        // Store and move on
                        // Alloc new node to continue workin
                        current_node = nodes.addOneAssumeCapacity();
                        state = .start;
                    },
                    .brace_start =>  {
                        state = .data;
                    },
                    else => {
                        debug("FATAL: Expected ; or {{, got: {s}\n", .{token.slice});
                        break :main;
                    }
                }
            },
            .data => {
                parent_node = current_node;
                // debug("data: {s}\n", .{token.typ});
                token = tokenizer.nextToken();
                switch(token.typ) {
                    .identifier => {
                        state = .parameter;
                    },
                    .brace_end => {
                        // Store and move on
                        parent_node = current_node.parent; // TODO: Revise.
                        current_node = nodes.addOneAssumeCapacity();
                        state = .start;
                    },
                    else => {
                        debug("FATAL: Expected identifier or }}, got: {s} -> {s}\n", .{@tagName(token.typ), token.slice});
                        break :main;
                    }
                }
            },
            // Node parsing
            // Layout parsing
            // Layer parsing
            // Group parsing
            .parameter => {
                // Parse a key/value-set
                // current token is the identifier
                // next token shall be =
                // then we shall get the value
                if(!expectToken(token, .identifier)) {
                    break :main;
                }
                current_node.* = DifNode {
                    .node_type = .Parameter,
                    .parent = parent_node,
                    .name = token.slice,
                    .data = .{
                        .Parameter = .{}
                    }
                };
                parent_node = current_node;
                token = tokenizer.nextToken();
                if(!expectToken(token, .equal)) {
                    break :main;
                }
                token = tokenizer.nextToken();
                switch(token.typ) {
                    // must be any of the value-types
                    .identifier => {
                        current_node = nodes.addOneAssumeCapacity();
                        current_node.* = DifNode {
                            .node_type = .Value,
                            .parent = parent_node,
                            .name = token.slice,
                            .data = .{
                                .Value = .{}
                            }
                        };
                    },
                    .string => {
                        current_node = nodes.addOneAssumeCapacity();
                        current_node.* = DifNode {
                            .node_type = .Value,
                            .parent = parent_node,
                            .name = token.slice,
                            .data = .{
                                .Value = .{}
                            }
                        };
                    },
                    else => {
                        debug("FATAL: Expected value value-type, got: {s}\n", .{token.slice});
                        break :main;
                    }
                }
                token = tokenizer.nextToken();
                if(!expectToken(token, .eos)) {
                    break :main;
                }
                token = tokenizer.nextToken();
                switch(token.typ) {
                    .brace_end => {
                        state = .start;
                    },
                    .identifier => {
                        state = .data;
                    },
                    else => {
                        debug("FATAL: Expected identifier or }}, got: {s}\n", .{token.slice});
                        break :main;
                    }
                }
            },
            else => {},
        }
    }
    debug("DONE\n", .{});

    for(nodes.slice()) |node| {
        debug("parsed: {s}: {s}\n", .{node.node_type, node.name});
    }
}

test "Dififier" {
    var buf =
        \\node Module {
        \\  label=unquoted value;
        \\  width=300px;
        \\}
        \\
        \\edge uses;
        \\edge contains {
        \\  label="contains for realz";
        \\}
        \\
        \\group Components {
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

    var tokenizer = Tokenizer.init(buf[0..]);

    var nodes = initBoundedArray(DifNode, 2048); // TODO: dynamically allocate to support arbitrary sizes of documents

    var parent_node: ?*DifNode = null;

    while(true) {
        // TODO: This can't always happen since we might pre-read tokens inside cases below. Or shall we go full tokenizer-style? With states etc? Or abort fully when we get something unexpected.
        var token = tokenizer.nextToken();

        switch(token.typ) {
            .eof => break,
            .keyword_edge => {
                var node = nodes.addOneAssumeCapacity();

                // Expects next: identified (name), then either: {...} or ;
                node.* = .{
                    .node_type = .Edge,
                    .parent = parent_node,
                    .data = .{
                        .Edge = .{}
                    }
                };
                // prev_node = node;

                token = tokenizer.nextToken();
                switch(token.typ) {
                    .identifier => {
                        node.name = token.slice;
                    },
                    else => {
                        debug("FATAL: Expected identifier, got: {s}\n", .{token.slice});
                        return;
                    }
                }
                switch(token.typ) {
                    .eos => {

                    },
                    .brace_start => {
                        parent_node = node;
                    },
                    else => {
                        debug("FATAL: Expected ; or {{, got: {s}\n", .{token.slice});
                        return;
                    }
                }
                debug("got edge: {s}\n", .{tokenizer.nextToken().slice});
            },
            .identifer => {

            },
            .equal => {

            },
            // .keyword_node => {
            //     // Expects next: identified (name), then either: {...} or ;
            //     debug("got node: {s}\n", .{tokenizer.nextToken().slice});
            // },
            // .keyword_group => {
            //     // Expects next: identified (name), then {...}
            //     debug("got group: {s}\n", .{tokenizer.nextToken().slice});
            // },
            // .keyword_layer => {
            //     // Expects next: identified (name), then {...}
            //     debug("got layer: {s}\n", .{tokenizer.nextToken().slice});
            // }, 
            else => {
                debug("Unhandled token: {s}\n", .{token.slice});
            },
        }
    }

    // TODO: Process and print as tree
    for(nodes.slice()) |node| {
        debug("parsed: {s}: {s}\n", .{node.node_type, node.name});
    }
}