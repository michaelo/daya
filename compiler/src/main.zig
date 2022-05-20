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
    CouldNotWriteOutputFile,
    TooLargeInputFile,
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
        \\https://github.com/michaelo/hidot
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

    var parsedArgs = parseArgs(args[1..]) catch |e| switch(e) {
        error.OkExit => {
            return;
        },
        else => {
            debug("Unable to continue. Exiting.\n", .{});
            return;
        }
    };

    do(aa, &parsedArgs) catch |e| switch(e) {
        errors.CouldNotReadInputFile => {
            debug("Could not read input-file: {s}\nVerify that the path is correct and that the file is readable.\n", .{parsedArgs.input_file});
        },
        errors.CouldNotWriteOutputFile => {
            debug("Could not read output-file: {s}\n", .{parsedArgs.output_file});
        },
        errors.ProcessError => {
            // Compilation-error, previous output should pinpoint the issue.
        },
        else => {
            debug("DEBUG: Unhandled error: {s}\n", .{e});
        }
    };

    // Arguments:
    //   Input source (file or stdin (eventually))
    //   Output (file or stdout (eventually))
    //   Output format (dot, png, svg)
    // 
    // Sequence:
    //   Read input to buffer
    //   Establish writer for output
    //   Call lib, with output-writer
    //
}

pub fn do(allocator: std.mem.Allocator, args: *AppArgs) errors!void {
    const TEMPORARY_FILE = "__hidot_tmp.dot";
    // v0.1.0:
    // Generate a .dot anyway: tmp.dot
    //   Att! This makes it not possible to run in parallal for now
    // var scrap: [1024]u8 = undefined;
    // var output_tmp_dot = std.fmt.bufPrint(scrap, "{s}", .{});
    try hidotFileToDotFile(allocator, args.input_file, TEMPORARY_FILE);
    defer {
        std.fs.cwd().deleteFile(TEMPORARY_FILE) catch |e| {
            debug("ERROR: Could not delete temporary file '{s}' ({s})\n", .{TEMPORARY_FILE, e});
        };
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
            callDot(allocator, TEMPORARY_FILE, args.output_file, args.output_format) catch |e| {
                debug("ERROR: dot failed - {s}\n", .{e});
                return errors.ProcessError;
            };
        },
    }
}


pub fn hidotFileToDotFile(allocator: std.mem.Allocator, path_hidot_input: []const u8, path_dot_output: []const u8) errors!void {
    var input_buffer = std.fs.cwd().readFileAlloc(allocator, path_hidot_input, 10*1024*1024) catch |e| switch(e) {
        error.FileTooBig => return errors.TooLargeInputFile,
        error.FileNotFound, error.AccessDenied => return errors.CouldNotReadInputFile,
        else => {
            debug("ERROR: Got error '{s}' while reading input file '{s}'\n", .{e, path_hidot_input});
            return errors.ProcessError;
        },
    };
    defer allocator.free(input_buffer);

    var file = std.fs.cwd().createFile(path_dot_output, .{ .truncate = true }) catch {
        return errors.ProcessError;
    };
    defer file.close();
    
    hidot.hidotToDot(allocator, std.fs.File.Writer, file.writer(), input_buffer[0..]) catch |e| {
        debug("ERROR: Got error when compiling ({s}), see messages above\n", .{e});
        return errors.ProcessError;
    };
}


// Launches a child process to call dot, assumes it's available in path
fn callDot(allocator: std.mem.Allocator, input_file: []const u8, output_file: []const u8, output_format: OutputFormat) !void {
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

    var got_error: bool = switch(result.term) {
        .Stopped => |code| code > 0,
        .Exited => |code| code > 0,
        .Signal => true,
        .Unknown => true,
    };

    if(got_error) {
        debug("dot returned error: {s}\n", .{result.stderr});
        debug("Generate .dot-file instead to debug generated data. This is most likely a bug in hidot.", .{});
        return error.ProcessError;
    }
    
    defer {
        allocator.free(result.stderr);
        allocator.free(result.stdout);
    }
}
