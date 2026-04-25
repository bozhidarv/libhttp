//! HTTP header utilities and common header definitions

const std = @import("std");
const mem = std.mem;

pub const Name = struct {
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

        pub fn put(self: *HeadersMap(T), name: []const u8, value: []const u8) mem.Allocator.Error!void {
            if (self.get(name) == null) {
                try self.raw_headers.put(name, value);
            }
        }

        pub fn count(self: *HeadersMap(T)) usize {
            return self.raw_headers.count();
        }

        pub fn contains(self: *const HeadersMap(T), name: []const u8) bool {
            return self.get(name) != null;
        }

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

        pub fn getInt(self: *const HeadersMap(T), comptime IntT: type, name: []const u8) (std.fmt.ParseIntError || error{InvalidType})!?IntT {
            switch (@typeInfo(IntT)) {
                .int => {
                    const value = self.get(name) orelse return null;
                    return try std.fmt.parseInt(IntT, value, 10);
                },
                else => return error.InvalidType
            }
        }

        pub fn getFloat(self: *const HeadersMap(T), comptime FloatT: type, name: []const u8) (std.fmt.ParseFloatError || error{InvalidType})!?FloatT {
            switch (@typeInfo(FloatT)) {
                .float => {
                    const value = self.get(name) orelse return null;
                    return try std.fmt.parseFloat(FloatT, value);
                },
                else => return error.InvalidType
            }
        }
    };
}

test "case insensitive header lookup" {
    var headers = HeadersMap(std.StringHashMap([]const u8)).init(std.testing.allocator);
    defer headers.deinit();

    try headers.put("Content-Type", "text/plain");

    try std.testing.expectEqualStrings("text/plain", headers.get("content-type").?);
    try std.testing.expectEqualStrings("text/plain", headers.get("CONTENT-TYPE").?);
}

test "getInt functionality" {
    var headers = HeadersMap(std.StringHashMap([]const u8)).init(std.testing.allocator);
    defer headers.deinit();

    try headers.put("Content-Length", "1024");
    try headers.put("Negative-Value", "-42");
    try headers.put("Invalid-Value", "not_a_number");

    // Valid positive integer
    const length = try headers.getInt(usize, "Content-Length");
    try std.testing.expectEqual(@as(usize, 1024), length.?);

    // Valid negative integer
    const negative = try headers.getInt(i32, "Negative-Value");
    try std.testing.expectEqual(@as(i32, -42), negative.?);

    // Missing header
    const missing = try headers.getInt(usize, "Missing-Header");
    try std.testing.expectEqual(@as(?usize, null), missing);

    // Invalid character in integer
    const err = headers.getInt(usize, "Invalid-Value");
    try std.testing.expectError(error.InvalidCharacter, err);

    // Invalid type (non-integer)
    const type_err = headers.getInt(f32, "Content-Length");
    try std.testing.expectError(error.InvalidType, type_err);
}

test "getFloat functionality" {
    var headers = HeadersMap(std.StringHashMap([]const u8)).init(std.testing.allocator);
    defer headers.deinit();

    try headers.put("Content-Length", "1024");
    try headers.put("Negative-Value", "-42.43");
    try headers.put("Invalid-Value", "not_a_number");

    // Valid positive integer
    const length = try headers.getFloat(f64, "Content-Length");
    try std.testing.expectEqual(@as(f64, 1024.0), length.?);

    // Valid negative integer
    const negative = try headers.getFloat(f32, "Negative-Value");
    try std.testing.expectEqual(@as(f32, -42.43), negative.?);

    // Missing header
    const missing = try headers.getFloat(f64, "Missing-Header");
    try std.testing.expectEqual(@as(?f64, null), missing);

    // Invalid character in integer
    const err = headers.getFloat(f64, "Invalid-Value");
    try std.testing.expectError(error.InvalidCharacter, err);

    // Invalid type (non-integer)
    const type_err = headers.getFloat(i32, "Content-Length");
    try std.testing.expectError(error.InvalidType, type_err);
}
