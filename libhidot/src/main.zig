const std = @import("std");
const builtin = @import("builtin");

const dif = @import("dif.zig");
const dot = @import("dot.zig");
const tokenizer = @import("tokenizer.zig");

const initBoundedArray = @import("utils.zig").initBoundedArray;
const Token = @import("tokenizer.zig").Token;
const Dif = dif.Dif;

pub const LIB_VERSION = blk: {
    if (builtin.mode != .Debug) {
        break :blk @embedFile("../VERSION");
    } else {
        break :blk @embedFile("../VERSION") ++ "-UNRELEASED";
    }
};

const debug = std.debug.print;

/// Full process from input-buffer of hidot-format to ouput-buffer of dot-format
pub fn hidotToDot(comptime Writer: type, buf: []const u8, writer: Writer) !void {
    var tokens_buf = initBoundedArray(Token, 1024);
    try tokens_buf.resize(try tokenizer.tokenize(buf, tokens_buf.unusedCapacitySlice()));
    // dumpTokens(buf);
    var mydif = dif.Dif{};
    try dif.tokensToDif(tokens_buf.slice(), &mydif);
    try dot.difToDot(Writer, &mydif, writer);
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