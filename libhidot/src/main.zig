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
// fn hidotToDot(buf: []const u8, out_buf: []u8) !usize {
pub fn hidotToDot(buf: []const u8, file: std.fs.File) !usize {
    var tokens_buf = initBoundedArray(Token, 1024);
    try tokens_buf.resize(try tokenizer.tokenize(buf, tokens_buf.unusedCapacitySlice()));
    // dumpTokens(buf);
    var mydif = dif.Dif{};
    try dif.tokensToDif(tokens_buf.slice(), &mydif);
    return try dot.difToDotFile(&mydif, file);
}

pub fn hidotFileToDotFile(path_hidot_input: []const u8, path_dot_output: []const u8) !void {
    // Allocate sufficiently big input and output buffers (1MB to begin with)
    var input_buffer = initBoundedArray(u8, 1024 * 1024);
    // var output_buffer = initBoundedArray(u8, 1024 * 1024);
    // Open path_hidot_input and read to input-buffer
    try input_buffer.resize(try readFile(std.fs.cwd(), path_hidot_input, input_buffer.unusedCapacitySlice()));
    // debug("input: {s}\n", .{input_buffer.slice()});
    // hidotToDot(input_buffer, output_buffer);


    var file = try std.fs.cwd().createFile(path_dot_output, .{ .truncate = true });
    defer file.close();
    _ = try hidotToDot(input_buffer.slice(), file);
    // try output_buffer.resize(try hidotToDot(input_buffer.slice(), file.writer()));
    // Write output_buffer to path_dot_output
    // debug("output: {s}\n", .{output_buffer.slice()});
    // try writeFile(std.fs.cwd(), path_dot_output, output_buffer.slice());
}


// test "dummy" {
//     debug("sizeOf(Dif): {d}kb\n", .{@divFloor(@sizeOf(Dif), 1024)});
// }

// test "full cycle" {
//     try hidotFileToDotFile("../exploration/syntax/diagrammer.hidot", "tmp/test_full_cycle.dot");
// }




// Sequence:
// 1. Input: buffer
// 2. Tokenize
// 3. AST
// 4. Process AST?
// 5. Generate .dot
// 6. Optional: from dot, convert e.g. svg, png etc.



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

