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
const wp = wayland.client.wp;
const cairo = @import("./cairo.zig");
const Scheduler = @import("./Scheduler.zig");
const Surface = @import("./Surface.zig");
const common = @import("./common.zig");
const Rect = common.Rect;
const Vec2 = common.Vec2;
const KeyState = common.KeyState;
const pango = common.pango;
const Style = common.Style;
const Watch = common.Watch;
const dbus = common.dbus;
const FileNotifier = common.FileNotifier;
const c = common.c;

display: *wl.Display,
scheduler: Scheduler,
watch: Watch,
file_notifier: *FileNotifier,
compositor: *wl.Compositor = undefined,
shm: *wl.Shm = undefined,
seat: Seat = undefined,
wm_base: ?*xdg.WmBase = null,
layer_shell: ?*wlr.LayerShellV1 = null,
outputs: OutputList,
allocator: Allocator,
font_map: *pango.FontMap,
pango_context: *pango.Context,

const Context = @This();
// pub fn init(allocator: Allocator) !@This() {
pub fn configure(self: *Context, allocator: Allocator) !void {
    const font_map = pango.PangoCairo.fontMapGetDefault();
    const pango_context = font_map.createContext();
    pango_context.setRoundGlyphPositions(false);
    const font_description = pango.FontDescription.fromString("mono space");
    font_description.setAbsoluteSize(pango.SCALE * 11);
    defer font_description.free();
    Style.default_theme.default_font = font_map.loadFont(pango_context, font_description);

    const variable_font_description = pango.FontDescription.fromString("sans-serif");
    variable_font_description.setAbsoluteSize(pango.SCALE * 11);
    defer variable_font_description.free();
    Style.default_theme.variable_font = font_map.loadFont(pango_context, variable_font_description);
    var watch = Watch.init(allocator);
    const display = try wl.Display.connect(null);

    var err = dbus.Error{};
    err.init();
    const dbus_connection = dbus.busGet(.session, &err) orelse {
        log.err("{s} {s}", .{ err.name.?, err.message.? });
        return error.Dbus;
    };
    _ = dbus_connection.addFilter(dbus.printFilter, undefined, null);

    const file_notifier = try allocator.create(FileNotifier);
    file_notifier.* = try FileNotifier.init(allocator);

    try watch.appendSlice(&.{
        .{
            .events = std.posix.POLL.IN,
            .fd = display.getFd(),
            .revents = 0,
        },
        .{
            .events = std.posix.POLL.IN,
            .fd = file_notifier.fd,
            .revents = 0,
        },
        // .{
        //     .events = std.posix.POLL.IN,
        //     .fd = dbus_connection.getFd(),
        //     .revents = 0,
        // },
    }, &.{
        Watch.Handler.create(
            display,
            displayDispatch,
            displayFlush,
        ),
        Watch.Handler.create(
            file_notifier,
            notifierDispatch,
            null,
        ),
        // Watch.Handler.create(
        //     dbus_connection,
        //     dbusDispatch,
        //     dbusFlush,
        // ),
    });
    self.* = Context{
        .allocator = allocator,
        .display = display,
        .outputs = OutputList.init(allocator),
        .scheduler = Scheduler.init(allocator),
        .watch = watch,
        .file_notifier = file_notifier,
        .seat = .{ .wl_seat = undefined, .surfaces = Seat.Surfaces.init(allocator) },
        .font_map = font_map,
        .pango_context = pango_context,
    };
    dbus_connection.setDispatchStatusFunction(
        dbusDispatch,
        @ptrCast(self),
        dbus.Connection.doNothing,
    );
    // get any messages first
    dbusDispatch(dbus_connection, .data_remains, self);
    _ = dbus_connection.setWatchFunctions(
        dbusAddWatch,
        dbusRemoveWatch,
        dbusToggledWatch,
        &self.watch,
        dbus.Connection.doNothing,
    );
    try self.getGlobals();
}

