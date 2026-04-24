const std = @import("std");
const mem = std.mem;
const slog = std.log;

pub const ParseError = error{ InvalidUrl, InvalidScheme, InvalidHost, MissingHost } || mem.Allocator.Error;

raw_url: []const u8,
path: std.array_list.Managed([]const u8),
query: std.StringHashMap([]const u8),
params: ?*const std.array_list.Managed([]const u8),

const Url = @This();

pub fn init(url_str: []const u8, allocator: *const mem.Allocator) Url {
    return .{
        .raw_url = url_str,
        .path = .init(allocator.*),
        .query = .init(allocator.*),
        .params = null,
    };
}

pub fn parse(self: *Url, host: ?[]const u8) ParseError!void {
    var url = self.raw_url[0..];

    const start_idx = try trimUnnecessaryUrlInfo(url, host);
    url = url[start_idx..];

    const query_start_idx = mem.indexOf(u8, url, "?") orelse url.len;

    if (query_start_idx < url.len) {
        // Skip the '?' character for query params
        try parseQueryParams(url[query_start_idx + 1 ..], &self.query);
    }

    var path_str = url[0..query_start_idx];

    // Ensure we safely skip a leading slash without going out of bounds
    if (path_str.len > 0 and path_str[0] == '/') {
        path_str = path_str[1..];
    }
    
    if (path_str.len > 0) {
        var path_it = mem.splitSequence(u8, path_str, "/");

        while (path_it.next()) |path| {
            try self.path.append(path);
        }
    }
}

pub fn initParse(raw_url: []const u8, host: ?[]const u8, allocator: *const mem.Allocator) ParseError!Url {
    var url: Url = .init(raw_url, allocator);
    try url.parse(host);

    return url;
}

fn trimUnnecessaryUrlInfo(url: []const u8, host: ?[]const u8) ParseError!usize {
    var new_start_idx: usize = 0;
    const is_url_absolute = mem.startsWith(u8, url, "http");
    if (is_url_absolute and host == null) {
        slog.warn("Url is absolute and there is no host header", .{});
        return ParseError.MissingHost;
    }

    if (!is_url_absolute) {
        return new_start_idx;
    }

    if (url[4] == 's') {
        new_start_idx += 8;
    } else if (url[4] == ':') {
        new_start_idx += 7;
    } else {
        return ParseError.InvalidScheme;
    }

    if (!mem.startsWith(u8, url[new_start_idx..], host.?)) {
        return ParseError.InvalidHost;
    }

    new_start_idx += host.?.len;

    return new_start_idx;
}

fn parseQueryParams(url: []const u8, query_params: *std.StringHashMap([]const u8)) mem.Allocator.Error!void {
    if (url.len == 0) return;
    var query_it = mem.splitSequence(u8, url, "&");
    while (query_it.next()) |query_raw| {
        var query_split = mem.splitSequence(u8, query_raw, "=");

        const key = query_split.next() orelse break;
        const value = query_split.next() orelse "";

        try query_params.put(key, value);
    }
}

test "init" {
    var url = Url.init("/test/path", &std.testing.allocator);
    try std.testing.expectEqualStrings("/test/path", url.raw_url);
    try std.testing.expectEqual(@as(usize, 0), url.path.items.len);
    try std.testing.expectEqual(@as(u32, 0), url.query.count());
    try std.testing.expect(url.params == null);
    url.path.deinit();
    url.query.deinit();
}

test "parse" {
    var url = Url.init("/api/v1/users?limit=10&offset=20", &std.testing.allocator);
    defer url.path.deinit();
    defer url.query.deinit();
    
    try url.parse(null);
    
    try std.testing.expectEqual(@as(usize, 3), url.path.items.len);
    try std.testing.expectEqualStrings("api", url.path.items[0]);
    try std.testing.expectEqualStrings("v1", url.path.items[1]);
    try std.testing.expectEqualStrings("users", url.path.items[2]);
    
    try std.testing.expectEqual(@as(u32, 2), url.query.count());
    try std.testing.expectEqualStrings("10", url.query.get("limit").?);
    try std.testing.expectEqualStrings("20", url.query.get("offset").?);
}

