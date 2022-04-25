const std = @import("std");
const testing = std.testing;

pub fn initBoundedArray(comptime T: type, comptime S: usize) std.BoundedArray(T, S) {
    return std.BoundedArray(T, S).init(0) catch unreachable;
}

// Takes 0-indexed idx into buffer, and returns the corresponding 1-indexed line and col of said character
// Intended to be used in error-situations
// Returns line and col=0 in in case of invalid input
pub fn idxToLineCol(src: []const u8, idx: usize) struct { l: usize, c: usize} {
    if(idx >= src.len) return .{.l=0, .c=0}; // TODO: throw error?

    var l: usize = 1;
    var lc: usize = 0;

    for(src[0..idx+1]) |c| {
        if(c == '\n') {
            l += 1;
            lc = 0;
            continue;
        }

        lc += 1;
    }

    return .{.l=l, .c=lc};
}

test "idxToLineCol" {
    var buf =
    \\0123
    \\56
    \\
    \\9
    ;

    try testing.expectEqual(idxToLineCol(buf[0..], 0), .{.l=1, .c=1});
    try testing.expectEqual(idxToLineCol(buf[0..], 3), .{.l=1, .c=4});
    try testing.expectEqual(idxToLineCol(buf[0..], 5), .{.l=2, .c=1});
}
