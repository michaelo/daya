const std = @import("std");
const testing = std.testing;
const debug = std.debug.print;
const assert = std.debug.assert;

fn keywordOrIdentifier(value: []const u8) TokenType {
    if(std.mem.eql(u8, value, "node")) {
        return TokenType.Keyword_Node;
    } else if(std.mem.eql(u8, value, "edge")) {
        return TokenType.Keyword_Edge;
    } else if(std.mem.eql(u8, value, "layout")) {
        return TokenType.Keyword_Layout;
    }

    return TokenType.Identifier;
}

const TokenType = enum {
    Invalid,
    Eof,
    Nl,
    Keyword_Node,
    Keyword_Edge,
    Keyword_Layout,
    Identifier,
    SingleLineComment,
    BraceStart,
    BraceEnd,
    QuoteStart, // necessary? we only want the inner string anyway
    QuoteEnd, // necessary? we only want the inner string anyway
    Colon,
    Arrow,
    NumericLiteral,
    NumericUnit,
    HashColor
    };

const Token = struct {
    typ: TokenType,
    start: u64,
    end: u64,
    slice: []const u8, // Requires source buf to be available
};

const Tokenizer = struct {
    const State = enum {
        Start,
        String,
        Identifier,
        SingleLineComment,
        Dash,
        NumericLiteral,
        NumericUnit,
        Hash,
        FSlash,
    };

    buf: []const u8,
    pos: u64 = 0,
    // state: ParseState = .Start,

    fn init(buffer: []const u8) Tokenizer {
        return Tokenizer{
            .buf = buffer,
        };
    }

    fn nextToken(self: *Tokenizer) Token {
        var result = Token{
            .typ = .Eof,
            .start = self.pos,
            .end = undefined,
            .slice = undefined,
        };

        var state: State = .Start;

        while (self.pos < self.buf.len) : (self.pos += 1) {
            const c = self.buf[self.pos];
            // debug("Processing '{c}' ({s})\n", .{c, state});
            switch (state) {
                .Start => {
                    switch (c) {
                        '/' => {
                            state = .FSlash;
                        },
                        '#' => {
                            state = .Hash;
                        },
                        'a'...'z', 'A'...'Z' => {
                            state = .Identifier;
                        },
                        '0'...'9' => {
                            state = .NumericLiteral;
                        },
                        '{' => {
                            result.typ = .BraceStart;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        '}' => {
                            result.typ = .BraceEnd;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        ':' => { // TODO: Doesn't hit...
                            result.typ = .Colon;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        // TBD: Any semantic use for newlines, or simply treat it like any space? Will then need another separator, e.g. ;
                        '\n' => {
                            result.typ = .Nl;
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
                .String => {},
                .Identifier => {
                    switch (c) {
                        'a'...'z', 'A'...'Z', '0'...'9' => {},
                        else => {
                            result.end = self.pos; // TBD: +1?
                            result.typ = keywordOrIdentifier(self.buf[result.start..result.end]);
                            // self.pos+=1;
                            break;
                        },
                    }
                },
                .FSlash => {
                    switch(c) {
                        '/' => state = .SingleLineComment,
                        else => {
                            // Currently unknown token
                            break;
                        }
                    }
                },
                .SingleLineComment => {
                    // Spin until end of line
                    // Currently ignoring comments
                    switch (c) {
                        '\n' => break,
                        else => {},
                    }
                },
                .Dash => {

                },
                .NumericLiteral => {
                    switch(c) {
                        '0'...'9' => {},
                        // 'a'...'z' => state = .NumericUnit,
                        else => {
                            result.typ = .NumericLiteral;
                            result.end = self.pos;
                            break;
                        }
                    }
                },
                .NumericUnit => {
                    // TODO: Await.
                },
                .Hash => {
                    switch(c) {
                        '0'...'9','a'...'f','A'...'F' => {},
                        else => {
                            result.typ = .HashColor;
                            result.end = self.pos;
                            break;
                        }
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
        if (token.typ == .Eof) break;

        debug("{d}-{d} - {s}: '{s}'\n", .{ token.start, token.end, token.typ, buf[token.start..token.end] });
    }
}

fn expectTokens(buf: []const u8, expected_tokens: []const TokenType) !void {
    var tokenizer = Tokenizer.init(buf);

    for (expected_tokens) |expected_token, i| {
        const found_token = tokenizer.nextToken();
        testing.expectEqual(expected_token, found_token.typ) catch |e| {
            debug("Expected token[{d}] {s}, got {s}:\n\n", .{ i, expected_token, found_token.typ });
            debug("  ({d}-{d}): '{s}'\n", .{found_token.start, found_token.end, buf[found_token.start..found_token.end]});
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
        .Keyword_Node,
        .Identifier,
        .BraceStart,
        .Nl,
        .Identifier,
        .Colon,
        .Identifier,
        .Nl,
        .BraceEnd,
        .Nl });
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
        .Keyword_Layout,
        .BraceStart,
        .Nl,
        // width: 600px
        .Identifier,
        .Colon,
        .NumericLiteral,
        .Identifier, // .NumericUnit
        .Nl,
        // height: 400px
        .Identifier,
        .Colon,
        .NumericLiteral,
        .Identifier, // .NumericUnit
        .Nl,
        // background: #ffffff
        .Identifier,
        .Colon,
        .HashColor,
        .Nl,
        // foreground: #ffffff
        .Identifier,
        .Colon,
        .HashColor,
        .Nl,
        // }
        .BraceEnd
        });
}

// General strategy
// For text: We start with simply storing slices of the input-data in the Dif
// If we later find we need to preprocess something, we'll reconsider and add dedicated storage

const NodeShape = enum {
    Square,
    Circle,
};

const EdgeStyle = enum {
    Solid,
    Dotted,
    Dashed
};

const EdgeEndStyle = enum {
    None,
    OpenArrow,
    SolidArrow
};

const NodeDefinition = struct {
    label: []const u8,
    shape: NodeShape,
    // TODO: Add more style-stuff
};

const EdgeDefinition = struct {
    label: []const u8,
    edgeStyle: EdgeStyle,
    sourceSymbol: EdgeEndStyle,
    sourceLabel: []const u8,
    targetSymbol: EdgeEndStyle,
    targetLabel: []const u8,
};

const Relationship = struct {
    // TBD: This is currently pointers, but could just as well be idx to the respective arrays. Benchmark later on.
    source: *NodeInstance, // Necessary? Or simple store them at the source-NodeInstance and point out?
    target: *NodeInstance,
    edge: *EdgeDefinition
};

const NodeInstance = struct {
    type: *NodeDefinition,
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
    while (tok_idx<buf.len) {
        const token = tokenizer.nextToken();
        tokens_out[tok_idx] = token;
        tok_idx += 1;

        if (token.typ == .Eof) break;
    } else if(tok_idx == buf.len) {
        return error.Overflow;
    }
    return tok_idx;
}

// Parse strategy: 
// Can create a variant of the tokanizer, but working on the tokens. Then have a struct/union based on a Type-enum (Definition (node, edge), Instantiation (MyObj: SomeNode), Property (key:value), Relation (<nodeinstance> <edgetype> <nodeinstance>)
// Can be run nested as well?

/// Take the tokenized input and parse/convert it to the internal format
/// We don't need/use a full AST (in the PL-form), but we need to parse to an internal format we can work with


const DifParser = struct {
    const State = enum {
        Start,
        String,
        Identifier,
        SingleLineComment,
        Dash,
        NumericLiteral,
        NumericUnit,
        Hash,
        FSlash,
    };

    tokens: []const Token,
    pos: u64 = 0,

    fn init(tokens: []const Token) DifParser {
        return DifParser{
            .tokens = tokens,
        };
    }

    fn nextToken(self: *Tokenizer) Token {
        // var result = Token{
        //     .typ = .Eof,
        //     .start = self.pos,
        //     .end = undefined,
        //     .slice = undefined,
        // };

        var state: State = .Start;
        _ = state;
        var idx: usize = 0;
        while(idx < self.tokens.len) : (idx += 1) {
            const token = self.tokens[idx];
            switch(token.typ) {
                .Eof => {
                    debug("End of file\n", .{});
                },
                .Keyword_Node => {
                    debug("Found node: {s}\n", .{self.tokens[idx+1].slice});
                    idx+=1;
                    assert(self.tokens[idx].typ == .BraceStart);
                    // while()
                    // TODO: Parse following chunk.

                },
                else => {}
            }
        }
    }
};

fn tokensToDif(tokens: []Token, out_dif: *Dif) void {
     _ = tokens;
     _ = out_dif;
    // Find all 'node'-blocks and add to out_dif.nodeDefinitions
    // Find all 'edge'-blocks and add to out_dif.edgeDefinitions
    // Find all node-instances (entries in top-level matching <identifier><colon><identifier>) and add to nodeinstances
    // Find all entries matching format: <identifier> <identifier> <identifier> <nl> where first and last identifier is nodeInstance, and the middle is edgeInstance
    var idx: usize = 0; 
    while(idx < tokens.len) : (idx += 1) {
        const token = tokens[idx];
        switch(token.typ) {
            .Eof => {
                debug("End of file\n", .{});
            },
            .Keyword_Node => {
                debug("Found node: {s}\n", .{tokens[idx+1].slice});
                idx+=1;
                assert(tokens[idx+1].typ == .BraceStart);
                // while()
                // TODO: Parse following chunk.
            },
            .Keyword_Edge => {
                debug("Found edge: {s}\n", .{tokens[idx+1].slice});
                idx+=1;
                assert(tokens[idx+1].typ == .BraceStart);
                // while()
                // TODO: Parse following chunk.
            },
            else => {}
        }
    }


    // Naive strategy: separate pass for each step
    // Optimized strategy: parse as we go, and lazily fill up if something's out of order. Can start with requirement that defs must be top-down for simplicity, but it also enforces readability

}

/// Take the Dif and convert it to well-defined DOT. Returns size of dot-buffer
fn difToDot(dif: *Dif, out_buf: []u8) !usize {
    _ = dif;
    _ = out_buf;
    return (try std.fmt.bufPrint(out_buf, "data here", .{})).len;    
}

/// Full process from input-buffer of hidot-format to ouput-buffer of dot-format
fn hidotToDot(buf: []const u8, out_buf: []u8) !usize {
    var tokens_buf = initBoundedArray(Token, 1024);
    try tokens_buf.resize(try tokenize(buf, tokens_buf.unusedCapacitySlice()));
    var dif = Dif{};
    tokensToDif(tokens_buf.slice(), &dif);
    return try difToDot(&dif, out_buf);
}

fn hidotFileToDotFile(path_hidot_input: []const u8, path_dot_output: []const u8) !void {
    // Allocate sufficiently big input and output buffers (1MB to begin with)
    var input_buffer = initBoundedArray(u8, 1024*1024);
    var output_buffer = initBoundedArray(u8, 1024*1024);
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
