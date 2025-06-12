const std = @import("std");
const mem = std.mem;

pub const ParseError = error{
    InvalidUrl,
    InvalidScheme,
    InvalidHost,
};

raw_url: []const u8,
path: std.ArrayList([]const u8),
query: std.StringHashMap([]const u8),
params: ?*const std.ArrayList([]const u8),

const Url = @This();

pub fn parseUrl(raw_url: []const u8, host: ?[]const u8, allocator: *const mem.Allocator) !Url {
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
            return ParseError.InvalidScheme;
        }

        if (!mem.startsWith(u8, url[new_start_idx..], host.?)) {
            return ParseError.InvalidHost;
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

test parseUrl {
    var url = try parseUrl("/echo/name", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 0);

    url.query.deinit();
    url.path.deinit();

    url = try parseUrl("http://127.0.0.1:8080/echo/name", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 0);

    url.query.deinit();
    url.path.deinit();

    url = try parseUrl("https://127.0.0.1:8080/echo/name", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 0);

    url.query.deinit();
    url.path.deinit();

    url = try parseUrl("/echo/name?name=fffff&animal=ferret&color=purple", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 3);

    url.query.deinit();
    url.path.deinit();

    url = try parseUrl("/echo/name?name=fffff&question=\"ajja?\"", "127.0.0.1:8080", &std.testing.allocator);

    try std.testing.expect(url.path.items.len == 2);
    try std.testing.expect(url.query.count() == 2);

    try std.testing.expect(url.query.get("question") != null);
    const answer = url.query.get("question");
    try std.testing.expect(mem.eql(u8, answer.?, "\"ajja?\""));

    url.query.deinit();
    url.path.deinit();
}
