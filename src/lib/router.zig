const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const HttpRequest = @import("request.zig");
const HttpResponse = @import("response.zig");
const HttpMethod = @import("utils.zig").HttpMethod;

pub const Router = @This();

pub const Route = struct {
    method: HttpMethod,
    path: std.ArrayList([]const u8),
    handler: *const fn (req: *const HttpRequest, res: *HttpResponse, allocator: mem.Allocator) anyerror!void,

    pub fn deinit(self: *const Route, _: *mem.Allocator) void {
        // for (self.path.items) |path_item| {
        //     allocator.free(path_item);
        // }

        self.path.deinit();
    }

    pub fn extractRouteParams(self: *const Route, raw_path: [][]const u8, allocator: mem.Allocator) !std.ArrayList([]const u8) {
        var url_params: std.ArrayList([]const u8) = .init(allocator);
        for (self.path.items, 0..) |path_item, i| {
            if (mem.eql(u8, path_item, "{str}")) {
                try url_params.append(raw_path[i]);
            }
        }
        return url_params;
    }
};

routes: std.ArrayList(Route),
allocator: mem.Allocator,

pub fn init(allocator: mem.Allocator) Router {
    const routes: std.ArrayList(Route) = .init(allocator);
    return .{
        .routes = routes,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Router) void {
    for (self.routes.items) |route| {
        route.deinit(&self.allocator);
    }

    self.routes.deinit();
}

pub fn addRoute(self: *Router, method: HttpMethod, path: []const u8, handler: *const fn (req: *const HttpRequest, res: *HttpResponse, allocator: mem.Allocator) anyerror!void) !void {
    var path_it = mem.splitSequence(u8, path[1..], "/");

    var path_arr: std.ArrayList([]const u8) = .init(self.allocator);

    while (path_it.next()) |path_item| {
        try path_arr.append(path_item);
    }

    const route: Route = .{
        .method = method,
        .handler = handler,
        .path = path_arr,
    };

    try self.routes.append(route);
}

pub fn getRoute(self: *Router, method: HttpMethod, path: []const u8) !?*const Route {
    var path_it = mem.splitSequence(u8, path[1..], "/");

    const prev_routes: *std.ArrayList(*const Route) = @constCast(&(std.ArrayList(*const Route).init(self.allocator)));
    defer prev_routes.*.deinit();

    for (0..self.routes.items.len) |i| {
        try prev_routes.*.append(&(self.routes.items[i]));
    }

    var current_routes: *std.ArrayList(*const Route) = @constCast(&(std.ArrayList(*const Route).init(self.allocator)));
    defer current_routes.*.deinit();

    var i: u32 = 0;
    while (path_it.next()) |path_item| : (i += 1) {
        for (prev_routes.items) |route| {
            if (route.method != method or (route.path.items.len - 1) < i) {
                continue;
            }

            if (mem.eql(u8, route.path.items[i], path_item) or mem.eql(u8, route.path.items[i], "{str}")) {
                try current_routes.append(route);
            }
        }

        prev_routes.*.deinit();
        prev_routes.* = current_routes.*;
        current_routes = @constCast(&(std.ArrayList(*const Route).init(self.allocator)));
    }

    var j: u32 = 0;
    while (j < prev_routes.items.len) {
        const route = prev_routes.items[j];
        if (route.*.path.items.len != i) {
            _ = prev_routes.orderedRemove(j);
            continue;
        }
        j += 1;
    }

    if (prev_routes.*.items.len != 1) {
        return null;
    }

    const route = prev_routes.*.items[0];

    return route;
}

fn dummyHandler(_: *const HttpRequest, _: *HttpResponse, _: mem.Allocator) anyerror!void {}

test getRoute {
    var router: Router = .init(std.testing.allocator);
    defer router.deinit();

    try router.addRoute(.GET, "/test", &dummyHandler);
    try router.addRoute(.GET, "/", &dummyHandler);
    try router.addRoute(.GET, "/info/haha", &dummyHandler);
    try router.addRoute(.GET, "/hello/name", &dummyHandler);
    try router.addRoute(.GET, "/info", &dummyHandler);

    var route = try router.getRoute(.GET, "/test");

    try testing.expect(mem.eql(u8, route.?.path.items[0], "test"));

    route = try router.getRoute(.GET, "/about");

    try testing.expect(route == null);

    route = try router.getRoute(.GET, "/info");

    try testing.expect(mem.eql(u8, route.?.path.items[0], "info"));

    route = try router.getRoute(.GET, "/info/haha");

    try testing.expect(mem.eql(u8, route.?.path.items[1], "haha"));

    route = try router.getRoute(.GET, "/");

    try testing.expect(mem.eql(u8, route.?.path.items[0], ""));
}

test "route_params" {
    var router: Router = .init(std.testing.allocator);
    defer router.deinit();

    try router.addRoute(.GET, "/test", &dummyHandler);
    try router.addRoute(.GET, "/info/haha", &dummyHandler);
    try router.addRoute(.GET, "/hello/name", &dummyHandler);
    try router.addRoute(.GET, "/info", &dummyHandler);
    try router.addRoute(.GET, "/echo/{str}", &dummyHandler);

    const route = try router.getRoute(.GET, "/echo/hello");

    try testing.expect(mem.eql(u8, route.?.path.items[0], "echo"));

    const parsed_url = [_][]const u8{ "echo", "hello" };

    const url_params = try route.?.extractRouteParams(@constCast(parsed_url[0..]), testing.allocator);
    defer url_params.deinit();

    try testing.expect(mem.eql(u8, url_params.items[0], "hello"));
}
