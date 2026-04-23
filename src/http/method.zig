//! HTTP method definitions and utilities

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Standard HTTP methods as defined in RFC 7231
pub const Method = enum {
    GET,
    HEAD,
    POST,
    PUT,
    DELETE,
    CONNECT,
    OPTIONS,
    TRACE,
    PATCH,

    /// Convert string to HTTP method
    pub fn fromString(str: []const u8) ?Method { 
        const method_len: usize = @min(str.len, 7);
        var str_upper: [7]u8 = undefined;
        for (str, 0..method_len) |ch, i| {
            str_upper[i] = std.ascii.toUpper(ch);
        }
        const method = std.meta.stringToEnum(Method, str_upper[0..method_len]);
        return method;
    }

    /// Convert HTTP method to string
    pub fn toString(self: Method) []const u8 {
        return @tagName(self);
    }

    /// Check if method typically has a request body
    pub fn hasBody(self: Method) bool {
        return switch (self) {
            .POST, .PUT, .PATCH => true,
            else => false,
        };
    }

    /// Check if method is safe (read-only)
    pub fn isSafe(self: Method) bool {
        return switch (self) {
            .GET, .HEAD, .OPTIONS, .TRACE => true,
            else => false,
        };
    }

    /// Check if method is idempotent
    pub fn isIdempotent(self: Method) bool {
        return switch (self) {
            .GET, .HEAD, .PUT, .DELETE, .OPTIONS, .TRACE => true,
            else => false,
        };
    }
};

test "method from string" {
    try std.testing.expect(Method.fromString("GET") == .GET);
    try std.testing.expect(Method.fromString("POST") == .POST);
    try std.testing.expect(Method.fromString("INVALID") == null);
}

test "method properties" {
    try std.testing.expect(Method.GET.isSafe());
    try std.testing.expect(!Method.POST.isSafe());
    try std.testing.expect(Method.POST.hasBody());
    try std.testing.expect(!Method.GET.hasBody());
}
