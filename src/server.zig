const std = @import("std");
const posix = std.posix;
const net = std.net;
const Router = @import("router.zig");
const HttpRequest = @import("request.zig");
const HttpResponse = @import("response.zig");

const MAX_CONNS = 4096;

const HttpConnection = struct {
    net_conn: net.Server.Connection,
    req: ?*HttpRequest,
    res: ?*HttpResponse,
};

pub const Server = struct {
    server_sock: net.Server,
    server_poll: posix.pollfd,
    router: Router,
    conns: [MAX_CONNS]HttpConnection,
    polls: [MAX_CONNS + 1]posix.pollfd,
    conn_count: usize,
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Server {
        return .{
            .server_sock = undefined,
            .server_poll = undefined,
            .router = .init(alloc),
            .conns = [_]HttpConnection{.{
                .net_conn = undefined,
                .req = null,
                .res = null,
            }} ** 4096,
            .polls = undefined,
            .conn_count = 0,
            .allocator = alloc,
        };
    }

    pub fn start(self: *Server, buf: []const u8, port: u16) !void {
        const server_addr = try net.Address.parseIp4(buf, port);
        self.server_sock = try server_addr.listen(.{ .reuse_address = true, .force_nonblocking = true });
        defer self.server_sock.deinit();

        self.polls[0] = .{
            .events = posix.POLL.IN,
            .fd = self.server_sock.stream.handle,
            .revents = 0,
        };

        while (true) {
            var pending_num = try posix.poll(self.polls[0 .. self.conn_count + 1], -1);

            if (pending_num == 0) {
                continue;
            }

            if (self.polls[0].revents != 0) {
                while (true) {
                    const conn = acceptNonBlocking(&self.server_sock) catch |err| switch (err) {
                        error.WouldBlock => break,
                        else => return err,
                    };

                    self.polls[self.conn_count + 1] = posix.pollfd{ .events = posix.POLL.IN, .fd = conn.stream.handle, .revents = 0 };
                    self.conns[self.conn_count].net_conn = conn;
                    self.conn_count += 1;
                }
                pending_num -= 1;
            }

            var closed = false;
            var i: usize = 0;
            while ((i < self.conn_count) and (pending_num > 0)) {
                if (self.polls[i + 1].revents == 0) {
                    i += 1;
                    continue;
                }

                if (self.polls[i + 1].revents & posix.POLL.IN == posix.POLL.IN) read_blk: {
                    var read_data: std.ArrayList(u8) = .init(self.allocator);
                    defer read_data.deinit();

                    var buffer: [1024]u8 = undefined;
                    var read_size: usize = 0;

                    while (true) {
                        read_size = self.conns[i].net_conn.stream.read(&buffer) catch |err| {
                            std.debug.print("{any}", .{err});
                            closed = true;
                            break :read_blk;
                        };
                        try read_data.appendSlice(buffer[0..read_size]);
                        buffer = undefined;
                        if (read_size < buffer.len) {
                            break;
                        }
                    }

                    var req: HttpRequest = try .init(read_data.items, self.allocator);

                    var res: HttpResponse = .init(self.allocator);

                    const encoding = req.headers.get("Accept-Encoding");
                    if (encoding) |e| {
                        try res.setEncoding(e);
                    }

                    const route = try self.router.getRoute(req.method, req.url.raw_url);
                    if (route) |r| {
                        const url_params = try r.extractRouteParams(req.url.path.items, self.allocator);
                        defer url_params.deinit();

                        req.setUrlParams(&url_params);
                        try r.handler(&req, &res, self.allocator);
                    } else {
                        res.status = 404;
                    }

                    self.conns[i].req = &req;
                    self.conns[i].res = &res;

                    const serialized_res = try res.serialize();
                    defer self.allocator.free(serialized_res);

                    _ = try self.conns[i].net_conn.stream.write(serialized_res);

                    req.deinit();
                    res.deinit();

                    closed = true;
                }

                if (closed or (self.polls[i].revents & posix.POLL.HUP == posix.POLL.HUP)) {
                    self.conns[i].net_conn.stream.close();
                    self.conns[i] = self.conns[self.conn_count - 1];
                    self.polls[i + 1] = self.polls[self.conn_count];
                    self.conn_count -= 1;
                } else {
                    i += 1;
                }

                pending_num -= 1;
            }
        }
    }

    fn acceptNonBlocking(s: *net.Server) posix.AcceptError!net.Server.Connection {
        var accepted_addr: net.Address = undefined;
        var addr_len: posix.socklen_t = @sizeOf(net.Address);
        const fd = try posix.accept(s.stream.handle, &accepted_addr.any, &addr_len, posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK);

        return .{
            .stream = .{ .handle = fd },
            .address = accepted_addr,
        };
    }
};
