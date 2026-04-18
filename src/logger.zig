const std = @import("std");

pub const log_level = std.log.default_level;

pub fn stdErrLogger(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);


    var buf: [24]u8 = undefined;
    const date_time = getCurrentTimeString(&buf, io);

    var buffer: [64]u8 = undefined;
    const stderr = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();

    stderr.writer.print("{s}", .{date_time}) catch {};

    stderr.setColor(switch (level) {
        .debug => .magenta,
        .err => .red,
        .info => .cyan,
        .warn => .yellow,
    }) catch {};

    stderr.writer.print(" {t}", .{level}) catch {};

    stderr.setColor(.reset) catch {};

    stderr.writer.print("({t}): " ++ format ++ "\n", .{scope} ++ args) catch {};
}

fn getCurrentTimeString(buf: []u8, io: std.Io) []const u8 {
    // Get current timestamp in milliseconds
    const now_ms = std.Io.Timestamp.now(io, .real).toMilliseconds();
    const now_sec = @divFloor(now_ms, 1000);
    const milliseconds = @mod(now_ms, 1000);

    // Convert to epoch seconds and get time components
    const epoch_seconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(now_sec) };
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    // Extract components
    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1;
    const hour = day_seconds.getHoursIntoDay();
    const minute = day_seconds.getMinutesIntoHour();
    const second = day_seconds.getSecondsIntoMinute();

    // Format: DD-MM-YYYYTThh:mm:ss.mmm
    return nosuspend std.fmt.bufPrint(buf, "{d:0>2}/{d:0>2}/{d:0>4}-{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}", .{ day, month, year, hour, minute, second, @abs(milliseconds) }) catch "";
}
