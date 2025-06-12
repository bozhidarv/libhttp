//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");

pub const HttpRequest = @import("lib/request.zig").HttpRequest;
pub const HttpResponse = @import("lib/response.zig").HttpResponse;
pub const Router = @import("lib/router.zig").Router;
pub const HttpMethod = @import("lib/method.zig").Method;
pub const HttpStatus = @import("lib/status.zig").Status;
pub const Server = @import("lib/server.zig").Server;
pub const encoder = @import("lib/encoder.zig");

const testing = std.testing;

test "basic add functionality" {
    _ = @import("lib/request.zig");
    _ = @import("lib/response.zig");
    _ = @import("lib/router.zig");
    _ = @import("lib/utils.zig");
    _ = @import("lib/server.zig");
    _ = @import("lib/encoder.zig");
}
