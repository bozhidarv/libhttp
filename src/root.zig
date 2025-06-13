//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");

pub const HttpRequest = @import("http/request.zig").HttpRequest;
pub const HttpResponse = @import("http/response.zig").HttpResponse;
pub const Router = @import("server/router.zig").Router;
pub const HttpMethod = @import("http/method.zig").Method;
pub const HttpStatus = @import("http/status.zig").Status;
pub const headers = @import("http/headers.zig");
pub const Server = @import("server/server.zig").Server;
pub const Url = @import("http/url.zig");
pub const encoder = @import("encoding/encoder.zig");

pub const version = "0.0.1";

const testing = std.testing;

test "basic add functionality" {
    std.testing.refAllDecls(@This());
}
