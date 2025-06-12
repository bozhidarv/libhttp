const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("libhttp", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("libhttp", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "http",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "http_lib",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    const examples = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "basic", .desc = "Basic HTTP server with file serving" },
    };

    for (examples) |example| {
        const example_exe = b.addExecutable(.{
            .name = b.fmt("httplib_{s}", .{example.name}),
            .root_source_file = b.path(b.fmt("src/examples/{s}_server.zig", .{example.name})),
            .target = target,
            .optimize = optimize,
        });
        example_exe.root_module.addImport("libhttp", lib_mod);

        const install_example = b.addInstallArtifact(example_exe, .{});
        const example_step = b.step(
            b.fmt("install-{s}", .{example.name}),
            b.fmt("Install {s}", .{example.desc}),
        );
        example_step.dependOn(&install_example.step);

        const run_example = b.addRunArtifact(example_exe);
        if (b.args) |args| {
            run_example.addArgs(args);
        }
        const run_example_step = b.step(
            b.fmt("run-{s}", .{example.name}),
            b.fmt("Run {s}", .{example.desc}),
        );
        run_example_step.dependOn(&run_example.step);
    }
}
