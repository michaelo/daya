const std = @import("std");
const builtin = @import("builtin");
const debug = std.debug.print;

const hidot = @import("hidot");

pub const APP_NAME = "hidot";
pub const APP_VERSION = blk: {
    if (builtin.mode != .Debug) {
        break :blk @embedFile("../VERSION");
    } else {
        break :blk @embedFile("../VERSION") ++ "-UNRELEASED";
    }
};


const OutputFormat = enum {
    dot,
    png,
    svg
};

const AppArgs = struct {
    input_file: []const u8,
    output_file: []const u8,
    output_format: OutputFormat = .png,
};

pub fn printHelp(full: bool) void {
    debug(
        \\{0s} v{1s} - Quick graphing utility
        \\
        \\Usage: {0s} [arguments] input.hidot output.png
        \\
    , .{ APP_NAME, APP_VERSION});

    if (!full) {
        debug(
            \\
            \\try '{0s} --help' for more information.
            \\
        , .{APP_NAME});
        return;
    }
    
    debug(
        \\
        \\Examples:
        \\  {0s} myapp.hidot mynicediagram.png
        \\  {0s} myapp.hidot mynicediagram.svg
        \\  {0s} myapp.hidot mynicediagram.dot
        \\
        \\Arguments
        \\  -h, --help          Show this help and exit
        \\      --version       Show version and exit
        \\  -v, --verbose       Verbose output
        \\
        , .{APP_NAME});
}

fn argIs(arg: []const u8, full: []const u8, short: ?[]const u8) bool {
    return std.mem.eql(u8, arg, full) or std.mem.eql(u8, arg, short orelse "321NOSUCHTHING123");
}

fn argHasValue(arg: []const u8, full: []const u8, short: ?[]const u8) ?[]const u8 {
    var eq_pos = std.mem.indexOf(u8, arg, "=") orelse return null;

    var key = arg[0..eq_pos];

    if(argIs(key, full, short)) {
        return arg[eq_pos + 1 ..];
    } else return null;
}

fn parseArgs(args: [][]const u8) !AppArgs {
    var result = AppArgs{
        .input_file = undefined,
        .output_file = undefined,
    };

    if(args.len < 1) {
        debug("ERROR: No arguments provided\n", .{});
        printHelp(false);
        return error.NoArguments;
    }

    for (args) |arg| {
        // Flags
        if(argIs(arg, "--help", "-h")) {
            printHelp(true);
            return error.OkExit;
        }

        if(argIs(arg, "--version", null)) {
            debug("{0s} v{1s} (libhidot v{2s})\n", .{APP_NAME, APP_VERSION, hidot.LIB_VERSION});
            return error.OkExit;
        }

        if(arg[0] == '-') {
            debug("ERROR: Unsupported argument '{s}'\n", .{arg});
            printHelp(false);
            return error.InvalidArgument;
        }
    }

    return result;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    defer arena.deinit();
    const aa = &arena.allocator;

    const args = try std.process.argsAlloc(aa);
    defer std.process.argsFree(aa, args);

    _ = parseArgs(args[1..]) catch {

    };
    // debug("Got hidot: {s}\nGot ibhidot: {s}\n", .{APP_VERSION, hidot.LIB_VERSION});
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
