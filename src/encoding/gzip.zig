const std = @import("std");
const gzip_compress = std.compress.gzip;

const reader_utils = @import("../utils/io_utils.zig");

pub fn encode(data: []const u8, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var ctx = reader_utils.ReaderContext{
        .pos = 0,
        .str_ptr = @constCast(&data),
    };

    const reader:  reader_utils.InMemmoryReader = .{
        .context = &ctx,
    };

    var arr: std.ArrayList(u8) = .init(allocator);

    try gzip_compress.compress(reader, arr.writer(), .{});

    return arr;
}

pub fn decode(data: []const u8, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var ctx = reader_utils.ReaderContext{
        .pos = 0,
        .str_ptr = @constCast(&data),
    };

    const reader: reader_utils.InMemmoryReader = .{
        .context = &ctx,
    };

    var arr: std.ArrayList(u8) = .init(allocator);

    try gzip_compress.decompress(reader, arr.writer());

    return arr;
}

test encode {
    const data: []const u8 = "HAIFOADGHADPOGASIHFAPSOIGHFSHPFOIHIADGAGOUJIAHSGFASHPFGHPOASGHUASDGHOPASHUPFHAUSGHUPAGHUPSGFHUPOASG";

    const compressed_arr = try encode(data, std.testing.allocator);
    defer compressed_arr.deinit();

    const norm_arr = try decode(@as([]const u8, compressed_arr.items), std.testing.allocator);
    defer norm_arr.deinit();

    try std.testing.expect(std.mem.eql(u8, norm_arr.items, data));
}
