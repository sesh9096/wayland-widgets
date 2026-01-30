const std = @import("std");
const mem = std.mem;
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
    scanner.addCustomProtocol(b.path("xml/protocols/wlr-layer-shell-unstable-v1.xml"));

    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("xdg_wm_base", 3);
    scanner.generate("zwlr_layer_shell_v1", 1);
    scanner.generate("wp_cursor_shape_manager_v1", 1);
    // scanner.generate("ext_session_lock_manager_v1", 1);

    const dbus = b.addModule("dbus", .{
        .root_source_file = b.path("src/dbus/dbus.zig"),
        .target = target,
    });
    dbus.linkSystemLibrary("dbus-1", .{});
    const dbus_codegen = b.addExecutable(.{
        .name = "dbus_codegen",
        .root_source_file = b.path("src/dbus/codegen.zig"),
        .target = b.host,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "wayland-utility",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("wayland", wayland);
    exe.root_module.addImport("dbus", dbus);
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");
    exe.linkSystemLibrary("cairo");
    exe.linkSystemLibrary("pangocairo");

    // slightly less stupid way to generate dbus client proxies
    var dbus_codegen_step = b.addRunArtifact(dbus_codegen);
    inline for ([_][2][]const u8{
        .{ "xml/dbus/DBusMenu.xml", "DBusMenu" },
        .{ "xml/dbus/status_notifier_watcher.xml", "StatusNotifierWatcher" },
        .{ "xml/dbus/notify.xml", "Notifications" },
    }) |pair| {
        const xml_path = pair[0];
        const module_name = pair[1];
        const generated_path = comptime blk: {
            const start = if (mem.lastIndexOfScalar(u8, xml_path, '/')) |i| i + 1 else 0;
            const end = mem.lastIndexOf(u8, xml_path, ".xml") orelse xml_path.len;
            break :blk xml_path[start..end] ++ ".zig";
        };

        dbus_codegen_step.addPrefixedFileArg("--input=", b.path(xml_path));
        const root_path = dbus_codegen_step.addPrefixedOutputFileArg("--output=", generated_path);
        const generated_module = b.createModule(.{ .root_source_file = root_path });
        generated_module.addImport("dbus", dbus);
        exe.root_module.addImport(module_name, generated_module);
    }
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");

    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_tests.root_module.addImport("wayland", wayland);
    unit_tests.root_module.addImport("dbus", dbus);
    unit_tests.linkLibC();
    // unit_tests.linkSystemLibrary("dbus-1");
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_unit_tests.step);
}
