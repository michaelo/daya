const std = @import("std");
const utils = @import("utils.zig");
const testing = std.testing;
const debug = std.debug.print;
const any = utils.any;

pub const TokenType = enum {
    invalid,
    eof,
    eos,
    value,
    keyword_node,
    keyword_edge,
    keyword_group,
    keyword_layer,
    identifier,
    single_line_comment,
    brace_start,
    brace_end,
    colon,
    equal,
    string,
    include,
};

pub const Token = struct {
    typ: TokenType,
    start: u64,
    end: u64,
    slice: []const u8, // Requires source buf to be available
};

pub const Tokenizer = struct {
    const State = enum {
        start,
        string,
        include,
        identifier_or_keyword,
        single_line_comment,
        f_slash,
    };

    buf: []const u8,
    pos: u64 = 0,

    pub fn init(buffer: []const u8) Tokenizer {
        return Tokenizer{
            .buf = buffer,
        };
    }

    pub fn nextToken(self: *Tokenizer) Token {
        var result = Token{
            .typ = .eof,
            .start = self.pos,
            .end = undefined,
            .slice = undefined,
        };

        var state: State = .start;

        while (self.pos < self.buf.len) : (self.pos += 1) {
            const c = self.buf[self.pos];
            switch (state) {
                .start => {
                    result.start = self.pos;
                    switch (c) {
                        '/' => {
                            state = .f_slash;
                        },
                        '"' => {
                            state = .string;
                            result.start = self.pos + 1;
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
                        '=' => {
                            result.typ = .equal;
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
                        // Whitespace of any kind are separators
                        ' ', '\t', '\n' => {
                            result.start = self.pos + 1;
                        },
                        '@' => {
                            state = .include;
                            result.typ = .include;
                        },
                        else => {
                            // Any character not specifically intended for something else is a valid identifier-character
                            result.typ = .identifier; // will be overridden if it turns out to be a keyword
                            state = .identifier_or_keyword;
                        },
                    }
                },
                .string => {
                    switch (c) {
                        '"' => {
                            // Ignore escaped "'s
                            if (self.buf[self.pos - 1] == '\\') continue;

                            result.end = self.pos;
                            result.typ = .string;
                            self.pos += 1;
                            break;
                        },
                        else => {},
                    }
                },
                .identifier_or_keyword => {
                    switch (c) {
                        // Anything that's not whitespace, special reserver character or eos is a valid identifier
                        '\n', '\t', ' ', '\r', ';', '{', '}', '(', ')', ':', '=' => {
                            result.end = self.pos;
                            result.typ = keywordOrIdentifier(self.buf[result.start..result.end]);
                            break;
                        },
                        else => {},
                    }
                },
                .f_slash => {
                    switch (c) {
                        '/' => state = .single_line_comment,
                        else => {
                            // Currently unknown token TODO: Error?
                            break;
                        },
                    }
                },
                .single_line_comment => {
                    // Spin until end of line
                    switch (c) {
                        '\n' => {
                            state = .start;
                        },
                        else => {},
                    }
                },
                .include => {
                    // Spin until end of line / buffer
                    switch (c) {
                        '\n' => {
                            result.end = self.pos;
                            self.pos += 1;
                            break;
                        },
                        else => {},
                    }
                },
            }
        } else {
            // end of "file"
            result.end = self.pos;

            if (state == .identifier_or_keyword) {
                result.typ = keywordOrIdentifier(self.buf[result.start..result.end]);
            }
        }
        result.slice = self.buf[result.start..result.end];
        return result;
    }
};

const keyword_map = .{
    .{ "node", TokenType.keyword_node },
    .{ "edge", TokenType.keyword_edge },
    .{ "group", TokenType.keyword_group },
    .{ "layer", TokenType.keyword_layer },
};

/// Evaluates a string against a known set of supported keywords
fn keywordOrIdentifier(value: []const u8) TokenType {
    inline for (keyword_map) |kv| {
        if (std.mem.eql(u8, value, kv[0])) {
            return kv[1];
        }
    }

    return TokenType.identifier;
}

test "keywordOrIdentifier" {
    try testing.expectEqual(TokenType.keyword_edge, keywordOrIdentifier("edge"));
    try testing.expectEqual(TokenType.identifier, keywordOrIdentifier("edgeish"));
}

/// For tests
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

test "tokenizer tokenizes empty string" {
    try expectTokens("", &[_]TokenType{.eof});
}

test "tokenizer tokenizes string-tokens" {
    try expectTokens(
        \\"string here"
    , &[_]TokenType{ .string, .eof });
}

test "tokenizer tokenizes identifier" {
    try expectTokens(
        \\unquoted_word_without_white-space
    , &[_]TokenType{ .identifier, .eof });
}

test "tokenizer tokenizes keyword" {
    try expectTokens(
        \\node edge group layer
    , &[_]TokenType{ .keyword_node, .keyword_edge, .keyword_group, .keyword_layer, .eof });
}

test "tokenizer tokenizes import-statements" {
    var buf = "@somefile.hidot";
    try expectTokens(buf, &[_]TokenType{.include});
}

test "tokenize exploration" {
    var buf =
        \\node Module {
        \\  label="My module";
        \\}
        \\
        \\// Comment here
        \\edge relates_to {
        \\  label="relates to";
        \\  color=#ffffff;
        \\}
        \\
        \\edge owns;
        \\
        \\ModuleA: Module;
        \\ModuleB: Module;
        \\
        \\ModuleA relates_to ModuleB;
        \\ModuleB owns ModuleA {
        \\  label="overridden label here";
        \\}
        \\
    ;

    try expectTokens(buf, &[_]TokenType{
        // node Module {...}
        .keyword_node, .identifier, .brace_start,
            .identifier, .equal, .string, .eos,
        .brace_end,

        // edge relates_to {...}
        .keyword_edge, .identifier, .brace_start,
            .identifier, .equal, .string, .eos,
            .identifier, .equal, .identifier, .eos,
        .brace_end,

        // edge owns;
        .keyword_edge, .identifier, .eos,

        // Instantations
        .identifier, .colon, .identifier, .eos,
        .identifier, .colon, .identifier, .eos,

        // Relationships
        // ModuleA relates_to ModuleB
        .identifier, .identifier, .identifier, .eos,

        // ModuleB owns ModuleA
        .identifier, .identifier, .identifier, .brace_start,
            .identifier, .equal, .string, .eos,
        .brace_end,

        .eof,
    });
}

pub fn dump(buf: []const u8) void {
    var tokenizer = Tokenizer.init(buf);
    var i: usize = 0;

    while (true) : (i += 1) {
        var token = tokenizer.nextToken();
        var start = utils.idxToLineCol(buf[0..], token.start);
        debug("token[{d:>2}] ({d:>2}:{d:<2}): {s:<16} -> {s}\n", .{ i, start.line, start.col, @tagName(token.typ), token.slice });
        if (token.typ == .eof) break;
    }
}
