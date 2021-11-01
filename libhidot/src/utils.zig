const std = @import("std");

pub fn initBoundedArray(comptime T: type, comptime S: usize) std.BoundedArray(T, S) {
    return std.BoundedArray(T, S).init(0) catch unreachable;
}
