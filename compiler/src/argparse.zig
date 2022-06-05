const std = @import("std");
const testing = std.testing;
const debug = std.debug.print;
const daya = @import("daya");
const main = @import("main.zig");

pub const OutputFormat = enum {
    dot,
    png,
    svg
};

pub const AppArgs = struct {
    input_file: []const u8,
    output_file: []const u8,
    output_format: OutputFormat = .png,
};

pub fn printHelp(full: bool) void {
    debug(
        \\{0s} v{1s} - Quick graphing utility
        \\
        \\Usage: {0s} [arguments] input.daya output.png
        \\
    , .{ main.APP_NAME, main.APP_VERSION});

    if (!full) {
        debug(
            \\
            \\try '{0s} --help' for more information.
            \\
        , .{main.APP_NAME});
        return;
    }
    
    debug(
        \\
        \\Examples:
        \\  {0s} myapp.daya mynicediagram.png
        \\  {0s} myapp.daya mynicediagram.svg
        \\  {0s} myapp.daya mynicediagram.dot
        \\
        \\Arguments
        \\  -h, --help          Show this help and exit
        \\      --version       Show version and exit
        // \\  -v, --verbose       Verbose output
        \\
        \\https://github.com/michaelo/daya
        \\
        , .{main.APP_NAME});
}

fn argIs(arg: []const u8, full: []const u8, short: ?[]const u8) bool {
    return std.mem.eql(u8, arg, full) or std.mem.eql(u8, arg, short orelse "321NOSUCHTHING123");
}

fn argHasValue(arg: []const u8, full: []const u8, short: ?[]const u8) ?[]const u8 {
    const eq_pos = std.mem.indexOf(u8, arg, "=") orelse return null;

    const key = arg[0..eq_pos];

    if(argIs(key, full, short)) {
        return arg[eq_pos + 1 ..];
    } else return null;
}

fn getLowercaseFileext(file: []const u8, scrap: []u8) ![]u8 {
    const last_dot = std.mem.lastIndexOf(u8, file, ".") orelse return error.NoExtFound;
    return std.ascii.lowerString(scrap, file[last_dot+1..]);
}

pub fn parseArgs(args: []const []const u8) !AppArgs {
    if(args.len < 1) {
        debug("ERROR: No arguments provided\n", .{});
        printHelp(false);
        return error.NoArguments;
    }

    var scrap: [64]u8 = undefined;

    var maybe_input_file: ?[]const u8 = null;
    var maybe_output_file: ?[]const u8 = null;
    var maybe_output_format: ?OutputFormat = null;

    for (args) |arg| {
        // Flags
        if(argIs(arg, "--help", "-h")) {
            printHelp(true);
            return error.OkExit;
        }

        if(argIs(arg, "--version", null)) {
            debug("{0s} v{1s} (libdaya v{2s})\n", .{main.APP_NAME, main.APP_VERSION, daya.LIB_VERSION});
            return error.OkExit;
        }

        if(arg[0] == '-') {
            debug("ERROR: Unsupported argument '{s}'\n", .{arg});
            printHelp(false);
            return error.InvalidArgument;
        }

        
        // Check for input file
        const ext = getLowercaseFileext(arg, scrap[0..]) catch {
            debug("WARNING: Could not read file-extension of argument '{s}' (ignoring)\n", .{arg});
            continue;
        };

        if(std.mem.eql(u8, ext, "daya")) {
            maybe_input_file = arg[0..];
            continue;
        }

        // Check for valid output-file
        if(std.meta.stringToEnum(OutputFormat, ext)) |format| {
            maybe_output_file = arg[0..];
            maybe_output_format = format;
            continue;
        }

        debug("WARNING: Unhandled argument: '{s}'\n", .{arg});
    }

    // Validate parsed args
    const input_file = maybe_input_file orelse {
        debug("ERROR: Missing input file\n", .{});
        return error.NoInputFile;
    };

    const output_file = maybe_output_file orelse {
        debug("ERROR: Missing output file\n", .{});
        return error.NoOutputFile;
    };

    const output_format = maybe_output_format orelse {
        debug("ERROR: Unknown output format\n", .{});
        return error.NoOutputFormat;
    };

    // Donaroo
    return AppArgs{
        .input_file = input_file,
        .output_file = output_file,
        .output_format = output_format,
    };
}

test "ArgParse" {
    try testing.expectError(error.OkExit, parseArgs(&.{"--help"}));
    try testing.expectError(error.OkExit, parseArgs(&.{"-h"}));
    try testing.expectError(error.OkExit, parseArgs(&.{"--version"}));
}
