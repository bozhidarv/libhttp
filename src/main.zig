const std = @import("std");
const httplib = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1 and std.mem.eql(u8, args[1], "--version")) {
        std.debug.print("HttpLib v{s}\n", .{httplib.version});
        return;
    }

    std.debug.print("HttpLib v{s} - Demo\n", .{httplib.version});
    std.debug.print("Available examples:\n", .{});
    std.debug.print("  zig build run-basic      - Basic HTTP server\n", .{});
    std.debug.print("\nRun tests with: zig build test\n", .{});
}

test {
    std.testing.refAllDecls(httplib);
}
