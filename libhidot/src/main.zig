const std = @import("std");
const builtin = @import("builtin");

const dif = @import("dif.zig");
const dot = @import("dot.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

const initBoundedArray = @import("utils.zig").initBoundedArray;
const Token = @import("tokenizer.zig").Token;

pub const LIB_VERSION = blk: {
    if (builtin.mode != .Debug) {
        break :blk @embedFile("../VERSION");
    } else {
        break :blk @embedFile("../VERSION") ++ "-UNRELEASED";
    }
};

const debug = std.debug.print;

/// Full process from input-buffer of hidot-format to ouput-buffer of dot-format
pub fn hidotToDot(comptime Writer: type, writer: Writer, buf: []const u8) !void {
    var tokenizer = Tokenizer.init(buf[0..]);
    var nodePool = initBoundedArray(dif.DifNode, 1024);
    var rootNode = try dif.tokensToDif(1024, &nodePool, &tokenizer);
    try dot.difToDot(Writer, writer, rootNode);
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


test "test entry" {
    comptime {
        _ = @import("dif.zig");
        _ = @import("tokenizer.zig");
        _ = @import("utils.zig");
        _ = @import("bufwriter.zig");
        _ = @import("dot.zig");
    }
}