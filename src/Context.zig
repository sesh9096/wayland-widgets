//! The global context containing everything you might need
const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;
const cairo = @import("./cairo.zig");
const widgets = @import("./widgets.zig");
const Window = @import("./LayerSurfaceWindow.zig");
const Scheduler = @import("./Scheduler.zig");
const Task = Scheduler.Task;
const Surface = @import("./Surface.zig");

display: *wl.Display,
scheduler: Scheduler,
compositor: *wl.Compositor = undefined,
shm: *wl.Shm = undefined,
seat: Seat = undefined,
wm_base: ?*xdg.WmBase = null,
layer_shell: ?*wlr.LayerShellV1 = null,
outputs: OutputList,
allocator: Allocator,

const Context = @This();
pub fn init(allocator: Allocator) !@This() {
    return @This(){
        .allocator = allocator,
        .display = try wl.Display.connect(null),
        .outputs = OutputList.init(allocator),
        .scheduler = Scheduler.init(allocator),
        .seat = .{ .wl_seat = undefined, .surfaces = Seat.Surfaces.init(allocator) },
    };
}

pub fn getGlobals(self: *@This()) !void {
    const registry = try self.display.getRegistry();
    defer registry.destroy();
    registry.setListener(*Context, registryListener, self);
    // gather context
    if (self.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
    // gather output info
    if (self.display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
}

pub fn destroy(self: *@This()) void {
    self.compositor.destroy();
    self.shm.destroy();
    if (self.wm_base) |wm_base| {
        wm_base.destroy();
    }
    if (self.layer_shell) |layer_shell| {
        layer_shell.destroy();
    }
    self.outputs.deinit();
    self.display.disconnect();
}
pub fn displayFd(self: *const @This()) c_int {
    return self.display.getFd();
}

fn layerSurfaceListener(layer_surface: *wlr.LayerSurfaceV1, event: wlr.LayerSurfaceV1.Event, window: *const Window) void {
    switch (event) {
        .configure => |content| {
            // log.debug("Acking layer surface configure", .{});
            layer_surface.ackConfigure(content.serial);
            assert(window.width == 0 or window.width == content.width);
            assert(window.height == 0 or window.height == content.height);
            // wl_surface.commit();
        },
        else => {},
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, wlr.LayerShellV1.interface.name) == .eq) {
                context.layer_shell = registry.bind(global.name, wlr.LayerShellV1, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                context.seat.wl_seat = registry.bind(global.name, wl.Seat, 1) catch return;
                context.seat.init();
            } else if (std.mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                const wl_output = registry.bind(global.name, wl.Output, 1) catch return;
                context.outputs.append(Output{
                    .wl_output = wl_output,
                }) catch return;
                wl_output.setListener(*Output, Output.listener, &context.outputs.items[context.outputs.items.len - 1]);
            } else {
                // uncomment to see all globals
                // log.debug("Not Bound: {s}", .{global.interface});
            }
        },
        .global_remove => {},
    }
}

const Output = struct {
    wl_output: *wl.Output,
    width: i32 = 0,
    height: i32 = 0,
    name: [*:0]const u8 = undefined,
    fn deinit(self: *@This()) void {
        self.wl_output.deinit();
    }
    pub fn initLayerSurface(self: @This(), context: *Context, window: *const Window) !Surface {
        const display = context.display;
        const compositor = context.compositor;
        const layer_shell = context.layer_shell orelse return error.NoZwlrLayerShell;
        const wl_surface = try compositor.createSurface();
        const layer_surface = try layer_shell.getLayerSurface(wl_surface, self.wl_output, window.layer, window.namespace);
        layer_surface.setListener(*const Window, layerSurfaceListener, window);
        const width = if (window.width == 0) self.width else @as(i32, @intCast(window.width));
        const height = if (window.height == 0) self.height else @as(i32, @intCast(window.height));
        layer_surface.setSize(@intCast(width), @intCast(height));
        layer_surface.setExclusiveZone(window.exclusiveZone);
        layer_surface.setAnchor(window.anchor);
        _ = display;
        // if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        wl_surface.commit();
        return Surface.fromWlSurface(context, wl_surface, @intCast(width), @intCast(height));
    }
    pub fn listener(_: *wl.Output, event: wl.Output.Event, output: *Output) void {
        // log.debug("hello from Listener", .{});
        switch (event) {
            .mode => |mode| {
                log.debug("Output mode: {}x{}", .{ mode.width, mode.height });
                output.width = mode.width;
                output.height = mode.height;
            },
            .name => |name| {
                log.debug("Name: {s}", .{name.name});
                output.name = name.name;
            },
            .geometry => {
                log.debug("Geometry", .{});
            },
            .scale => {
                log.debug("Scale", .{});
            },
            .description => {
                log.debug("Description", .{});
            },
            .done => {
                log.debug("Output {s}: {}x{}", .{ output.name, output.width, output.height });
            },
            // else => {},
        }
    }
};

