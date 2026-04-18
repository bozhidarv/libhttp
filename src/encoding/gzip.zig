const std = @import("std");
const mem = std.mem;
const flate = std.compress.flate;

pub fn encode(data: []const u8, allocator: mem.Allocator) !std.array_list.Managed(u8) {
    var arr: std.ArrayList(u8) = try .initCapacity(allocator, 12);
    var allocating: std.Io.Writer.Allocating = .fromArrayList(allocator, &arr);

    var buf: [flate.max_window_len]u8 = undefined;
    var compressor = try flate.Compress.init(&allocating.writer, &buf, .gzip, .default);
    try compressor.writer.writeAll(data);
    try compressor.finish();

    var out_arr = allocating.toArrayList();
    const out_arr_managed = out_arr.toManaged(allocator);

    return out_arr_managed;
}

pub fn decode(data: []const u8, allocator: mem.Allocator) !std.array_list.Managed(u8) {
    var reader: std.Io.Reader = .fixed(data);

    var buf: [flate.max_window_len]u8 = undefined;
    var decompressor = flate.Decompress.init(&reader, .gzip, &buf);

    var arr: std.ArrayList(u8) = .empty;
    try decompressor.reader.appendRemainingUnlimited(allocator, &arr);

    return arr.toManaged(allocator);
}

test encode {
    const data: []const u8 = "HAIFOADGHADPOGASIHFAPSOIGHFSHPFOIHIADGAGOUJIAHSGFASHPFGHPOASGHUASDGHOPASHUPFHAUSGHUPAGHUPSGFHUPOASG";

    const compressed_arr = try encode(data, std.testing.allocator);
    defer compressed_arr.deinit();

    const norm_arr = try decode(@as([]const u8, compressed_arr.items), std.testing.allocator);
    defer norm_arr.deinit();


    // std.debug.print("{s}\n{s}", .{data, norm_arr.items});

    try std.testing.expect(std.mem.eql(u8, norm_arr.items, data));
}
