const std = @import("std");
const posix = std.posix;
const net = std.Io.net;
const Io = std.Io;
const Router = @import("router.zig");
const HttpRequest = @import("../http/request.zig");
const HttpResponse = @import("../http/response.zig");
const HttpStatus = @import("../http/status.zig").Status;
const slog = std.log;

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
            var allocator = @constCast(&arena).allocator();
            defer if (!closed) {
                _ = @constCast(&arena).reset(.free_all);
            };

            var req_buffer: [4096]u8 = undefined;
            var req_writer: Io.Writer = .fixed(&req_buffer);
            const read_data = reader.stream(&req_writer, .limited(4096)) catch |err| switch (err) {
                Io.Reader.StreamError.EndOfStream => {
                    break;
                },
                else => return err,
            };
            var req_raw: std.ArrayList(u8) = req_writer.toArrayList();
            defer req_raw.deinit(allocator);

            slog.info("Read {d} bytes", .{read_data});
            // slog.info("the request has length of {d} bytes", .{req_raw.items.len});
            // while (true) {
            //     const req_buffer = reader.stream(1) catch |err| switch (err) {
            //         error.EndOfStream => {
            //             break;
            //         },
            //         else => return err,
            //     };
            //     try req_raw.append(req_buffer[0]);
            //     if (req_raw.items.len >= 4 and std.mem.eql(u8, req_raw.items[req_raw.items.len-4..], "\r\n\r\n")) {
            //         break;
            //     }
            // }

            // Parse Content-Length and read the body if present.
            // var content_length: usize = 0;
            // var header_lines = std.mem.splitSequence(u8, req_raw.items, "\r\n");
            // _ = header_lines.first();
            // while (header_lines.next()) |line| {
            //     if (line.len == 0) break;
            //     if (std.mem.startsWith(u8, line, "Content-Length: ")) {
            //         content_length = std.fmt.parseInt(usize, line["Content-Length: ".len..], 10) catch 0;
            //         break;
            //     }
            // }
            // if (content_length > 0) {
            //     const header_end = req_raw.items.len;
            //     try req_raw.resize(allocator, header_end + content_length);
            //     var remaining = content_length;
            //     while (remaining > 0) {
            //         const to_read = @min(remaining, rbuffer.len);
            //         reader.fill(to_read) catch |err| switch (err) {
            //             Io.Reader.Error.EndOfStream => return,
            //             else => return err,
            //         };
            //         const offset = header_end + (content_length - remaining);
            //         @memcpy(req_raw.items[offset..][0..to_read], rbuffer[0..to_read]);
            //         remaining -= to_read;
            //         reader.tossBuffered();
            //     }
            // }

            var req: HttpRequest = try .init(req_raw.items, allocator);
            defer req.deinit();

            const conn_header = req.headers.get("Connection");

            var res: HttpResponse = .init(allocator, io);
            defer res.deinit();

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
