const std = @import("std");
const testing = std.testing;

pub fn Entry(comptime T: type) type {
    return struct {
        const Self = @This();

        storage: *const std.ArrayList(T),
        idx: usize, // index into .storage.items

        pub inline fn get(self: *Self) *T {
            return &self.storage.items[self.idx];
        }

        pub inline fn getConst(self: *Self) *const T {
            return &self.storage.items[self.idx];
        }
    };
}

/// A wrapper for std.ArrayList to provide a way of accessing a relocatable
/// area of heap-memory. Returns a struct with local idx + pointer to the std.ArrayList
pub fn IndexedArrayList(comptime T: type) type {
    return struct {
        const Self = @This();

        storage: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .storage = std.ArrayList(T).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.storage.deinit();
        }

        pub fn addOne(self: *Self) error{OutOfMemory}!Entry(T) {
            _ = try self.storage.addOne();
            var idx = self.storage.items.len - 1;

            return Entry(T){ .storage = &self.storage, .idx = idx };
        }
    };
}

test "can add and get entries" {
    var mylist = IndexedArrayList(u64).init(std.testing.allocator);
    defer mylist.deinit();

    var el = try mylist.addOne();
    try testing.expect(el.idx == 0);
    try testing.expect(el.storage == &mylist.storage);

    el.get().* = 123;

    try testing.expect(el.get().* == 123);
    try testing.expect(mylist.storage.items[0] == 123);
}

// TODO: Performance tests, cache-friendliness
test "performance comparisons" {
    if (true) return error.SkipZigTest;

    const Data = struct {
        string: [256]u8,
        string2: [128]u8,
        string3: [128]u8,
        val: usize,
    };

    const iterations = 100;
    const reps_pr_iteration = 100000;

    // Testing the IndexedArrayList
    {
        var start = std.time.milliTimestamp();
        var iteration_counter: usize = 0;
        while (iteration_counter < iterations) : (iteration_counter += 1) {
            var mylist = IndexedArrayList(Data).init(std.testing.allocator);
            defer mylist.deinit();

            var i: usize = 0;
            var sum: usize = 0;
            while (i < reps_pr_iteration) : (i += 1) {
                var el = try mylist.addOne();
                el.get().*.val = i;
                sum += el.get().*.val;
            }
        }
        std.debug.print("time IndexedArrayList: {d}ms\n", .{@divTrunc(std.time.milliTimestamp() - start, iterations)});
    }

    // Testing the std.ArrayList for comparison
    {
        var start = std.time.milliTimestamp();

        var iteration_counter: usize = 0;
        while (iteration_counter < iterations) : (iteration_counter += 1) {
            var mylist = std.ArrayList(Data).init(std.testing.allocator);
            defer mylist.deinit();

            var i: usize = 0;
            var sum: usize = 0;
            while (i < reps_pr_iteration) : (i += 1) {
                var el = try mylist.addOne();
                el.*.val = i;
                sum += el.*.val;
            }
        }
        std.debug.print("time std.ArrayList: {d}ms\n", .{@divTrunc(std.time.milliTimestamp() - start, iterations)});
    }
}

// TODO: Create minimal example of const-issue to verify if it's a feature/bug and how it better could be solved
