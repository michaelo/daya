const std = @import("std");
const testing = std.testing;

pub fn initBoundedArray(comptime T: type, comptime S: usize) std.BoundedArray(T, S) {
    return std.BoundedArray(T, S).init(0) catch unreachable;
}

// Takes 0-indexed idx into buffer, and returns the corresponding 1-indexed line and col of said character
// Intended to be used in error-situations
// Returns line and col=0 in in case of invalid input
pub fn idxToLineCol(src: []const u8, idx: usize) struct { line: usize, col: usize, line_start: usize} {
    if(idx >= src.len) return .{.line=0, .col=0, .line_start=0}; // TODO: throw error?

    var l: usize = 1;
    var lc: usize = 0;
    var ls: usize = 0;

    for(src[0..idx+1]) |c, i| {
        if(c == '\n') {
            l += 1;
            lc = 0;
            ls = i+1; // TODO: invalid idx if src ends with nl
            continue;
        }

        lc += 1;
    }

    return .{.line=l, .col=lc, .line_start=ls};
}

test "idxToLineCol" {
    var buf =
    \\0123
    \\56
    \\
    \\9
    ;

    try testing.expectEqual(idxToLineCol(buf[0..], 0), .{.line=1, .col=1, .line_start=0});
    try testing.expectEqual(idxToLineCol(buf[0..], 3), .{.line=1, .col=4, .line_start=0});
    try testing.expectEqual(idxToLineCol(buf[0..], 5), .{.line=2, .col=1, .line_start=5});
}

pub fn parseError(src: []const u8, start_idx: usize, comptime fmt: []const u8, args: anytype) void {
    const print = std.io.getStdOut().writer().print;
    var lc = idxToLineCol(src, start_idx);
    print("PARSE ERROR ({d}:{d}): ", .{lc.line, lc.col}) catch {};
    print(fmt, args) catch {};
    print("\n", .{}) catch {};
    dumpSrcChunkRef(src, start_idx);
    print("\n", .{}) catch {};
    var i: usize = 0;
    if(lc.col > 0) while(i<lc.col-1): (i+=1) {
        print(" ", .{}) catch {};
    };
    print("^\n", .{}) catch {};
}

pub fn dumpSrcChunkRef(src: []const u8, start_idx: usize) void {
    const writeByte = std.io.getStdOut().writer().writeByte;
    // Prints the line in which the start-idx resides.
    // Assumes idx'es are valid within src-range
    // Assumed used for error-scenarios, perf not a priority
    var lc = idxToLineCol(src, start_idx);

    // Print until from start of line and until end of line/buf whichever comes first
    for(src[lc.line_start..]) |c| {
        if(c == '\n') break;

        writeByte(c) catch {};
    }
}