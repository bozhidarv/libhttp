const mem = std.mem;
const Io = std.Io;
const testing = std.testing;

const HeadersMap = @import("headers.zig").UnmanagedHeadersMap;
const Method = @import("method.zig").Method;
const Url = @import("url.zig");

const std = @import("std");

pub const Error = HeaderError || RequestLineError;

const HttpRequest = @This();

method: Method,
headers: HeadersMap,
url: Url,
version: []const u8,
allocator: mem.Allocator,
body_reader: ?*Io.Reader,

pub fn setUrlParams(self: *HttpRequest, params: *const std.array_list.Managed([]const u8)) void {
    self.url.params = params;
}

const HeaderError = error {InvalidHeader} || mem.Allocator.Error;

pub fn parseHeader(self: *HttpRequest, header_line: []const u8) HeaderError!void {
    var header_it = mem.splitSequence(u8, header_line, ": ");

    const header_name = header_it.next() orelse return HeaderError.InvalidHeader;
    const header_value = header_it.next() orelse return HeaderError.InvalidHeader;

    if (header_it.peek() != null) {
        return HeaderError.InvalidHeader;
    }

    try self.headers.put(header_name, header_value);
}

pub fn init(allocator: mem.Allocator) HttpRequest {
    return .{
        .method = undefined,
        .headers = .init(allocator),
        .url = undefined,
        .version = undefined,
        .allocator = allocator,
        .body_reader = null,
    };
}

const RequestLineError = error{InvalidRequestLine} || mem.Allocator.Error;

pub fn parseRequestLine(self: *HttpRequest, req_line: []const u8) RequestLineError!void {
    var req_it = mem.splitSequence(u8, req_line, " ");

    const http_method_str = req_it.next() orelse return RequestLineError.InvalidRequestLine;
    self.method = Method.fromString(http_method_str) orelse return RequestLineError.InvalidRequestLine;

    const url_str = req_it.next() orelse return RequestLineError.InvalidRequestLine;
    self.url = Url.init(url_str, &self.allocator);

    self.version = req_it.next() orelse return RequestLineError.InvalidRequestLine;
    self.version = mem.trim(u8, self.version, " \n\r");

    if (req_it.peek() != null) {
        return RequestLineError.InvalidRequestLine;
    }
}

pub fn deinit(self: *HttpRequest) void {
    self.headers.deinit();

    for (self.url.path.items) |path_item| {
        self.allocator.free(path_item);
    }

    self.url.path.deinit();
    self.url.query.deinit();
    self.allocator.free(self.version);
}

test "parseHeader" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const header_str = "Content-Type: application/json";

    var req: HttpRequest = .init(arena.allocator());

    try req.parseHeader(header_str);

    try testing.expect(req.headers.contains("Content-Type"));
}

test "parseHeader stores value" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try req.parseHeader("Content-Type: application/json");

    try testing.expectEqualStrings("application/json", req.headers.get("Content-Type").?);
}

test "parseHeader invalid - missing separator" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try testing.expectError(HeaderError.InvalidHeader, req.parseHeader("Content-Type"));
}

test "parseHeader invalid - multiple separators" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try testing.expectError(HeaderError.InvalidHeader, req.parseHeader("Content-Type: text/plain: extra"));
}

test "parseHeader case insensitive lookup" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try req.parseHeader("Authorization: Bearer token123");

    try testing.expectEqualStrings("Bearer token123", req.headers.get("authorization").?);
}

test "parseHeader multiple headers" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try req.parseHeader("Content-Type: text/plain");
    try req.parseHeader("Content-Length: 42");
    try req.parseHeader("Host: localhost:8080");

    try testing.expect(req.headers.count() == 3);
    try testing.expectEqualStrings("text/plain", req.headers.get("Content-Type").?);
    try testing.expectEqualStrings("42", req.headers.get("Content-Length").?);
    try testing.expectEqualStrings("localhost:8080", req.headers.get("Host").?);
}

test "parseRequestLine" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const req_str = "POST /api/users HTTP/1.1";

    var req: HttpRequest = .init(arena.allocator());

    try req.parseRequestLine(req_str);

    try testing.expect(req.method == .POST);
    try testing.expect(mem.eql(u8, req.version, "HTTP/1.1"));
}

test "parseRequestLine all methods" {
    const cases = .{
        .{ "GET /path HTTP/1.1", Method.GET },
        .{ "PUT /path HTTP/1.1", Method.PUT },
        .{ "DELETE /path HTTP/1.1", Method.DELETE },
        .{ "PATCH /path HTTP/1.1", Method.PATCH },
        .{ "HEAD /path HTTP/1.1", Method.HEAD },
        .{ "OPTIONS /path HTTP/1.1", Method.OPTIONS },
    };

    inline for (cases) |case| {
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();

        var req: HttpRequest = .init(arena.allocator());
        try req.parseRequestLine(case[0]);
        try testing.expect(req.method == case[1]);
    }
}

test "parseRequestLine parses url path" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try req.parseRequestLine("GET /api/users/123 HTTP/1.1");

    try testing.expect(req.url.path.items.len == 3);
    try testing.expectEqualStrings("api", req.url.path.items[0]);
    try testing.expectEqualStrings("users", req.url.path.items[1]);
    try testing.expectEqualStrings("123", req.url.path.items[2]);
}

test "parseRequestLine parses query params" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try req.parseRequestLine("GET /search?q=hello&page=2 HTTP/1.1");

    try testing.expect(req.url.query.count() == 2);
    try testing.expectEqualStrings("2", req.url.query.get("page").?);
}

test "parseRequestLine HTTP/1.0" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try req.parseRequestLine("GET / HTTP/1.0");

    try testing.expectEqualStrings("HTTP/1.0", req.version);
}

test "parseRequestLine invalid - missing version" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try testing.expectError(RequestLineError.InvalidRequestLine, req.parseRequestLine("GET /path"));
}

test "parseRequestLine invalid - unknown method" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try testing.expectError(RequestLineError.InvalidRequestLine, req.parseRequestLine("BREW /coffee HTTP/1.1"));
}

test "parseRequestLine invalid - too many parts" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var req: HttpRequest = .init(arena.allocator());
    try testing.expectError(RequestLineError.InvalidRequestLine, req.parseRequestLine("GET /path HTTP/1.1 extra"));
}

test "init_simple sets body_reader to null" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const req: HttpRequest = .init(arena.allocator());
    try testing.expect(req.body_reader == null);
}
