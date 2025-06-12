const std = @import("std");
const Method = @import("method.zig").Method;
const mem = std.mem;

pub const HttpError = error{
    ParsingError,
};

pub const HttpRequest = @This();

method: Method,
headers: std.StringHashMap([]const u8),
url: Url,
version: []const u8,
allocator: mem.Allocator,
raw_request: []const u8,
body: ?[]const u8,

pub const Url = struct {
    raw_url: []const u8,
    path: std.ArrayList([]const u8),
    query: std.StringHashMap([]const u8),
    params: ?*const std.ArrayList([]const u8),
};

fn parseHeaders(iterator: *std.mem.SplitIterator(u8, .sequence), allocator: std.mem.Allocator) !std.StringHashMap([]const u8) {
    var header_map = std.StringHashMap([]const u8).init(allocator);
    while (iterator.next()) |header| {
        if (std.mem.eql(u8, header, "")) {
            break;
        }
        var header_it = mem.splitSequence(u8, header, ": ");
        const key = header_it.next() orelse break;
        const value = header_it.next() orelse break;
        try header_map.put(key, value);
    }

    return header_map;
}

fn parseUrl(raw_url: []const u8, host: ?[]const u8, allocator: *const mem.Allocator) !Url {
    var url = raw_url[0..];

    const startIdx = try trimUnnecessaryUrlInfo(url, host);
    url = url[startIdx..];

    const query_start_idx = mem.indexOf(u8, url, "?") orelse url.len;

    var path_str = url[0..query_start_idx];

    var query_params: std.StringHashMap([]const u8) = .init(allocator.*);
    if (query_start_idx < url.len) {
        try parseQueryParams(url[query_start_idx..], &query_params);
    }

    var path_arr: std.ArrayList([]const u8) = .init(allocator.*);

    var path_it = mem.splitSequence(u8, path_str[1..], "/");

    while (path_it.next()) |path| {
        try path_arr.append(path);
    }

    return .{
        .raw_url = raw_url,
        .path = path_arr,
        .query = query_params,
        .params = null,
    };
}

fn trimUnnecessaryUrlInfo(url: []const u8, host: ?[]const u8) !usize {
    var new_start_idx: usize = 0;
    if (mem.startsWith(u8, url, "http")) {
        if (url[4] == 's') {
            new_start_idx += 8;
        } else if (url[4] == ':') {
            new_start_idx += 7;
        } else {
            return HttpError.ParsingError;
        }

        if (!mem.startsWith(u8, url[new_start_idx..], host.?)) {
            return HttpError.ParsingError;
        }

        new_start_idx += host.?.len + 1;
    }
    return new_start_idx;
}

fn parseQueryParams(url: []const u8, query_params: *std.StringHashMap([]const u8)) !void {
    var query_it = mem.splitSequence(u8, url, "&");
    while (query_it.next()) |query_raw| {
        var query_split = mem.splitSequence(u8, query_raw, "=");

        const key = query_split.next() orelse break;
        const value = query_split.next() orelse break;

        try query_params.put(key, value);
    }
}

pub fn setUrlParams(self: *HttpRequest, params: *const std.ArrayList([]const u8)) void {
    self.url.params = params;
}

pub fn init(req: []const u8, allocator: mem.Allocator) !HttpRequest {
    const req_copy = try allocator.alloc(u8, req.len);
    @memcpy(req_copy, req);

    var it = mem.splitSequence(u8, req_copy, "\r\n");

    const req_line = it.first();

    var req_it = mem.splitSequence(u8, req_line, " ");

    var headers = try parseHeaders(&it, allocator);

    var req_part = req_it.next() orelse return HttpError.ParsingError;

    const method = try Method.fromString(req_part, allocator) orelse return HttpError.ParsingError;

    req_part = req_it.next() orelse return HttpError.ParsingError;

    const host = headers.get("Host");
    const url = try parseUrl(req_part, host, &allocator);

    req_part = req_it.next() orelse return HttpError.ParsingError;

    const httpVersion = req_part;
    var body: ?[]const u8 = null;

    const length_str = headers.get("Content-Length");
    if (headers.contains("Content-Type") and length_str != null and it.index != null) {
        const length = try std.fmt.parseInt(usize, length_str.?, 10);
        body = req[it.index.? .. it.index.? + length];
    }

    return .{
        .method = method,
        .headers = headers,
        .url = url,
        .version = httpVersion,
        .allocator = allocator,
        .raw_request = req_copy,
        .body = body,
    };
}

pub fn deinit(self: *HttpRequest) void {
    self.headers.deinit();

    for (self.url.path.items) |path_item| {
        self.allocator.free(path_item);
    }

    self.url.path.deinit();
    self.url.query.deinit();
    self.allocator.free(self.raw_request);
    self.allocator.free(self.version);
}

test parseUrl {
    var url = try HttpRequest.parseUrl("/echo/name", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 0);

    url.query.deinit();
    url.path.deinit();

    url = try HttpRequest.parseUrl("http://127.0.0.1:8080/echo/name", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 0);

    url.query.deinit();
    url.path.deinit();

    url = try HttpRequest.parseUrl("https://127.0.0.1:8080/echo/name", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 0);

    url.query.deinit();
    url.path.deinit();

    url = try HttpRequest.parseUrl("/echo/name?name=fffff&animal=ferret&color=purple", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 3);

    url.query.deinit();
    url.path.deinit();

    url = try HttpRequest.parseUrl("/echo/name?name=fffff&question=\"ajja?\"", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 2);

    try std.testing.expect(url.query.get("question") != null);
    const answer = url.query.get("question");
    try std.testing.expect(mem.eql(u8, answer.?, "\"ajja?\""));

    url.query.deinit();
    url.path.deinit();
}

test parseHeaders {
    var it = mem.splitSequence(u8, "Host: localhost:4221\r\nUser-Agent: curl/7.64.1\r\nAccept: */*\r\n\r\n", "\r\n");
    var headers = try HttpRequest.parseHeaders(&it, std.testing.allocator);

    try std.testing.expect(headers.count() == 3);
    try std.testing.expect(mem.eql(u8, headers.get("Host").?, "localhost:4221"));

    headers.deinit();

    it = mem.splitSequence(u8, "Host: example.com\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 27\r\n\r\nfield1=value1&field2=value2", "\r\n");

    headers = try HttpRequest.parseHeaders(&it, std.testing.allocator);

    try std.testing.expect(headers.count() == 3);
    try std.testing.expect(mem.eql(u8, headers.get("Content-Type").?, "application/x-www-form-urlencoded"));
    try std.testing.expect(mem.eql(u8, headers.get("Host").?, "example.com"));
    try std.testing.expect(mem.eql(u8, headers.get("Content-Length").?, "27"));

    headers.deinit();
}
