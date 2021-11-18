const std = @import("std");
const debug = std.debug.print;
const testing = std.testing;

pub const HttpMethod = enum {
    CONNECT,
    DELETE,
    GET,
    HEAD,
    OPTIONS,
    PATCH,
    POST,
    PUT,
    TRACE,

    pub fn string(self: HttpMethod) [:0]const u8 {
        return @tagName(self);
    }
    pub fn create(raw: []const u8) !HttpMethod {
        return std.meta.stringToEnum(HttpMethod, raw) orelse error.NoSuchHttpMethod;
    }
};

pub const HttpHeader = struct {
    pub const MAX_HEADER_LEN = 8*1024;

    name: std.BoundedArray(u8, 256),
    value: std.BoundedArray(u8, MAX_HEADER_LEN),
    pub fn create(name: []const u8, value: []const u8) !HttpHeader {
        return HttpHeader{
            .name = std.BoundedArray(u8, 256).fromSlice(std.mem.trim(u8, name, " ")) catch {
                return error.ParseError;
            },
            .value = std.BoundedArray(u8, MAX_HEADER_LEN).fromSlice(std.mem.trim(u8, value, " ")) catch {
                return error.ParseError;
            },
        };
    }

    pub fn render(self: *HttpHeader, comptime capacity: usize, out: *std.BoundedArray(u8, capacity)) !void {
        try out.appendSlice(self.name.slice());
        try out.appendSlice(": ");
        try out.appendSlice(self.value.slice());
    }
};

const HttpRequest = struct {
    const MAX_HEADER_LEN = 8*1024;
    const MAX_URI_LEN = 8*1024;

    const ParseState = enum {
        expecting_request_line,
        getting_method,
        getting_uri,
        getting_http_version,
        expecting_headers,
        expecting_header,
        expecting_header_start,
        parsing_header_got_nl,
        parsing_header,
        end_of_headers,
        expecting_payload,
        start, // Waiting to find token
        cr, // Expecting lf -> .start
        method, //
        url,
        http_version,
        header_start,
        header,
        header_end,
        eof, // This means that we're good to go!
    };

    allocator: *std.mem.Allocator,

    method: HttpMethod = HttpMethod.GET,
    uri: std.BoundedArray(u8, 8 * 1024) = std.BoundedArray(u8, MAX_URI_LEN).init(0) catch unreachable,
    http_version: std.BoundedArray(u8, 32) = std.BoundedArray(u8, 32).init(0) catch unreachable,
    // URL: protocol, domain, subsection, hash, query
    /// Headers
    headers: std.StringArrayHashMap(HttpHeader),
    /// Payload. Allocated on heap. After parse, it must be free'd
    maybe_payload: ?[]u8 = null,

    parse_state: ParseState = ParseState.expecting_request_line,

    fn addHeader(self: *@This(), header_buf: []const u8) !void {
        var key_scrap: [256]u8 = undefined;
        var col_pos = std.mem.indexOf(u8, header_buf, ":") orelse return error.InvalidHeaderFormat;
        var key = std.mem.trim(u8, header_buf[0..col_pos], " ");
        // std.mem.copy(u8, scrap[0..], key);
        var key_lc = std.ascii.lowerString(key_scrap[0..], key);
        var value = std.mem.trim(u8, header_buf[col_pos+1..], " "); // TODO: remove inner newlines
        debug("Added entry: {s}: {s}\n", .{key_lc, value});
        try self.headers.put(key_lc, try HttpHeader.create(key_lc, value));
    }

    fn getHeader(self: *@This(), header: []const u8) ?[]const u8 {
        debug("...: {s}\n", .{self.headers.get(header)});
        return "Dummy";
        // return self.headers.get(header).?.constSlice();
    }

    fn init(allocator: *std.mem.Allocator) HttpRequest {
        return .{
            .allocator = allocator,
            .headers = std.StringArrayHashMap(HttpHeader).init(allocator),
            // .uri = @TypeOf(@This().uri).init(0) catch unreachable,
        };
    }

    fn deinit(self: *HttpRequest) void {
        if (self.maybe_payload) |payload| {
            self.allocator.destroy(payload.ptr);
        }

        self.headers.deinit();
    }

    fn feedParser(self: *HttpRequest, buf_chunk: []const u8) !ParseState {
        const Token = struct {
            source_buf: []const u8,
            start: usize = 0,
            end: usize = 0,
            pub fn slice(_self: *@This()) []const u8 {
                return _self.source_buf[_self.start.._self.end];
            }
        };
        // Read through chunk, and parse out parts as far as possible
        // Always store point of last finished piece of information
        // How to keep remainder? Have an internal buffer which use for
        // scrap?
        // Or, since we kind of know what we are expecting to be parsing, we can keep an unfinished piece of this?
        //    Request-line? Header?, payload (only if Content-Length)?

        // start assuming that we get the entire header in one chunk...
        var tok = Token{
            .source_buf = buf_chunk,
        };
        var idx: usize = 0;
        while (idx < buf_chunk.len) : (idx += 1) {
            const c = buf_chunk[idx];
            switch (self.parse_state) {
                ////////////////////////////////////////////////////
                // Parsing request line
                ////////////////////////////////////////////////////
                .expecting_request_line => switch (c) {
                    // '\r' => { self.parse_state = .cr; },
                    'A'...'Z' => {
                        tok.start = idx;
                        self.parse_state = .getting_method;
                    },
                    else => {
                        return error.MalformedHeader;
                    },
                },
                .getting_method => switch (c) {
                    ' ' => {
                        tok.end = idx;
                        self.method = try HttpMethod.create(tok.slice());
                        self.parse_state = .getting_uri;
                        tok.start = idx + 1;
                        // TODO: Are there always only one space here?
                    },
                    else => {},
                },
                .getting_uri => switch (c) {
                    ' ' => {
                        tok.end = idx;
                        try self.uri.appendSlice(tok.slice());
                        self.parse_state = .getting_http_version;
                        tok.start = idx + 1;
                    },
                    else => {},
                },
                .getting_http_version => switch (c) {
                    '\r' => {
                        tok.end = idx;
                        try self.http_version.appendSlice(tok.slice());
                        self.parse_state = .expecting_headers;
                    },
                    else => {},
                },
                ////////////////////////////////////////////////////
                // Finished parsing request line
                ////////////////////////////////////////////////////
                // Parse headers
                //    Only store headers we care for?
                // Header starts at newline, and ends at next newline which is followed by a non-space character
                ////////////////////////////////////////////////////
                .expecting_headers => switch(c) {
                    //'a'...'z','A'...'Z' => {
                    '\n' => {
                        self.parse_state = .expecting_header_start;
                    },
                    else => {},
                },
                .expecting_header_start => switch(c) {
                    'a'...'z','A'...'Z' => {
                        self.parse_state = .parsing_header;
                        tok.start = idx;
                    },
                    else => {},
                },
                .parsing_header => switch(c) {
                    // Parse until newline+alpha
                    '\n' => {
                        self.parse_state = .parsing_header_got_nl;
                    },
                    else => {}
                },
                .parsing_header_got_nl => switch(c) {
                    '\r', '\n' => {
                        tok.end = idx-2;
                        try self.addHeader(tok.slice());
                        self.parse_state = .end_of_headers;
                    },
                    'a'...'z','A'...'Z' => {
                        // Got end of previous header, starting new
                        tok.end = idx-2;
                        try self.addHeader(tok.slice());
                        // debug("Got header: {s}\n", .{tok.slice()});
                        // Store header
                        // Continue parsing
                        self.parse_state = .expecting_header_start;
                    },
                    else => {}
                },

                ////////////////////////////////////////////////////
                // Finished parsing headers
                ////////////////////////////////////////////////////
                // Possibly parse body
                ////////////////////////////////////////////////////

                ////////////////////////////////////////////////////
                // Finished
                ////////////////////////////////////////////////////

                else => {},
            }
        }

        // const ParseState = enum {
        //     start,
        //     method,
        //     url,
        //     http_version,
        //     header_start,
        //     header,
        //     header_end,
        //     eof,
        // };
        return self.parse_state;
    }
};

