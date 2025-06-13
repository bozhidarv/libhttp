const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const testing = std.testing;

const Status = @import("status.zig").Status;
const Encodings = @import("utils.zig").Encodings;
const headers_utils = @import("headers.zig");
const HeadersMap = headers_utils.ManagedHeadersMap;
const encode = @import("encoder.zig").encode;

pub const HttpResponse = @This();

status: Status,
headers: HeadersMap,
body: []u8,
allocator: mem.Allocator,

pub fn init(allocator: mem.Allocator) HttpResponse {
    return .{
        .status = Status.internal_server_error,
        .headers = .init(allocator),
        .body = "",
        .allocator = allocator,
    };
}

pub fn setBody(self: *HttpResponse, body: []const u8) !void {
    self.allocator.free(self.body);

    const encoding_str = self.headers.get("Content-Encoding");

    if (encoding_str != null) {
        const encoding = std.meta.stringToEnum(Encodings, encoding_str.?) orelse unreachable;
        const encoded_body = try encode(body, encoding, self.allocator);
        defer encoded_body.deinit();

        self.body = try self.allocator.alloc(u8, encoded_body.items.len);
        @memcpy(self.body, encoded_body.items);
    } else {
        self.body = try self.allocator.alloc(u8, body.len);
        @memcpy(self.body, body);
    }

    const content_length_str = try fmt.allocPrint(self.allocator, "{}", .{self.body.len});
    defer self.allocator.free(content_length_str);

    try self.headers.put("Content-Length", content_length_str);
}

pub fn sendText(self: *HttpResponse, body: []const u8) !void {
    try self.headers.put("Content-Type", "text/plain");
    try self.setBody(body);
}

fn readEntireFile(file_path: []const u8, allocator: mem.Allocator) ![]u8 {
    const file = try std.fs.openFileAbsolute(file_path, .{ .mode = .read_only });
    defer file.close();

    var buffered_reader = std.io.bufferedReader(file.reader());
    var reader = buffered_reader.reader();

    return try reader.readAllAlloc(allocator, std.math.maxInt(usize));
}

pub fn sendFile(self: *HttpResponse, file_name: []const u8) !void {
    const file_contents = try readEntireFile(file_name, self.allocator);
    defer self.allocator.free(file_contents);

    try self.headers.put(headers_utils.HeaderName.CONTENT_TYPE, headers_utils.ContentType.APPLICATION_OCTET_STREAM);

    try self.setBody(file_contents);
}

pub fn serialize(self: *HttpResponse) ![]const u8 {
    var headers_it = self.headers.raw_headers.iterator();

    var list: std.ArrayList([]const u8) = .init(self.allocator);
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

    const serialized_res = try fmt.allocPrint(self.allocator, "HTTP/1.1 {d} {s}\r\n{s}\r\n\r\n{s}", .{ @intFromEnum(self.status), self.status.reasonPhrase(), headers_str, self.body });

    return serialized_res[0..];
}

pub fn setEncoding(self: *HttpResponse, client_encoding: []const u8) !void {
    var encoding_it = mem.splitSequence(u8, client_encoding, ", ");

    while (encoding_it.next()) |encoding| {
        const parsed_encoding = std.meta.stringToEnum(Encodings, encoding);
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
    var response1: HttpResponse = .init(testing.allocator);
    defer response1.deinit();

    response1.status = Status.ok;
    try response1.headers.put("Content-Type", "text/plain");

    const response_ser1 = try response1.serialize();
    defer response1.allocator.free(response_ser1);

    try testing.expect(mem.eql(u8, response_ser1, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n"));

    var response2: HttpResponse = .init(testing.allocator);
    defer response2.deinit();

    response2.status = Status.ok;
    try response2.headers.put("Content-Type", "text/plain");

    try response2.setBody("abc");

    const response_ser2 = try response2.serialize();

    defer response2.allocator.free(response_ser2);

    try testing.expect(mem.eql(u8, response_ser2, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 3\r\n\r\nabc"));
}