const OutputList = std.ArrayList(Output);

pub const Seat = struct {
    wl_seat: *wl.Seat,
    surfaces: Surfaces = undefined,
    wl_pointer: ?*wl.Pointer = null,
    pointer_surface: ?*Surface = null,
    wl_keyboard: ?*wl.Keyboard = null,
    wl_touch: ?*wl.Touch = null,
    name: [*:0]const u8 = "",
    const Surfaces = std.ArrayList(*Surface);
    fn deinit(self: *Seat) void {
        self.wl_seat.deinit();
    }
    fn init(self: *Seat) void {
        self.wl_seat.setListener(*@This(), listener, self);
    }
    pub fn listener(wl_seat: *wl.Seat, event: wl.Seat.Event, seat: *@This()) void {
        assert(wl_seat == seat.wl_seat);
        // log.debug("Seat: {*}", .{seat});
        switch (event) {
            .capabilities => |capabilities| {
                // log.debug("Capabilities: {}", .{capabilities.capabilities});
                seat.getDevices(capabilities.capabilities) catch unreachable;
            },
            .name => |name| {
                seat.name = name.name;
                // log.debug("Name: {s}", .{seat.name});
            },
        }
    }
    fn getDevices(self: *Seat, capabilities: wl.Seat.Capability) !void {
        const wl_seat = self.wl_seat;
        if (capabilities.pointer) {
            const wl_pointer = try wl_seat.getPointer();
            self.wl_pointer = wl_pointer;
            wl_pointer.setListener(*Seat, pointerListener, self);
        }
        if (capabilities.keyboard) {
            const wl_keyboard = try wl_seat.getKeyboard();
            self.wl_keyboard = wl_keyboard;
            wl_keyboard.setListener(*Seat, keyboardListener, self);
        }
        if (capabilities.touch) {
            const wl_touch = try wl_seat.getTouch();
            self.wl_touch = wl_touch;
            wl_touch.setListener(*Seat, touchListener, self);
        }
    }
    pub fn registerSurface(self: *Seat, surface: *Surface) !void {
        try self.surfaces.append(surface);
    }
    pub fn getSurface(self: *Seat, wl_surface: *wl.Surface) !*Surface {
        for (self.surfaces.items) |surface| {
            if (surface.wl_surface == wl_surface) {
                return surface;
            }
        }
        log.err("Surface {*} not registered with seat", .{wl_surface});
        return error.SurfaceNotRegistered;
    }
    pub fn pointerListener(wl_pointer: *wl.Pointer, event: wl.Pointer.Event, seat: *Seat) void {
        // main input logic handled by Surface
        assert(wl_pointer == seat.wl_pointer);
        switch (event) {
            .enter => |data| {
                seat.pointer_surface = seat.getSurface(data.surface.?) catch unreachable;
                seat.pointer_surface.?.notify(event);
            },
            .leave => |data| {
                assert(data.surface == seat.pointer_surface.?.wl_surface);
                seat.pointer_surface.?.notify(event);
                seat.pointer_surface = null;
            },
            else => {
                seat.pointer_surface.?.notify(event);
            },
        }
    }
    pub fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, seat: *Seat) void {
        _ = seat;
        log.debug("Keyboard Event: {}", .{event});
    }
    pub fn touchListener(_: *wl.Touch, event: wl.Touch.Event, seat: *Seat) void {
        _ = seat;
        log.debug("Touch Event: {}", .{event});
    }
};
