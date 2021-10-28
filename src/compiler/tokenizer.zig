const std = @import("std");
const testing = std.testing;
const debug = std.debug.print;
const assert = std.debug.assert;

fn keywordOridentifier(value: []const u8) TokenType {
    if (std.mem.eql(u8, value, "node")) {
        return TokenType.keyword_node;
    } else if (std.mem.eql(u8, value, "edge")) {
        return TokenType.keyword_edge;
    } else if (std.mem.eql(u8, value, "layout")) {
        return TokenType.keyword_layout;
    }

    return TokenType.identifier;
}

const TokenType = enum {
    invalid,
    eof,
    nl,
    keyword_node,
    keyword_edge,
    keyword_layout,
    identifier,
    single_line_comment,
    brace_start,
    brace_end,
    colon,
    arrow,
    numeric_literal,
    numeric_unit,
    hash_color,
    string,
};

const Token = struct {
    typ: TokenType,
    start: u64,
    end: u64,
    slice: []const u8, // Requires source buf to be available
};

const Tokenizer = struct {
    const State = enum {
        start,
        string,
        identifier,
        single_line_comment,
        dash,
        numeric_literal,
        numeric_unit,
        hash,
        f_slash,
    };

    buf: []const u8,
    pos: u64 = 0,
    // state: ParseState = .start,

    fn init(buffer: []const u8) Tokenizer {
        return Tokenizer{
            .buf = buffer,
        };
    }

    fn nextToken(self: *Tokenizer) Token {
        var result = Token{
            .typ = .eof,
            .start = self.pos,
            .end = undefined,
            .slice = undefined,
        };

        var state: State = .start;

        while (self.pos < self.buf.len) : (self.pos += 1) {
            const c = self.buf[self.pos];
            // debug("Processing '{c}' ({s})\n", .{c, state});
            switch (state) {
                .start => {
                    switch (c) {
                        '/' => {
                            state = .f_slash;
                        },
                        '#' => {
                            state = .hash;
                        },
                        'a'...'z', 'A'...'Z' => {
                            state = .identifier;
                        },
                        '0'...'9' => {
                            state = .numeric_literal;
                        },
                        '"' => {
                            state = .string;
                            result.start = self.pos+1;
                        },
                        '{' => {
                            result.typ = .brace_start;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        '}' => {
                            result.typ = .brace_end;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        ':' => { // TODO: Doesn't hit...
                            result.typ = .colon;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        // TBD: Any semantic use for newlines, or simply treat it like any space? Will then need another separator, e.g. ;
                        '\n' => {
                            result.typ = .nl
                    ;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        // Whitespace are separators
                        ' ', '\t' => {
                            result.start = self.pos + 1;
                        },
                        else => {
                            // Error

                        },
                    }
                },
                .string => {
                    switch (c) {
                        '"' => {
                            result.end = self.pos;
                            result.typ = .string;
                            self.pos += 1;
                            break;
                        },
                        else => {},
                    }
                },
                .identifier => {
                    switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9','_' => {},
                        else => {
                            result.end = self.pos; // TBD: +1?
                            result.typ = keywordOridentifier(self.buf[result.start..result.end]);
                            // self.pos+=1;
                            break;
                        },
                    }
                },
                .f_slash => {
                    switch (c) {
                        '/' => state = .single_line_comment,
                        else => {
                            // Currently unknown token
                            break;
                        },
                    }
                },
                .single_line_comment => {
                    // Spin until end of line
                    // Currently ignoring comments
                    switch (c) {
                        '\n' => break,
                        else => {},
                    }
                },
                .dash => {},
                .numeric_literal => {
                    switch (c) {
                        '0'...'9' => {},
                        // 'a'...'z' => state = .numeric_unit,
                        else => {
                            result.typ = .numeric_literal;
                            result.end = self.pos;
                            break;
                        },
                    }
                },
                .numeric_unit => {
                    // TODO: Await.
                },
                .hash => {
                    switch (c) {
                        '0'...'9', 'a'...'f', 'A'...'F' => {},
                        else => {
                            result.typ = .hash_color;
                            result.end = self.pos;
                            break;
                        },
                    }
                },
            }
        } else {
            // eof
            result.end = self.pos;
        }
        result.slice = self.buf[result.start..result.end];
        return result;
    }
};

fn dumpTokens(buf: []const u8) void {
    var tokenizer = Tokenizer.init(buf);
    while (true) {
        var token = tokenizer.nextToken();
        if (token.typ == .eof) break;

        debug("{d}-{d} - {s}: '{s}'\n", .{ token.start, token.end, token.typ, buf[token.start..token.end] });
    }
}

fn expectTokens(buf: []const u8, expected_tokens: []const TokenType) !void {
    var tokenizer = Tokenizer.init(buf);

    for (expected_tokens) |expected_token, i| {
        const found_token = tokenizer.nextToken();
        testing.expectEqual(expected_token, found_token.typ) catch |e| {
            debug("Expected token[{d}] {s}, got {s}:\n\n", .{ i, expected_token, found_token.typ });
            debug("  ({d}-{d}): '{s}'\n", .{ found_token.start, found_token.end, buf[found_token.start..found_token.end] });
            return e;
        };
    }
}

test "tokenize exploration" {
    var buf =
        \\node Module {
        \\  label: Module
        \\}
        \\
    ;

    // dumpTokens(buf);
    try expectTokens(buf, &[_]TokenType{
        .keyword_node,
        .identifier,
        .brace_start,
        .nl
,
        .identifier,
        .colon,
        .identifier,
        .nl
,
        .brace_end,
        .nl
 });
}   

test "tokenize exploration 2" {
    var buf =
        \\layout {
        \\    width: 600px
        \\    height: 400px
        \\    background: #fffffff
        \\    foreground: #0000000
        \\}
    ;

    // dumpTokens(buf);
    try expectTokens(buf, &[_]TokenType{
        // Layout {
        .keyword_layout,
        .brace_start,
        .nl
,
        // width: 600px
        .identifier,
        .colon,
        .numeric_literal,
        .identifier, // .numeric_unit
        .nl
,
        // height: 400px
        .identifier,
        .colon,
        .numeric_literal,
        .identifier, // .numeric_unit
        .nl
,
        // background: #ffffff
        .identifier,
        .colon,
        .hash_color,
        .nl
,
        // foreground: #ffffff
        .identifier,
        .colon,
        .hash_color,
        .nl
,
        // }
        .brace_end,
    });
}

// General strategy
// For text: We start with simply storing slices of the input-data in the Dif
// If we later find we need to preprocess something, we'll reconsider and add dedicated storage

const NodeShape = enum {
    square,
    circle,

    pub fn fromString(name: []const u8) NodeShape {
        if(std.mem.eql(u8, name, "square")) return .square;
        if(std.mem.eql(u8, name, "circle")) return .circle;

        return .square; // default
    }
};

const EdgeStyle = enum {
    solid,
    dotted,
    dashed,

    pub fn fromString(name: []const u8) EdgeStyle {
        if(std.mem.eql(u8, name, "solid")) return .solid;
        if(std.mem.eql(u8, name, "dotted")) return .dotted;
        if(std.mem.eql(u8, name, "dashed")) return .dashed;

        return .solid; // default
    }
};

const EdgeEndStyle = enum {
    none,
    arrow_open,
    arrow_closed,

    pub fn fromString(name: []const u8) EdgeEndStyle {
        if(std.mem.eql(u8, name, "none")) return .none;
        if(std.mem.eql(u8, name, "arrow_open")) return .arrow_open;
        if(std.mem.eql(u8, name, "arrow_closed")) return .arrow_closed;

        return .none; // default
    }

};

const Color = struct {
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

const NodeDefinition = struct {
    name: []const u8,
    label: []const u8 = undefined,
    shape: NodeShape = .square,
    // TODO: Add more style-stuff
    bg_color: ?Color = null,
    fg_color: ?Color = null,
};

const EdgeDefinition = struct {
    name: []const u8,
    label: ?[]const u8 = null,
    edge_style: EdgeStyle = EdgeStyle.solid,
    source_symbol: EdgeEndStyle = EdgeEndStyle.none,
    source_label: ?[]const u8 = null,
    target_symbol: EdgeEndStyle = EdgeEndStyle.none,
    target_label: ?[]const u8 = null,
};

const Relationship = struct {
    // TBD: This is currently pointers, but could just as well be idx to the respective arrays. Benchmark later on.
    source: *NodeInstance, // Necessary? Or simple store them at the source-NodeInstance and point out?
    target: *NodeInstance,
    edge: *EdgeDefinition,
};

const NodeInstance = struct {
    type: *NodeDefinition,
    name: []const u8,
    label: ?[]const u8 = null,
    relationships: [64]Relationship,
};

/// Diagrammer Internal Format / Representation
const Dif = struct {
    // Definitions / types
    nodeDefinitions: std.BoundedArray(NodeDefinition, 64) = initBoundedArray(NodeDefinition, 64),
    edgeDefinitions: std.BoundedArray(EdgeDefinition, 64) = initBoundedArray(EdgeDefinition, 64),

    // The actual nodes and edges
    nodeInstance: std.BoundedArray(NodeInstance, 256) = initBoundedArray(NodeInstance, 256),
};

/// Adds tokens to tokens_out and returns number of tokens found/added
fn tokenize(buf: []const u8, tokens_out: []Token) !usize {
    var tokenizer = Tokenizer.init(buf);
    var tok_idx: usize = 0;
    while (tok_idx < buf.len) {
        const token = tokenizer.nextToken();
        tokens_out[tok_idx] = token;
        tok_idx += 1;

        if (token.typ == .eof) break;
    } else if (tok_idx == buf.len) {
        return error.Overflow;
    }
    return tok_idx;
}

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

fn parseColor(tokens: []const Token) Color {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .hash_color);
    return Color.fromHexstring(tokens[2].slice);
}

fn parseNodeDefinition(name: []const u8, tokens: []const Token) !NodeDefinition {
    var result = NodeDefinition{
        .name = name,
    };

    var state: enum {
        start,
        GotKey,
        Gotcolon,
        // GotValue
    } = .start;
    _ = state;

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
            result.shape = parseNodeShape(tokens[idx..idx+3]);
        } else if(std.mem.eql(u8, token.slice, "color")) {
            result.fg_color = parseColor(tokens[idx..idx+3]);
        } else if(std.mem.eql(u8, token.slice, "background")) {
            result.bg_color = parseColor(tokens[idx..idx+3]);
        }
    }
    return result;
}

fn parseNodeShape(tokens: []const Token) NodeShape {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    return NodeShape.fromString(tokens[2].slice);
}

fn parseEdgeStyle(tokens: []const Token) EdgeStyle {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    return EdgeStyle.fromString(tokens[2].slice);
}

fn parseEdgeEdgeEndStyle(tokens: []const Token) EdgeEndStyle {
    assert(tokens.len > 2);
    assert(tokens[1].typ == .colon);
    assert(tokens[2].typ == .identifier);
    return EdgeEndStyle.fromString(tokens[2].slice);
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
            result.edge_style = parseEdgeStyle(tokens[idx..idx+3]);
            idx += 3;
        } else if(std.mem.eql(u8, token.slice, "targetSymbol")) {
            // debug("parsing targetSymbol\n", .{});
            result.target_symbol = parseEdgeEdgeEndStyle(tokens[idx..idx+3]);
            idx += 3;
        } else if(std.mem.eql(u8, token.slice, "sourceSymbol")) {
            result.source_symbol = parseEdgeEdgeEndStyle(tokens[idx..idx+3]);
            idx += 3;
        }
    }
    return result;
}



