const std = @import("std");
const testing = std.testing;
const bufwriter = @import("bufwriter.zig");

pub fn initBoundedArray(comptime T: type, comptime S: usize) std.BoundedArray(T, S) {
    return std.BoundedArray(T, S).init(0) catch unreachable;
}

// Takes 0-indexed idx into buffer, and returns the corresponding 1-indexed line and col of said character
// Intended to be used in error-situations
// Returns line and col=0 in in case of invalid input
pub fn idxToLineCol(src: []const u8, idx: usize) struct { line: usize, col: usize, line_start: usize } {
    if (idx >= src.len) return .{ .line = 0, .col = 0, .line_start = 0 }; // TODO: throw error?

    var l: usize = 1;
    var lc: usize = 0;
    var ls: usize = 0;

    for (src[0 .. idx + 1]) |c, i| {
        if (c == '\n') {
            l += 1;
            lc = 0;
            ls = i + 1; // TODO: invalid idx if src ends with nl
            continue;
        }

        lc += 1;
    }

    return .{ .line = l, .col = lc, .line_start = ls };
}

test "idxToLineCol" {
    var buf =
        \\0123
        \\56
        \\
        \\9
    ;

    try testing.expectEqual(idxToLineCol(buf[0..], 0), .{ .line = 1, .col = 1, .line_start = 0 });
    try testing.expectEqual(idxToLineCol(buf[0..], 3), .{ .line = 1, .col = 4, .line_start = 0 });
    try testing.expectEqual(idxToLineCol(buf[0..], 5), .{ .line = 2, .col = 1, .line_start = 5 });
}

pub fn dumpSrcChunkRef(comptime Writer: type, writer: Writer, src: []const u8, start_idx: usize) void {
    const writeByte = writer.writeByte;
    // Prints the line in which the start-idx resides.
    // Assumes idx'es are valid within src-range
    // Assumed used for error-scenarios, perf not a priority
    const lc = idxToLineCol(src, start_idx);

    // Print until from start of line and until end of line/buf whichever comes first
    for (src[lc.line_start..]) |c| {
        if (c == '\n') break;

        writeByte(c) catch {};
    }
}

// Take a string and with simple heuristics try to make it more readable (replaces _ with space upon print)
// TODO: Support unicode properly
pub fn printPrettify(comptime Writer: type, writer: Writer, label: []const u8, comptime opts: struct {
    do_caps: bool = false,
}) !void {
    const State = enum {
        space,
        plain,
    };
    var state: State = .space;
    for (label) |c| {
        var fc = blk: {
            switch (state) {
                // First char of string or after space
                .space => switch (c) {
                    '_', ' ' => break :blk ' ',
                    else => {
                        state = .plain;
                        break :blk if (opts.do_caps) std.ascii.toUpper(c) else c;
                    },
                },
                .plain => switch (c) {
                    '_', ' ' => {
                        state = .space;
                        break :blk ' ';
                    },
                    else => break :blk c,
                },
            }
        };
        try writer.print("{c}", .{fc});
    }
}

test "printPrettify" {
    // Setup custom writer with buffer we can inspect
    var buf: [128]u8 = undefined;
    var bufctx = bufwriter.ArrayBuf{ .buf = buf[0..] };

    const writer = bufctx.writer();

    try printPrettify(@TypeOf(writer), writer, "label", .{});
    try testing.expectEqualStrings("label", bufctx.slice());
    bufctx.reset();

    try printPrettify(@TypeOf(writer), writer, "label", .{ .do_caps = true });
    try testing.expectEqualStrings("Label", bufctx.slice());
    bufctx.reset();

    try printPrettify(@TypeOf(writer), writer, "label_part", .{});
    try testing.expectEqualStrings("label part", bufctx.slice());
    bufctx.reset();

    try printPrettify(@TypeOf(writer), writer, "Hey Der", .{});
    try testing.expectEqualStrings("Hey Der", bufctx.slice());
    bufctx.reset();

    try printPrettify(@TypeOf(writer), writer, "æøå_æøå", .{}); // Att: unicode not handled
    try testing.expectEqualStrings("æøå æøå", bufctx.slice());
    bufctx.reset();

    // Not working
    // try printPrettify(@TypeOf(writer), writer, "æøå_æøå", .{.do_caps=true}); // Att: unicode not handled
    // try testing.expectEqualStrings("Æøå Æøå", bufctx.slice());
    // bufctx.reset();
}

pub const Color = struct {
    r: f16,
    g: f16,
    b: f16,
    a: f16,

    fn hexToFloat(color: []const u8) f16 {
        std.debug.assert(color.len == 2);
        var buf: [1]u8 = undefined;
        _ = std.fmt.hexToBytes(buf[0..], color) catch 0;
        return @intToFloat(f16, buf[0]) / 255;
    }

    pub fn fromHexstring(color: []const u8) Color {
        std.debug.assert(color.len == 7 or color.len == 9);
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

/// Checks for string-needle in a string-haystack. TBD: Can generalize.
pub fn any(comptime haystack: [][]const u8, needle: []const u8) bool {
    var found_any = false;
    inline for (haystack) |candidate| {
        if (std.mem.eql(u8, candidate, needle)) {
            found_any = true;
        }
    }
    return found_any;
}

test "any" {
    comptime var haystack = [_][]const u8{"label"};
    try testing.expect(any(haystack[0..], "label"));
    try testing.expect(!any(haystack[0..], "lable"));
}
