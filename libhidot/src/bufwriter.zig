const std = @import("std");
const testing = std.testing;

pub const ArrayBufWriter = std.io.Writer(*ArrayBuf, ArrayBufWriteError, write);

pub const ArrayBufWriteError = error {
    BufferFull,
};

/// Create an array-backed buffer with std.io.Writer()-support
pub const ArrayBuf = struct {
    /// Slice to array which serves as the storage
    buf: []u8,

    /// Current number of bytes written to the array
    len: usize = 0,

    /// Slice from idx 0 to .len - e.g. the utilized area
    pub fn slice(self: *ArrayBuf) []u8 {
        return self.buf[0..self.len];
    }

    /// Create a writer for this buffer
    pub fn writer(self: *ArrayBuf) ArrayBufWriter {
        return ArrayBufWriter {
                .context = self
            };
    }
};

/// If there's capacity to write the entire set of bytes to the backing array - write. Otherwise return error.BufferFull
pub fn write(context: *ArrayBuf, bytes: []const u8) ArrayBufWriteError!usize {
    if(context.len + bytes.len > context.buf.len) return ArrayBufWriteError.BufferFull;

    std.mem.copy(u8, context.buf[context.len..], bytes);
    context.len += bytes.len;
    return bytes.len;
}

test "ArrayBuf" {
    var buf: [9]u8 = undefined;
    var cont = ArrayBuf {
        .buf = buf[0..],
    };

    var writer = cont.writer();
    try writer.print("woop", .{});
    try testing.expectEqualStrings("woop", cont.slice());
    try writer.print("scoop", .{});
    try testing.expectEqualStrings("woopscoop", cont.slice());

    try testing.expectError(ArrayBufWriteError.BufferFull, writer.print("1", .{}));
}