fn tokensToDif(tokens: []const Token, out_dif: *Dif) !void {
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
                debug("End of file\n", .{});
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
            else => {},
        }
    }

    // Naive strategy: separate pass for each step
    // Optimized strategy: parse as we go, and lazily fill up if something's out of order. Can start with requirement that defs must be top-down for simplicity, but it also enforces readability
}

/// Take the Dif and convert it to well-defined DOT. Returns size of dot-buffer
fn difToDot(dif: *Dif, out_buf: []u8) !usize {
    // TODO: Replace with proper dot-definitions
    var len: usize = 0;
    for(dif.nodeDefinitions.slice()) |el| {
        len += (try std.fmt.bufPrint(out_buf[len..],
        \\nodeDefinition: {s}
        \\  label: "{s}"
        \\  shape: {s}
        \\  fg_color: {s}
        \\  bg_color: {s}
        \\
        , .{el.name, el.label, el.shape, el.fg_color, el.bg_color})).len;
    }

    for(dif.edgeDefinitions.slice()) |el| {
        len += (try std.fmt.bufPrint(out_buf[len..],
            \\edgeDefinition: {s}\n  label: "{s}"
            \\  edge_style: {s}
            \\  source_symbol: {s}
            \\  target_symbol: {s}
            \\
            , .{el.name, el.label, el.edge_style, el.source_symbol, el.target_symbol})).len;
    }

    for(dif.nodeInstance.slice()) |el| {
        len += (try std.fmt.bufPrint(out_buf[len..], "nodeInstance: {s}\n", .{el.name})).len;
    }

    return len;
}

