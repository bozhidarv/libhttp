const std = @import("std");

pub const InMemmoryReader = std.io.GenericReader(*ReaderContext, anyerror, readFn);

pub const ReaderContext = struct {
    str_ptr: *[]const u8,
    pos: usize,
};

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
