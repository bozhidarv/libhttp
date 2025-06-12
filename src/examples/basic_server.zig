const std = @import("std");
const net = std.net;
const mem = std.mem;
const libhttp = @import("libhttp");

var directory: ?[]const u8 = null;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const env_map = try arena.allocator().create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(arena.allocator());
    defer env_map.deinit(); // technically unnecessary when using ArenaAllocator

    var args = std.process.args(); //why does this only compile with "var"??
    _ = args.skip(); //to skip the zig call
    //
    const flag_name = args.next() orelse "";
    if (std.mem.eql(u8, flag_name, "--directory")) {
        directory = args.next();
    }

    const port_str = env_map.get("PORT") orelse "4221";

    const port_parsed = try std.fmt.parseInt(u16, port_str, 10);

    var server = libhttp.Server.init(arena.allocator());

    try server.router.addRoute(.GET, "/", &handleIndex);
    try server.router.addRoute(.GET, "/echo/{str}", &handleEcho);
    try server.router.addRoute(.GET, "/user-agent", &handleUserAgent);
    try server.router.addRoute(.GET, "/files/{str}", &handleReadFile);
    try server.router.addRoute(.POST, "/files/{str}", &handleWriteFile);

    try server.start("127.0.0.1", port_parsed);
}

fn handleIndex(_: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, _: mem.Allocator) anyerror!void {
    res.status = libhttp.HttpStatus.ok;
}

fn handleEcho(req: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, _: mem.Allocator) anyerror!void {
    res.status = libhttp.HttpStatus.ok;
    try res.sendText(req.url.params.?.items[0]);
}

fn handleWriteFile(req: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, allocator: mem.Allocator) anyerror!void {
    if (req.body == null) {
        return;
    }

    const file_name = req.url.params.?.items[0];
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory.?, file_name });
    defer allocator.free(path);

    const file = try std.fs.createFileAbsolute(path, .{});
    _ = try file.write(req.body.?);

    res.status = libhttp.HttpStatus.created;
}

fn handleReadFile(req: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, allocator: mem.Allocator) anyerror!void {
    const file_name = req.url.params.?.items[0];

    if (directory == null) {
        res.status = libhttp.HttpStatus.internal_server_error;
        return;
    }

    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory.?, file_name });
    defer allocator.free(path);

    res.sendFile(path) catch |err| switch (err) {
        error.FileNotFound => {
            res.status = libhttp.HttpStatus.not_found;
            return;
        },
        else => return err,
    };
    res.status = libhttp.HttpStatus.ok;
}

fn handleUserAgent(req: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, _: mem.Allocator) anyerror!void {
    const user_agent = req.headers.get("user-agent");

    if (user_agent == null) {
        res.status = libhttp.HttpStatus.internal_server_error;
        return;
    }

    res.status = libhttp.HttpStatus.ok;
    try res.sendText(user_agent.?);
}