/// Full process from input-buffer of hidot-format to ouput-buffer of dot-format
fn hidotToDot(buf: []const u8, out_buf: []u8) !usize {
    var tokens_buf = initBoundedArray(Token, 1024);
    try tokens_buf.resize(try tokenize(buf, tokens_buf.unusedCapacitySlice()));
    // dumpTokens(buf);
    var dif = Dif{};
    try tokensToDif(tokens_buf.slice(), &dif);
    return try difToDot(&dif, out_buf);
}

fn hidotFileToDotFile(path_hidot_input: []const u8, path_dot_output: []const u8) !void {
    // Allocate sufficiently big input and output buffers (1MB to begin with)
    var input_buffer = initBoundedArray(u8, 1024 * 1024);
    var output_buffer = initBoundedArray(u8, 1024 * 1024);
    // Open path_hidot_input and read to input-buffer
    try input_buffer.resize(try readFile(std.fs.cwd(), path_hidot_input, input_buffer.unusedCapacitySlice()));
    // debug("input: {s}\n", .{input_buffer.slice()});
    // hidotToDot(input_buffer, output_buffer);
    try output_buffer.resize(try hidotToDot(input_buffer.slice(), output_buffer.unusedCapacitySlice()));
    // Write output_buffer to path_dot_output
    // debug("output: {s}\n", .{output_buffer.slice()});
    try writeFile(std.fs.cwd(), path_dot_output, output_buffer.slice());
}

test "dummy" {
    debug("sizeOf(Dif): {d}kb\n", .{@divFloor(@sizeOf(Dif), 1024)});
}

test "full cycle" {
    try hidotFileToDotFile("../../exploration/syntax/diagrammer.hidot", "test_full_cycle.dot");
}

// Sequence:
// 1. Input: buffer
// 2. Tokenize
// 3. AST
// 4. Process AST?
// 5. Generate .dot
// 6. Optional: from dot, convert e.g. svg, png etc.

fn initBoundedArray(comptime T: type, comptime S: usize) std.BoundedArray(T, S) {
    return std.BoundedArray(T, S).init(0) catch unreachable;
}

pub fn readFile(base_dir: std.fs.Dir, path: []const u8, target_buf: []u8) !usize {
    var file = try base_dir.openFile(path, .{ .read = true });
    defer file.close();

    return try file.readAll(target_buf[0..]);
}

pub fn writeFile(base_dir: std.fs.Dir, path: []const u8, target_buf: []u8) !void {
    var file = try base_dir.createFile(path, .{ .truncate = true });
    defer file.close();

    return try file.writeAll(target_buf[0..]);
}
