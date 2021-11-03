const std = @import("std");
const testing = std.testing;
const debug = std.debug.print;

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

pub const TokenType = enum {
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

pub const Token = struct {
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
                    result.start = self.pos;
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
                        '\n' => {
                            state = .start;
                            // result.start = self.pos;
                        },
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
            // TODO: Pass .nl before .eof to simplify parser?
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


/// Adds tokens to tokens_out and returns number of tokens found/added
pub fn tokenize(buf: []const u8, tokens_out: []Token) !usize {
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


