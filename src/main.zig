const std = @import("std");
const httplib = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const writer = &stdout_writer.interface;


    try writer.print("HttpLib v{s} - Demo\n", .{httplib.version});
    const args_slice = try init.minimal.args.toSlice(init.gpa); 
    defer init.gpa.free(args_slice);
    if (args_slice.len > 1 and std.mem.eql(u8, args_slice[1], "--version")) {
        return;
    }

    try writer.print("Available examples:\n", .{});
    try writer.print("  zig build run-basic      - Basic HTTP server\n", .{});
    try writer.print("\nRun tests with: zig build test\n", .{});

    try writer.flush();
}

test {
    std.testing.refAllDecls(httplib);
}