pub fn dbusAddWatch(dbus_watch: *dbus.Watch, user_data: *anyopaque) callconv(.C) dbus.dbus_bool_t {
    const watch: *Watch = @alignCast(@ptrCast(user_data));
    const flags = dbus_watch.getFlags();
    // TODO: implement writable properly
    const events = Watch.Events{
        .in = (flags & dbus.Watch.READABLE) != 0,
        // .out = (flags & dbus.Watch.WRITABLE) != 0,
        .out = false,
    };
    log.debug("adding watch, events: 0x{x}", .{@as(i16, @bitCast(events))});
    watch.addOrModify(
        .{ .fd = dbus_watch.getFd(), .events = events },
        .{ .data = dbus_watch, .handle_event = dbusWatchHandle },
    ) catch {
        log.warn("out of memory", .{});
        return .false;
    };
    return .true;
}
pub fn dbusRemoveWatch(dbus_watch: *dbus.Watch, user_data: *anyopaque) callconv(.C) void {
    const watch: *Watch = @alignCast(@ptrCast(user_data));
    _ = watch;
    _ = dbus_watch;
    log.debug("remove watch", .{});
    // watch.add(
    //     .{ .fd = watch.getFd(), .events = .{ .in = true, .out = true } },
    //     .{ .data = dbus_watch, .handle_event = dbusWatchHandle },
    // );
}
pub fn dbusToggledWatch(dbus_watch: *dbus.Watch, user_data: *anyopaque) callconv(.C) void {
    const watch: *Watch = @alignCast(@ptrCast(user_data));
    _ = watch;
    _ = dbus_watch;
    log.debug("toggle watch", .{});
    // watch.add(
    //     .{ .fd = watch.getFd(), .events = .{ .in = true, .out = true } },
    //     .{ .data = dbus_watch, .handle_event = dbusWatchHandle },
    // );
}
pub fn dbusWatchHandle(data: *anyopaque, fd: i32, revents: i16) void {
    _ = fd;
    const dbus_watch: *dbus.Watch = @alignCast(@ptrCast(data));
    const events: Watch.Events = @bitCast(revents);
    // TODO: implement writable properly
    const flags = (if (events.in) dbus.Watch.READABLE else 0) | dbus.Watch.WRITABLE;
    const res = dbus_watch.handle(@intCast(flags));
    _ = res;
}

