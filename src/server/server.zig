const std = @import("std");
const posix = std.posix;
const net = std.Io.net;
const Io = std.Io;
const Router = @import("router.zig");
const HttpRequest = @import("../http/request.zig");
const HttpResponse = @import("../http/response.zig");
const HttpStatus = @import("../http/status.zig").Status;
const slog = std.log;

pub const Errors = error{HeaderTooLarge};

pub const AcceptRequestError = Errors || Io.Reader.DelimiterError || Io.Writer.Error || HttpRequest.Error;

const MAX_CONNS = 4096;

pub const Server = struct {
    server_int: net.Server,
    router: Router,
    allocator: std.mem.Allocator,
    io: Io,

    pub fn init(alloc: std.mem.Allocator, io: Io) Server {
        return .{ .server_int = undefined, .router = .init(alloc), .allocator = alloc, .io = io };
    }

    pub fn start(self: *Server, buf: []const u8, port: u16) !void {
        const server_addr = try net.IpAddress.parseIp4(buf, port);
        self.server_int = try server_addr.listen(self.io, .{ .reuse_address = true });
        defer self.server_int.deinit(self.io);

        while (true) {
            const conn = try self.server_int.accept(self.io);
            _ = try self.io.concurrent(acceptRequest, .{ self.io, std.heap.ArenaAllocator.init(self.allocator), &self.router, conn });
        }
    }

    fn acceptRequest(io: Io, arena: std.heap.ArenaAllocator, router: *Router, client: net.Stream) !void {
        defer client.close(io);
        defer arena.deinit();

        var rbuffer: [1024]u8 = undefined;
        var client_reader = client.reader(io, &rbuffer);
        const reader = &client_reader.interface;

        var wbuffer: [1024]u8 = undefined;
        var client_writer = client.writer(io, &wbuffer);
        const writer = &client_writer.interface;

        var closed = false;
        while (!closed) {
            var allocator: std.mem.Allocator = @constCast(&arena).allocator();
            defer if (!closed) {
                _ = @constCast(&arena).reset(.free_all);
            };

            var req_buffer: [8192]u8 = undefined;
            var req_writer: Io.Writer = .fixed(&req_buffer);

            var req: HttpRequest = .init_simple(allocator);

            var request_line_parsed = false;
            var curr_pos: usize = 0;
            while (true) {
                const curr_line_len = reader.streamDelimiter(&req_writer, '\n') catch |err| switch (err) {
                    Io.Reader.StreamError.EndOfStream => 0,
                    else => return err,
                };
                reader.toss(1);

                slog.debug("Read {d} bytes", .{curr_line_len});
                const is_req_end = req_writer.end >= 2 and req_buffer[req_writer.end - 2] == '\r' and req_buffer[req_writer.end - 1] == '\r';
                if (is_req_end or curr_line_len == 0) {
                    break;
                }

                const end_pos = curr_pos + curr_line_len - 1;
                const curr_line = req_buffer[curr_pos..end_pos];
                curr_pos = req_writer.end;

                if (!request_line_parsed) {
                    try req.parseRequestLine(curr_line);
                    request_line_parsed = true;
                    continue;
                }
                try req.parseHeader(curr_line);
            }

            const content_length_h = req.headers.get("Content-Length");
            if (content_length_h) |_| {
                req.body_reader = reader;
            }

            const conn_header = req.headers.get("Connection");

            var res: HttpResponse = .init(allocator, io);

            if (conn_header == null or (conn_header != null and std.mem.eql(u8, conn_header.?, "close"))) {
                closed = true;
                try res.headers.put("Connection", "close");
            }

            const encoding = req.headers.get("Accept-Encoding");
            if (encoding) |e| {
                try res.setEncoding(e);
            }

            const route = try router.getRoute(req.method, req.url.raw_url);
            if (route) |r| {
                const url_params = try r.extractRouteParams(req.url.path.items, allocator);
                defer url_params.deinit();

                req.setUrlParams(&url_params);
                try r.handler(&req, &res, io, allocator);
            } else {
                res.status = HttpStatus.not_found;
            }

            const serialized_res = try res.serialize();
            defer allocator.free(serialized_res);

            try writer.writeAll(serialized_res);
            try writer.flush();
        }
    }
};
