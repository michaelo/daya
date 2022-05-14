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

const errors = error {
    ParseError,
    CouldNotReadInputFile,
    CouldNotReadOutputFile,
    ProcessError
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

fn getLowercaseFileext(file: []const u8, scrap: []u8) ![]u8 {
    var last_dot = std.mem.lastIndexOf(u8, file, ".") orelse return error.NoExtFound;
    return std.ascii.lowerString(scrap, file[last_dot+1..]);
}

fn parseArgs(args: [][]const u8) !AppArgs {
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
            debug("{0s} v{1s} (libhidot v{2s})\n", .{APP_NAME, APP_VERSION, hidot.LIB_VERSION});
            return error.OkExit;
        }

        if(arg[0] == '-') {
            debug("ERROR: Unsupported argument '{s}'\n", .{arg});
            printHelp(false);
            return error.InvalidArgument;
        }

        
        // Check for input file
        var ext = getLowercaseFileext(arg, scrap[0..]) catch {
            debug("WARNING: Could not read file-extension of argument '{s}' (ignoring)\n", .{arg});
            continue;
        };

        if(std.mem.eql(u8, ext, "hidot")) {
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
    var input_file = maybe_input_file orelse {
        debug("ERROR: Missing input file\n", .{});
        return error.NoInputFile;
    };

    var output_file = maybe_output_file orelse {
        debug("ERROR: Missing output file\n", .{});
        return error.NoOutputFile;
    };

    var output_format = maybe_output_format orelse {
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

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    defer arena.deinit();
    const aa = arena.allocator();

    const args = try std.process.argsAlloc(aa);
    defer std.process.argsFree(aa, args);

    var parsedArgs = parseArgs(args[1..]) catch {
        debug("Unable to continue. Exiting.\n", .{});
        return;
    };

    do(&parsedArgs) catch |e| switch(e) {
        errors.CouldNotReadInputFile => {
            debug("Could not read input-file: {s}\n", .{parsedArgs.input_file});
        },
        errors.CouldNotReadOutputFile => {
            debug("Could not read output-file: {s}\n", .{parsedArgs.output_file});
        },
        else => {
            debug("DEBUG: Unhandled error: {s}\n", .{e});
        }
    };

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

pub fn do(args: *AppArgs) errors!void {
    const TEMPORARY_FILE = "__hidot_tmp.dot";
    // v0.1.0:
    // Generate a .dot anyway: tmp.dot
    //   Att! This makes it not possible to run in parallal for now
    // var scrap: [1024]u8 = undefined;
    // var output_tmp_dot = std.fmt.bufPrint(scrap, "{s}", .{});
    try hidotFileToDotFile(args.input_file, TEMPORARY_FILE);
    defer {
        std.fs.cwd().deleteFile(TEMPORARY_FILE) catch unreachable;
    }

    switch(args.output_format) {
        .dot => {
            // Copy the temporary file as-is to output-path
            std.fs.cwd().copyFile(TEMPORARY_FILE, std.fs.cwd(), args.output_file, std.fs.CopyFileOptions{}) catch {
                debug("ERROR: Could not create output file: {s}\n", .{args.output_file});
            };
        },
        .png, .svg => {
            // Call external dot to convert
            callDot(TEMPORARY_FILE, args.output_file, args.output_format) catch |e| {
                debug("ERROR: dot failed - {s}\n", .{e});
                return errors.ProcessError;
            };
        },
    }
}


pub fn hidotFileToDotFile(path_hidot_input: []const u8, path_dot_output: []const u8) errors!void {
    // Allocate sufficiently big input and output buffers (1MB to begin with)
    // TODO: Allocate larger buffer on heap?
    var input_buffer = std.BoundedArray(u8, 1024 * 1024).init(0) catch unreachable;
    
    // Open path_hidot_input and read to input-buffer
    input_buffer.resize(
        readFile(std.fs.cwd(), path_hidot_input, input_buffer.unusedCapacitySlice()) catch { return errors.CouldNotReadInputFile; }
    ) catch {
        unreachable; // Because readFile will fail because of unsufficient storage in unusedCapacitySlice() before .resize() fails.
        // return errors.ProcessError;
    };

    var file = std.fs.cwd().createFile(path_dot_output, .{ .truncate = true }) catch {
        return errors.ProcessError;
    };
    defer file.close();
    
    hidot.hidotToDot(std.fs.File.Writer, file.writer(), input_buffer.slice()) catch |e| {
        debug("ERROR: Got error from libhidot: {s}\n", .{e});
        return errors.ProcessError;
    };
}

// Launches a child process to call dot, assumes it's available in path
fn callDot(input_file: []const u8, output_file: []const u8, output_format: OutputFormat) !void {
    var allocator = std.testing.allocator;
    var output_file_arg_buf: [1024]u8 = undefined;
    var output_file_arg = try std.fmt.bufPrint(output_file_arg_buf[0..], "-o{s}", .{output_file});

    const result = try std.ChildProcess.exec(.{
                                .allocator = allocator,
                                .argv = &[_][]const u8{"dot", input_file, output_file_arg, switch(output_format) {
                                    .png => "-Tpng",
                                    .svg => "-Tsvg",
                                    else => unreachable
                                }},
                                .max_output_bytes = 128,
                            });
    
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }
}


fn readFile(base_dir: std.fs.Dir, path: []const u8, target_buf: []u8) !usize {
    var file = try base_dir.openFile(path, .{ });
    defer file.close();

    return try file.readAll(target_buf[0..]);
}


fn writeFile(base_dir: std.fs.Dir, path: []const u8, target_buf: []u8) !void {
    var file = try base_dir.createFile(path, .{ .truncate = true });
    defer file.close();

    return try file.writeAll(target_buf[0..]);
}
