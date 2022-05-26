const std = @import("std");
const builtin = @import("builtin");
const debug = std.debug.print;

const hidot = @import("hidot");
const argparse = @import("argparse.zig");

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

/// Main executable entry point
/// Sets up allocator, parses arguments and invokes do() - the main doer.
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    defer arena.deinit();
    const aa = arena.allocator();

    const args = try std.process.argsAlloc(aa);
    defer std.process.argsFree(aa, args);

    var parsedArgs = argparse.parseArgs(args[1..]) catch |e| switch(e) {
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
            debug("Could not write to output-file: {s}\n", .{parsedArgs.output_file});
        },
        errors.ProcessError => {
            // Compilation-error, previous output should pinpoint the issue.
        },
        else => {
            debug("DEBUG: Unhandled error: {s}\n", .{e});
        }
    };
}

/// 
pub fn do(allocator: std.mem.Allocator, args: *argparse.AppArgs) errors!void {
    // v0.1.0:
    // Generate a .dot anyway: tmp.dot
    //   Att! This makes it not possible to run in parallal for now
    const TEMPORARY_FILE = "__hidot_tmp.dot";
    
    try hidotFileToDotFile(allocator, args.input_file, TEMPORARY_FILE);
    defer std.fs.cwd().deleteFile(TEMPORARY_FILE) catch |e| {
        debug("ERROR: Could not delete temporary file '{s}' ({s})\n", .{TEMPORARY_FILE, e});
    };

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

/// 
pub fn hidotFileToDotFile(allocator: std.mem.Allocator, path_hidot_input: []const u8, path_dot_output: []const u8) errors!void {
    // TODO: Set cwd to the folder of the file so any includes are handled relatively to file
    var input_buffer = std.fs.cwd().readFileAlloc(allocator, path_hidot_input, 10*1024*1024) catch |e| switch(e) {
        error.FileTooBig => return errors.TooLargeInputFile,
        error.FileNotFound, error.AccessDenied => return errors.CouldNotReadInputFile,
        else => {
            debug("ERROR: Got error '{s}' while reading input file '{s}'\n", .{@errorName(e), path_hidot_input});
            return errors.ProcessError;
        },
    };
    defer allocator.free(input_buffer);

    var file = std.fs.cwd().createFile(path_dot_output, .{ .truncate = true }) catch {
        debug("ERROR: Got error '{s}' while attempting to create file '{s}'\n", .{@errorName(e), path_dot_output});
        return errors.ProcessError;
    };
    errdefer std.fs.cwd().deleteFile(path_dot_output) catch |e| {
        debug("ERROR: Could not delete temporary file '{s}' ({s})\n", .{path_dot_output, e});
    };
    defer file.close();
    
    hidot.hidotToDot(allocator, std.fs.File.Writer, file.writer(), input_buffer[0..], path_hidot_input) catch |e| {
        debug("ERROR: Got error '{s}' when compiling, see messages above\n", .{@errorName(e)});
        return errors.ProcessError;
    };
}


/// Launches a child process to call dot, assumes it's available in path
fn callDot(allocator: std.mem.Allocator, input_file: []const u8, output_file: []const u8, output_format: argparse.OutputFormat) !void {
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

test {
    _ = @import("argparse.zig");
}