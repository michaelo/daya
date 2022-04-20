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
    } else if (std.mem.eql(u8, value, "group")) {
        return TokenType.keyword_group;
    } else if (std.mem.eql(u8, value, "layer")) {
        return TokenType.keyword_layer;
    }

    return TokenType.identifier;
}

pub const TokenType = enum {
    invalid,
    eof,
    eos,
    nl,
    value,
    keyword_node,
    keyword_edge,
    keyword_group,
    keyword_layout,
    keyword_layer,
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
                            // state = .hash; // Currently no need to do anything but passthrough the color
                            state = .identifier;
                        },
                        'a'...'z', 'A'...'Z', '-' => {
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
                        ':' => {
                            result.typ = .colon;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        ';' => {
                            result.typ = .eos;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        // TBD: Any semantic use for newlines, or simply treat it like any space? Will then need another separator, e.g. ;
                        // '\n' => {
                        //     result.typ = .nl;
                        //     self.pos += 1;
                        //     result.end = self.pos;
                        //     break;
                        // },
                        // Whitespace are separators
                        ' ', '\t', '\n' => {
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
                            // Ignore escaped "'s
                            if(self.buf[self.pos-1] == '\\') continue;

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
                        // Anything that's not whitespace, special reserver character or eos is a valid identifier
                        // 'a'...'z', 'A'...'Z', '0'...'9','_','-','<','>' => {},
                        '\n', '\t', ' ', '\r', ';', '{', '}', '(', ')', ':' => {
                            result.end = self.pos;
                            // TODO: Should we here have control if we're on lhs/rhs? Reserved leftside-keywords could be valid values
                            result.typ = keywordOridentifier(self.buf[result.start..result.end]);
                            break;
                        },
                        else => {}
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
        \\  label: "My module";
        \\}
        \\
        \\// Comment here
        \\edge relates_to {
        \\  label: "relates to";
        \\  color: #ffffff;
        \\}
        \\
        \\edge owns;
        \\
        \\ModuleA: Module;
        \\ModuleB: Module;
        \\
        \\ModuleA relates_to ModuleB;
        \\ModuleB owns ModuleA {
        \\  label: "overridden label here";
        \\}
        \\
    ;

    // dumpTokens(buf);
    try expectTokens(buf, &[_]TokenType{
        // node Module {...}
        .keyword_node,
        .identifier,
        .brace_start,
            .identifier,
            .colon,
            .string,
            .eos,
        .brace_end,

        // edge relates_to {...}
        .keyword_edge,
        .identifier,
        .brace_start,
            .identifier,
            .colon,
            .string,
            .eos,

            .identifier,
            .colon,
            .identifier, // #ffffff TODO: Parse it as hash-value already here?
            .eos,
        .brace_end,

        // edge owns;
        .keyword_edge,
        .identifier,
        .eos,

        // Instantations
        .identifier,
        .colon,
        .identifier,
        .eos,

        .identifier,
        .colon,
        .identifier,
        .eos,

        // Relationships
        // ModuleA relates_to ModuleB
        .identifier,
        .identifier,
        .identifier,
        .eos,

        // ModuleB owns ModuleA
        .identifier,
        .identifier,
        .identifier,
        .brace_start,
            .identifier,
            .colon,
            .string,
            .eos,
        .brace_end,

        .eof
 });
}

test "tokenize exploration 2" {
    var buf =
        \\node Module {
        \\  label: unquoted value;
        \\  width: 300px;
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

    var tokenizer = Tokenizer.init(buf);
    var i: usize = 0;
    while (true) : (i+=1) {
        var token = tokenizer.nextToken();
        debug("token[{d}]: {} -> {s}\n", .{i, token.typ, token.slice});
        if(token.typ == .eof) break;
    }
}

// Adds tokens to tokens_out and returns number of tokens found/added
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