test "HttpRequest" {
    var allocator = testing.allocator;

    var request = HttpRequest.init(allocator);
    defer request.deinit();

    var state = try request.feedParser("GET /index.html HTTP/1.1\r\nContent-Type: application/xml\r\n\r\n");
    debug("state: {s}\n", .{state});

    // try testing.expectEqualStrings("GET", request.method[0..]);
    try testing.expectEqual(HttpMethod.GET, request.method);
    try testing.expectEqualStrings("/index.html", request.uri.slice());
    try testing.expectEqualStrings("HTTP/1.1", request.http_version.slice());

    // try testing.expectEqualStrings("application/xml", request.getHeader("content-type").?);
    // try request.headers.put("key", try std.BoundedArray(u8, 8*1024).fromSlice("value"));

    // for(request.headers.keys()) |key| {
    //     if(request.headers.getKeyPtr(key.ptr.*)) |entry| {
    //         debug("key: {s} - {s}: {s}\n", .{key, entry.name, entry.value});
    //     }
    // }

    var it = request.headers.iterator();
    var maybe_value = it.next();
    while(maybe_value) |value| {
        // debug("* '{s}': '{s}'\n", .{request.headers.getKeyPtr(value.key_ptr.*), value.value_ptr.slice()});
        debug("* '{s}': '{s}'\n", .{ value.value_ptr.name.slice(), value.value_ptr.value.slice()});
        // debug("* {s}: {s}\n", .{header, request.headers.get(header).?.slice()});
        maybe_value = it.next();
    }
}

pub fn main() !void {
    // Initiate
    var server = std.net.StreamServer.init(.{});
    defer server.deinit();

    // Listen for requests
    try server.listen(std.net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, 8181));

    // loop:
    // Dispatch to thread
    var conn = try server.accept();
    // Read and parse request
    var read_buf: [1024]u8 = undefined;
    var len = try conn.stream.read(read_buf[0..]);
    debug("Got: {d} - {s}\n", .{ len, read_buf[0..len] });

    // Send response
    _ = try conn.stream.write("Out!\n");
}