fn getGlobals(self: *@This()) !void {
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
    self.file_notifier.close();
    self.allocator.destroy(self.file_notifier);
}
pub fn displayFd(self: *const @This()) c_int {
    return self.display.getFd();
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
            } else if (std.mem.orderZ(u8, global.interface, wp.CursorShapeManagerV1.interface.name) == .eq) {
                context.seat.cursor_shape_manager = registry.bind(global.name, wp.CursorShapeManagerV1, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                const wl_output = registry.bind(global.name, wl.Output, 1) catch return;
                context.outputs.append(Output{
                    .wl_output = wl_output,
                    .allocator = context.allocator,
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

pub const Output = struct {
    wl_output: *wl.Output,
    width: i32 = 0,
    height: i32 = 0,
    name: [:0]const u8 = undefined,
    allocator: std.mem.Allocator,
    fn deinit(self: *@This()) void {
        self.wl_output.deinit();
        self.allocator.free(self.name);
    }
    pub fn listener(_: *wl.Output, event: wl.Output.Event, output: *Output) void {
        // log.debug("hello from Listener", .{});
        switch (event) {
            .mode => |mode| {
                log.debug("Output mode: {}x{}", .{ mode.width, mode.height });
                output.width = mode.width;
                output.height = mode.height;
            },
            .name => |data| {
                log.debug("Name: {s}", .{data.name});
                const len = std.mem.len(data.name);
                const buf = output.allocator.allocSentinel(u8, len, 0) catch unreachable;
                @memcpy(buf, data.name);
                output.name = buf;
            },
            .geometry => |data| {
                log.debug("Geometry {}", .{data});
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

pub fn getOutputWithName(context: *Context, name: [:0]const u8) ?*Output {
    for (context.outputs.items) |*output| {
        if (std.mem.eql(u8, output.name, name)) {
            return output;
        }
    }
    return null;
}

pub const Seat = struct {
    wl_seat: *wl.Seat,
    surfaces: Surfaces = undefined,
    wl_pointer: ?*wl.Pointer = null,
    pointer_surface: ?*Surface = null,
    cursor_shape_manager: ?*wp.CursorShapeManagerV1 = null,
    wl_keyboard: ?*wl.Keyboard = null,
    wl_touch: ?*wl.Touch = null,
    name: [*:0]const u8 = "",
    pointer: Pointer = .{},
    // keyboard: void,
    // touch: void,
    const Surfaces = std.ArrayList(*Surface);
    pub const Pointer = struct {
        pos: Vec2 = .{},
        button: ?Button = null,
        surface: ?*Surface = null,
        handled: bool = false,
        state: KeyState = .up,
        serial: u32 = 0,
        cursor_shape_device: ?*wp.CursorShapeDeviceV1 = null,
        pub const Button = enum {
            left,
            right,
            middle,
            side,
            extra,
            forward,
            back,
            task,
        };
        pub fn in(self: *Pointer, rect: Rect) bool {
            return self.pos.in(rect);
        }
        pub fn setShape(self: *Pointer, shape: wp.CursorShapeDeviceV1.Shape) void {
            self.cursor_shape_device.?.setShape(self.serial, shape);
        }
        pub fn listener(wl_pointer: *wl.Pointer, event: wl.Pointer.Event, seat: *Seat) void {
            // main input logic handled by Surface
            assert(wl_pointer == seat.wl_pointer);
            const pointer = &seat.pointer;
            switch (event) {
                .enter => |data| {
                    assert(pointer.surface == null);
                    pointer.pos = .{
                        .x = @floatCast(data.surface_x.toDouble()),
                        .y = @floatCast(data.surface_y.toDouble()),
                    };
                    pointer.serial = data.serial;
                    pointer.surface = seat.getSurface(data.surface.?) catch unreachable;
                    pointer.surface.?.notify(event);
                },
                .leave => |data| {
                    assert(data.surface == pointer.surface.?.wl_surface);
                    pointer.surface.?.notify(event);
                    pointer.surface = null;
                },
                .motion => |data| {
                    pointer.pos = .{
                        .x = @floatCast(data.surface_x.toDouble()),
                        .y = @floatCast(data.surface_y.toDouble()),
                    };
                    pointer.surface.?.notify(event);
                },
                .button => |data| {
                    const btn: ?Pointer.Button = switch (data.button) {
                        c.BTN_LEFT => .left,
                        c.BTN_RIGHT => .right,
                        c.BTN_MIDDLE => .middle,
                        c.BTN_SIDE => .side,
                        c.BTN_EXTRA => .extra,
                        c.BTN_FORWARD => .forward,
                        c.BTN_BACK => .back,
                        c.BTN_TASK => .task,
                        else => blk: {
                            log.warn("Button 0x{x} not supported", .{data.button});
                            break :blk null;
                        },
                    };
                    switch (data.state) {
                        .pressed => {
                            pointer.button = btn;
                            pointer.state.transition(.pressed);
                        },
                        .released => {
                            if (pointer.button == btn) {
                                pointer.state.transition(.released);
                            }
                        },
                        _ => unreachable,
                    }
                    pointer.surface.?.notify(event);
                },
                else => |data| {
                    seat.pointer.surface.?.notify(event);
                    log.warn("Unsupported event: {}", .{data});
                },
            }
        }
    };
    pub fn transitionState(self: *Seat) void {
        self.pointer.state.transition(self.pointer.state);
    }
    pub fn reset(self: *Seat) void {
        self.pointer.handled = if (self.pointer.surface) |_| false else true;
    }
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
            wl_pointer.setListener(*Seat, Pointer.listener, self);
            if (self.cursor_shape_manager) |cursor_shape_manager| {
                self.pointer.cursor_shape_device = try cursor_shape_manager.getPointer(wl_pointer);
            }
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
    pub fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, seat: *Seat) void {
        _ = seat;
        log.debug("Keyboard Event: {}", .{event});
    }
    pub fn touchListener(_: *wl.Touch, event: wl.Touch.Event, seat: *Seat) void {
        _ = seat;
        log.debug("Touch Event: {}", .{event});
    }
};

pub fn displayDispatch(display: *wl.Display, fd: i32, revents: i16) void {
    _ = fd;
    // _ = revents;
    assert(revents & std.posix.POLL.IN != 0);
    switch (display.dispatch()) {
        .SUCCESS => {},
        else => |err| log.err("wayland display dispatch error: {}", .{err}),
    }
}
pub fn displayFlush(display: *wl.Display, fd: i32) void {
    _ = fd;
    // _ = revents;
    switch (display.flush()) {
        .SUCCESS => {},
        else => |err| log.err("wayland display dispatch error: {}", .{err}),
    }
}

pub fn notifierDispatch(notifier: *FileNotifier, fd: i32, revents: i16) void {
    assert(fd == notifier.fd);
    assert(revents & std.posix.POLL.IN != 0);
    notifier.readEvents() catch unreachable;
}
pub fn dbusDispatch(connection: *dbus.Connection, new_status: dbus.DispatchStatus, data: *anyopaque) callconv(.C) void {
    _ = data;
    // assert(revents & std.posix.POLL.IN != 0);
    switch (new_status) {
        .data_remains => while (connection.getDispatchStatus() == .data_remains) {
            connection.dispatch();
        },
        .complete => {},
        .need_memory => {},
    }
}
pub fn dbusFlush(connection: *dbus.Connection, fd: i32) void {
    _ = fd;
    connection.flush();
}
