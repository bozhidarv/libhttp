//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");

pub const HttpRequest = @import("lib/request.zig").HttpRequest;
pub const HttpResponse = @import("lib/response.zig").HttpResponse;
pub const Router = @import("lib/router.zig").Router;
pub const HttpMethod = @import("lib/method.zig").Method;
pub const HttpStatus = @import("lib/status.zig").Status;
pub const headers = @import("lib/headers.zig");
pub const Server = @import("lib/server.zig").Server;
pub const Url = @import("utils/url.zig");
pub const encoder = @import("encoding/encoder.zig");

pub const version = "0.0.1";

const testing = std.testing;

test "basic add functionality" {
    std.testing.refAllDecls(@This());
}
