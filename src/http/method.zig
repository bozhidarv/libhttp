//! HTTP method definitions and utilities

const std = @import("std");

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
    pub fn fromString(str: []const u8, alloc: std.mem.Allocator) !?Method { 
        var strUpper = try alloc.alloc(u8, str.len);
        defer alloc.free(strUpper);
        for (str, 0..) |ch, i| {
            strUpper[i] = std.ascii.toUpper(ch);
        }
        const method = std.meta.stringToEnum(Method, strUpper);
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
    try std.testing.expect(try Method.fromString("GET", std.testing.allocator) == .GET);
    try std.testing.expect(try Method.fromString("POST", std.testing.allocator) == .POST);
    try std.testing.expect(try Method.fromString("INVALID", std.testing.allocator) == null);
}

test "method properties" {
    try std.testing.expect(Method.GET.isSafe());
    try std.testing.expect(!Method.POST.isSafe());
    try std.testing.expect(Method.POST.hasBody());
    try std.testing.expect(!Method.GET.hasBody());
}
