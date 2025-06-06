const std = @import("std");
const Scanner = @import("zig-wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    // we don't technically support tablets, but we need this for cursor shape
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
    scanner.addSystemProtocol("staging/cursor-shape/cursor-shape-v1.xml");
    // scanner.addSystemProtocol("staging/ext-session-lock/ext-session-lock-v1.xml");
    scanner.addCustomProtocol(b.path("protocols/wlr-layer-shell-unstable-v1.xml"));

    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_shm", 2);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("xdg_wm_base", 3);
    scanner.generate("zwlr_layer_shell_v1", 1);
    scanner.generate("wp_cursor_shape_manager_v1", 1);
    // scanner.generate("ext_session_lock_manager_v1", 1);

    const exe = b.addExecutable(.{
        .name = "wayland-utility",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("wayland", wayland);
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");
    exe.linkSystemLibrary("cairo");
    exe.linkSystemLibrary("pangocairo");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // const scheduler = b.addExecutable(.{
    //     .name = "scheduler",
    //     .root_source_file = b.path("src/scheduler.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // const scheduler_step = b.step("scheduler", "Build a Scheduler");
    // scheduler_step.dependOn();
}
