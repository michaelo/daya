const std = @import("std");
const debug = std.debug.print;

const hidot = @import("hidot");

pub fn main() !void {
    debug("Got hidot: {s}\nGot ibhidot: {s}\n", .{version(), hidot.version()});
    // Arguments:
    //   Input source (file or stdin)
    //   Output (file or stdout)
    //   Output format (dot, png, svg)
    // 
    // Sequence:
    //   Read input to buffer
    //   Establish writer for output
    //   Call lib, with output-writer
    //
}

pub fn version() []const u8 {
    return "hidot v" ++ @embedFile("../VERSION");
}
