const std = @import("std");
const testing = std.testing;
const debug = std.debug.print;

const ParseState = enum {
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

const TokenType = enum {
    Invalid,
    Eof,
    Nl,
    Keyword_Node,
    Keyword_Edge,
    Identifier,
    SingleLineComment,
    BraceStart,
    BraceEnd,
    QuoteStart,
    QuoteEnd,
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
};

const Tokenizer = struct {
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
        };

        var state: ParseState = .Start;

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
                        '\n' => {
                            result.typ = .Nl;
                            self.pos += 1;
                            result.end = self.pos;
                            break;
                        },
                        '0'...'9' => {
                            state = .NumericLiteral;
                        },
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
                            result.typ = .Identifier;
                            result.end = self.pos; // TBD: +1?
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
    try expectTokens(buf, &[_]TokenType{ .Identifier, .Identifier, .BraceStart, .Nl, .Identifier, .Colon, .Identifier, .Nl, .BraceEnd, .Nl });
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
        .Identifier,
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

const Ast = struct {

};

fn generateAst(buf: []const u8) void {
     _ = buf;
}

fn AstToDot(ast: *Ast) void {
    _ = ast;
}

// Sequence:
// 1. Input: buffer
// 2. Tokenize
// 3. AST
// 4. Process AST?
// 5. Generate .dot
// 6. Optional: from dot, convert e.g. svg, png etc.
