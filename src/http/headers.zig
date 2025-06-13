//! HTTP header utilities and common header definitions

const std = @import("std");
pub const HeaderName = struct {
    pub const CONTENT_TYPE = "Content-Type";
    pub const CONTENT_LENGTH = "Content-Length";
    pub const CONTENT_ENCODING = "Content-Encoding";
    pub const ACCEPT_ENCODING = "Accept-Encoding";
    pub const HOST = "Host";
    pub const USER_AGENT = "User-Agent";
    pub const AUTHORIZATION = "Authorization";
    pub const CACHE_CONTROL = "Cache-Control";
    pub const CONNECTION = "Connection";
};

pub const ContentType = struct {
    pub const TEXT_PLAIN = "text/plain";
    pub const TEXT_HTML = "text/html";
    pub const APPLICATION_JSON = "application/json";
    pub const APPLICATION_OCTET_STREAM = "application/octet-stream";
    pub const APPLICATION_FORM_URLENCODED = "application/x-www-form-urlencoded";
};

///Headers map that manages its own memmory
pub const ManagedHeadersMap = HeadersMap(std.BufMap);

///Headers map that does not manage its own memmory
pub const UnmanagedHeadersMap = HeadersMap(std.StringHashMap([]const u8));

pub fn HeadersMap(comptime T: type) type {
    if (!(@TypeOf(T) == std.StringHashMap([]const u8) or @TypeOf(T) != std.BufMap)) {
        @compileError("The header type can only be std.StringHashMap([]const u8) or std.BufMap");
    }
    return struct {
        raw_headers: T,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) HeadersMap(T) {
            return .{ .allocator = allocator, .raw_headers = .init(allocator) };
        }

        pub fn deinit(self: *HeadersMap(T)) void {
            self.raw_headers.deinit();
        }

        ///Initializes and parses headers from splitIterator
        pub fn parseHeaders(lines: *std.mem.SplitIterator(u8, .sequence), allocator: std.mem.Allocator) !HeadersMap(T) {
            var headers: HeadersMap(T) = .init(allocator);
            while (lines.next()) |line| {
                if (std.mem.eql(u8, line, "")) {
                    break;
                }

                if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                    const name = line[0..colon_pos];
                    const value = line[colon_pos + 2 ..];
                    try headers.raw_headers.put(name, value);
                }
            }

            return headers;
        }

        pub fn put(self: *HeadersMap(T), name: []const u8, value: []const u8) !void {
            if (self.get(name) == null) {
                try self.raw_headers.put(name, value);
            }
        }

        pub fn count(self: *HeadersMap(T)) usize {
            return self.raw_headers.count();
        }

        ///Checks if  header exists (case insensitive)
        pub fn contains(self: *const HeadersMap(T), name: []const u8) bool {
            return self.get(name) != null;
        }

        ///Gets header value by key (case insensitive)
        pub fn get(self: *const HeadersMap(T), name: []const u8) ?[]const u8 {
            if (self.raw_headers.get(name)) |value| {
                return value;
            }

            var iterator = self.raw_headers.iterator();
            while (iterator.next()) |entry| {
                if (std.ascii.eqlIgnoreCase(entry.key_ptr.*, name)) {
                    return entry.value_ptr.*;
                }
            }

            return null;
        }
    };
}

test "header parsing" {
    var lines = std.mem.splitSequence(u8, "Content-Type: text/plain\r\nContent-Length: 5\r\n\r\n", "\r\n");
    var headers = try HeadersMap(std.StringHashMap([]const u8)).parseHeaders(&lines, std.testing.allocator);
    defer headers.deinit();

    try std.testing.expectEqualStrings("text/plain", headers.get("Content-Type").?);
    try std.testing.expectEqualStrings("5", headers.get("Content-Length").?);
}

test "case insensitive header lookup" {
    var headers = HeadersMap(std.StringHashMap([]const u8)).init(std.testing.allocator);
    defer headers.deinit();

    try headers.put("Content-Type", "text/plain");

    try std.testing.expectEqualStrings("text/plain", headers.get("content-type").?);
    try std.testing.expectEqualStrings("text/plain", headers.get("CONTENT-TYPE").?);
}
