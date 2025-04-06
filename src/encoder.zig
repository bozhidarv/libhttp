const std = @import("std");
const gzip_compress = std.compress.gzip;

const Ecodings = @import("utils.zig").Encodings;

pub fn encode(data: []const u8, encoding: Ecodings, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    return switch (encoding) {
        .gzip => gzipEncode(data, allocator),
    };
}

const ReaderContext = struct {
    str_ptr: *[]const u8,
    pos: usize,
};

const ReaderError = error{};

fn readFn(context: *ReaderContext, buffer: []u8) anyerror!usize {
    const available_size: usize = context.str_ptr.*.len - context.pos;

    if (available_size == 0) {
        return 0;
    }

    const read_size = @min(buffer.len, available_size);

    const end_pos = read_size + context.pos;

    std.mem.copyForwards(u8, buffer, context.str_ptr.*[context.pos..end_pos]);
    context.pos = end_pos;

    return read_size;
}

fn gzipEncode(data: []const u8, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var ctx: ReaderContext = .{
        .pos = 0,
        .str_ptr = @constCast(&data),
    };

    const reader: std.io.GenericReader(*ReaderContext, anyerror, readFn) = .{
        .context = &ctx,
    };

    var arr: std.ArrayList(u8) = .init(allocator);

    try gzip_compress.compress(reader, arr.writer(), .{});

    return arr;
}

fn gzipDecode(data: []const u8, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var ctx: ReaderContext = .{
        .pos = 0,
        .str_ptr = @constCast(&data),
    };

    const reader: std.io.GenericReader(*ReaderContext, anyerror, readFn) = .{
        .context = &ctx,
    };

    var arr: std.ArrayList(u8) = .init(allocator);

    try gzip_compress.decompress(reader, arr.writer());

    return arr;
}

test readFn {
    var data: []const u8 = "HAIFOADGHADPOGASIHFAPSOIGHFSHPFOIHIADGAGOUJIAHSGFASHPFGHPOASGHUASDGHOPASHUPFHAUSGHUPAGHUPSGFHUPOASG";

    var ctx: ReaderContext = .{
        .pos = 0,
        .str_ptr = @constCast(&data),
    };

    const reader: std.io.GenericReader(*ReaderContext, anyerror, readFn) = .{
        .context = &ctx,
    };

    var buffer: [3]u8 = undefined;

    var arr: std.ArrayList(u8) = .init(std.testing.allocator);
    defer arr.deinit();

    while (true) {
        const len = try reader.read(&buffer);
        if (len == 0) {
            break;
        }

        try arr.appendSlice(buffer[0..len]);
    }

    try std.testing.expect(std.mem.eql(u8, data, arr.items));
}

test gzipEncode {
    const data: []const u8 = "HAIFOADGHADPOGASIHFAPSOIGHFSHPFOIHIADGAGOUJIAHSGFASHPFGHPOASGHUASDGHOPASHUPFHAUSGHUPAGHUPSGFHUPOASG";

    const compressed_arr = try gzipEncode(data, std.testing.allocator);
    defer compressed_arr.deinit();

    const norm_arr = try gzipDecode(@as([]const u8, compressed_arr.items), std.testing.allocator);
    defer norm_arr.deinit();

    try std.testing.expect(std.mem.eql(u8, norm_arr.items, data));
}
