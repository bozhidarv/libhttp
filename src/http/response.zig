const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;
const Io = std.Io;

const Status = @import("status.zig").Status;
const headers_utils = @import("headers.zig");
const HeadersMap = headers_utils.ManagedHeadersMap;
const encoder = @import("../encoding/encoder.zig");

pub const HttpResponse = @This();

status: Status,
headers: HeadersMap,
body: []u8,
allocator: mem.Allocator,
io: Io, 

pub fn init(allocator: mem.Allocator, io: Io) HttpResponse {
    return .{
        .status = Status.internal_server_error,
        .headers = .init(allocator),
        .body = "",
        .allocator = allocator,
        .io = io
    };
}

pub fn setBody(self: *HttpResponse, body: []const u8) !void {
    self.allocator.free(self.body);

    const encoding_str = self.headers.get("Content-Encoding");

    if (encoding_str != null) {
        const encoding = std.meta.stringToEnum(encoder.Encoding, encoding_str.?) orelse unreachable;
        const encoded_body = try encoder.encode(body, encoding, self.allocator);
        defer encoded_body.deinit();

        self.body = try self.allocator.alloc(u8, encoded_body.items.len);
        @memcpy(self.body, encoded_body.items);
    } else {
        self.body = try self.allocator.alloc(u8, body.len);
        @memcpy(self.body, body);
    }
}

pub fn sendText(self: *HttpResponse, body: []const u8) !void {
    try self.headers.put("Content-Type", "text/plain");
    try self.setBody(body);
}

fn readEntireFile(io: Io, file_path: []const u8, allocator: mem.Allocator) ![]u8 {
    const file = try std.Io.Dir.openFileAbsolute(io, file_path, .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [2048]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    var reader = &file_reader.interface;

    var alloc_writer: Io.Writer.Allocating = .init(allocator);
    _ = try reader.streamRemaining(&alloc_writer.writer);

    return try alloc_writer.toOwnedSlice();
}

pub fn sendFile(self: *HttpResponse, file_name: []const u8) !void {
    const file_contents = try readEntireFile(self.io, file_name, self.allocator);
    defer self.allocator.free(file_contents);

    try self.headers.put(headers_utils.HeaderName.CONTENT_TYPE, headers_utils.ContentType.APPLICATION_OCTET_STREAM);

    try self.setBody(file_contents);
}

pub fn serialize(self: *HttpResponse) ![]const u8 {
    const content_length_str = try fmt.allocPrint(self.allocator, "{}", .{self.body.len});
    defer self.allocator.free(content_length_str);
    try self.headers.put("Content-Length", content_length_str);

    var headers_it = self.headers.raw_headers.iterator();

    var list: std.array_list.Managed([]const u8) = .init(self.allocator);
    defer {
        for (list.items) |ptr| {
            self.allocator.free(ptr);
        }
        list.deinit();
    }

    while (headers_it.next()) |entry| {
        const curr_header = try fmt.allocPrint(self.allocator, "{s}: {s}", .{ entry.key_ptr.*, entry.value_ptr.* });
        try list.append(curr_header);
    }

    const headers_str: []const u8 = try mem.join(self.allocator, "\r\n", list.items);
    defer self.allocator.free(headers_str);

    const additionalRN: []const u8 = if (headers_str.len == 0) "" else "\r\n";

    const serialized_res = try fmt.allocPrint(self.allocator, "HTTP/1.1 {d} {s}\r\n{s}{s}\r\n{s}", .{ @intFromEnum(self.status), self.status.reasonPhrase(), headers_str, additionalRN, self.body });

    std.debug.assert(serialized_res[0] == 'H');

    return serialized_res[0..];
}

pub fn setEncoding(self: *HttpResponse, client_encoding: []const u8) !void {
    var encoding_it = mem.splitSequence(u8, client_encoding, ", ");

    while (encoding_it.next()) |encoding| {
        const parsed_encoding = std.meta.stringToEnum(encoder.Encoding, encoding);
        if (parsed_encoding != null) {
            try self.headers.put("Content-Encoding", encoding);
            break;
        }
    }
}

pub fn deinit(self: *HttpResponse) void {
    self.headers.deinit();
    self.allocator.free(self.body);
}

test serialize {
    var response1: HttpResponse = .init(testing.allocator, testing.io);
    defer response1.deinit();

    response1.status = Status.ok;
    try response1.headers.put("Content-Type", "text/plain");

    const response_ser1 = try response1.serialize();
    defer response1.allocator.free(response_ser1);

    // std.debug.print("{s}", .{response_ser1});

    try testing.expect(mem.eql(u8, response_ser1, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 0\r\n\r\n"));

    var response2: HttpResponse = .init(testing.allocator, testing.io);
    defer response2.deinit();

    response2.status = Status.ok;
    try response2.headers.put("Content-Type", "text/plain");

    try response2.setBody("abc");

    const response_ser2 = try response2.serialize();

    defer response2.allocator.free(response_ser2);

    try testing.expect(mem.eql(u8, response_ser2, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 3\r\n\r\nabc"));
}
