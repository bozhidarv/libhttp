const std = @import("std");
const net = std.net;
const mem = std.mem;
const libhttp = @import("libhttp");
const slog = std.log;
const logger = libhttp.logger;
const headers = libhttp.headers;

var directory: ?[]const u8 = null;

pub const std_options: std.Options = .{
    // Set the log level to info
    .log_level = logger.log_level,

    // Define logFn to override the std implementation
    .logFn = logger.stdErrLogger,
};

pub fn main(init: std.process.Init) !void {
    const env_map = init.environ_map;
    defer env_map.deinit(); // technically unnecessary when using ArenaAllocator

    var args_iter = init.minimal.args.iterate(); //why does this only compile with "var"??
    _ = args_iter.skip(); //to skip the zig call
    
    const flag_name = args_iter.next() orelse "";
    if (std.mem.eql(u8, flag_name, "--directory")) {
        directory = args_iter.next();
    }

    const port_str = env_map.get("PORT") orelse "4221";
    slog.info("App started on port: {s}", .{port_str});

    const port_parsed = try std.fmt.parseInt(u16, port_str, 10);

    var server = libhttp.Server.init(init.gpa, init.io);

    try server.router.addRoute(.GET, "/", &handleIndex);
    try server.router.addRoute(.GET, "/echo/{str}", &handleEcho);
    try server.router.addRoute(.GET, "/user-agent", &handleUserAgent);
    try server.router.addRoute(.GET, "/files/{str}", &handleReadFile);
    try server.router.addRoute(.POST, "/files/{str}", &handleWriteFile);

    try server.start("127.0.0.1", port_parsed);
}

fn handleIndex(_: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, _: std.Io, _: mem.Allocator) !void {
    slog.info("Hit index page", .{});
    res.status = .ok;
}

fn handleEcho(req: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, _: std.Io, _: mem.Allocator) anyerror!void {
    slog.info("Hit echo page", .{});
    res.status = .ok;
    try res.sendText(req.url.params.?.items[0]);
}

fn handleWriteFile(req: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, io: std.Io, allocator: mem.Allocator) anyerror!void {
    slog.info("Hit write file page", .{});
    if (req.body_reader == null) {
        return;
    }

    const body_len = try req.headers.getInt(usize, headers.Name.CONTENT_LENGTH);
    slog.debug("File body length: {d}", .{ body_len.? });

    const file_name = req.url.params.?.items[0];
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory.?, file_name });
    defer allocator.free(path);

    const file = std.Io.Dir.createFileAbsolute(io, path, .{}) catch |e| {
        slog.err("{any}", .{e});
        return;
    };
    defer file.close(io);
    var wbuffer: [1024]u8 = undefined;
    var file_writer = file.writer(io, &wbuffer);
    const writer = &file_writer.interface;

    try req.body_reader.?.streamExact(writer, body_len.?);
    try writer.flush();

    res.status = .ok;
}

fn handleReadFile(req: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, _: std.Io, allocator: mem.Allocator) anyerror!void {
    slog.info("Hit read file page", .{});
    const file_name = req.url.params.?.items[0];

    if (directory == null) {
        res.status = .internal_server_error;
        return;
    }

    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory.?, file_name });
    slog.info("File trying to be read is: {s}", .{path});
    defer allocator.free(path);

    res.sendFile(path) catch |err| switch (err) {
        error.FileNotFound => {
            res.status = libhttp.HttpStatus.not_found;
            return;
        },
        else => return err,
    };
    res.status = .ok;
}

fn handleUserAgent(req: *const libhttp.HttpRequest, res: *libhttp.HttpResponse, _: std.Io, _: mem.Allocator) anyerror!void {
    slog.info("Hit user agent page", .{});
    const user_agent = req.headers.get("user-agent");

    if (user_agent == null) {
        res.status = .internal_server_error;
        return;
    }

    res.status = .ok;
    try res.sendText(user_agent.?);
}
