//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");

pub const HttpRequest = @import("request.zig").HttpRequest;
pub const HttpResponse = @import("response.zig").HttpResponse;
pub const Router = @import("router.zig").Router;
pub const HttpMethod = @import("utils.zig").HttpMethod;
pub const Server = @import("server.zig").Server;
pub const encoder = @import("encoder.zig");

const testing = std.testing;

test "basic add functionality" {
    _ = @import("request.zig");
    _ = @import("response.zig");
    _ = @import("router.zig");
    _ = @import("utils.zig");
    _ = @import("server.zig");
    _ = @import("encoder.zig");
}