test "trimUnnecessaryUrlInfo" {
    // Relative URL
    var idx = try trimUnnecessaryUrlInfo("/foo/bar", null);
    try std.testing.expectEqual(@as(usize, 0), idx);

    // Absolute HTTP URL
    idx = try trimUnnecessaryUrlInfo("http://example.com/foo/bar", "example.com");
    try std.testing.expectEqual(@as(usize, 18), idx); // 7 ("http://") + 11 ("example.com") = 18

    // Absolute HTTPS URL
    idx = try trimUnnecessaryUrlInfo("https://example.com/api", "example.com");
    try std.testing.expectEqual(@as(usize, 19), idx); // 8 ("https://") + 11 = 19

    // Absolute URL missing host
    try std.testing.expectError(ParseError.MissingHost, trimUnnecessaryUrlInfo("http://example.com", null));

    // Absolute URL with mismatched host
    try std.testing.expectError(ParseError.InvalidHost, trimUnnecessaryUrlInfo("http://example.com/api", "wrong.com"));
}

test "parseQueryParams" {
    var query = std.StringHashMap([]const u8).init(std.testing.allocator);
    defer query.deinit();

    // Standard params
    try parseQueryParams("name=bob&age=30", &query);
    try std.testing.expectEqualStrings("bob", query.get("name").?);
    try std.testing.expectEqualStrings("30", query.get("age").?);

    query.clearRetainingCapacity();

    // Empty value
    try parseQueryParams("flag=&other=1", &query);
    try std.testing.expectEqualStrings("", query.get("flag").?);
    try std.testing.expectEqualStrings("1", query.get("other").?);
    
    query.clearRetainingCapacity();
    
    // Empty string shouldn't crash
    try parseQueryParams("", &query);
    try std.testing.expectEqual(@as(u32, 0), query.count());
}

test "initParse" {
    var url = try initParse("/echo/name", "127.0.0.1:8080", &std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), url.path.items.len);
    try std.testing.expectEqualStrings("echo", url.path.items[0]);
    try std.testing.expectEqualStrings("name", url.path.items[1]);
    try std.testing.expectEqual(@as(u32, 0), url.query.count());
    url.query.deinit();
    url.path.deinit();

    url = try initParse("http://127.0.0.1:8080/echo/name", "127.0.0.1:8080", &std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), url.path.items.len);
    try std.testing.expectEqualStrings("echo", url.path.items[0]);
    try std.testing.expectEqualStrings("name", url.path.items[1]);
    try std.testing.expectEqual(@as(u32, 0), url.query.count());
    url.query.deinit();
    url.path.deinit();

    url = try initParse("https://127.0.0.1:8080/echo/name", "127.0.0.1:8080", &std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), url.path.items.len);
    try std.testing.expectEqualStrings("echo", url.path.items[0]);
    try std.testing.expectEqualStrings("name", url.path.items[1]);
    try std.testing.expectEqual(@as(u32, 0), url.query.count());
    url.query.deinit();
    url.path.deinit();

    url = try initParse("/echo/name?name=fffff&animal=ferret&color=purple", "127.0.0.1:8080", &std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), url.path.items.len);
    try std.testing.expectEqual(@as(u32, 3), url.query.count());
    try std.testing.expectEqualStrings("fffff", url.query.get("name").?);
    url.query.deinit();
    url.path.deinit();

    url = try initParse("/echo/name?name=fffff&question=\"ajja?\"", "127.0.0.1:8080", &std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), url.path.items.len);
    try std.testing.expectEqual(@as(u32, 2), url.query.count());
    try std.testing.expect(url.query.get("question") != null);
    const answer = url.query.get("question").?;
    try std.testing.expectEqualStrings("\"ajja?\"", answer);
    url.query.deinit();
    url.path.deinit();
}
