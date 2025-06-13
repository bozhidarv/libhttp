const std = @import("std");

const InMemmoryReader = @import("../utils/inMemmoryReader.zig").InMemmoryReader;
const gzip = @import("gzip.zig");

pub const Encoding = enum {
    gzip,
    // deflate,  // Future support
    // brotli,   // Future support
    
    /// Parse encoding from string
    pub fn fromString(str: []const u8) ?Encoding {
        return std.meta.stringToEnum(Encoding, str);
    }
    
    /// Get encoding name as string
    pub fn toString(self: Encoding) []const u8 {
        return @tagName(self);
    }
};

pub fn encode(data: []const u8, encoding: Encoding, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    return switch (encoding) {
        .gzip => gzip.encode(data, allocator),
    };
}

pub fn decode(data: []const u8, encoding: Encoding, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    return switch (encoding) {
        .gzip => gzip.decode(data, allocator),
    };
}
