const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
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
const c = @cImport({
    @cInclude("time.h");
});

const Options = struct {
    filename: ?[:0]const u8 = null,
    fn parseArgs() Options {
        var o: Options = .{};
        var args = std.process.args();
        _ = args.next();
        while (args.next()) |arg| {
            o.filename = arg;
        }
        return o;
    }
};

const Output = struct {
    wl_output: *wl.Output,
    width: i32 = 0,
    height: i32 = 0,
    name: [*:0]const u8 = undefined,
    fn deinit(self: *@This()) void {
        self.wl_output.deinit();
    }
    fn initLayerSurface(self: @This(), context: Context, window: *const Window) !Surface {
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
};

const OutputList = std.ArrayList(Output);
/// The global context containing everything you might need
pub const Context = struct {
    display: *wl.Display,
    scheduler: Scheduler,
    compositor: *wl.Compositor = undefined,
    shm: *wl.Shm = undefined,
    wm_base: ?*xdg.WmBase = null,
    layer_shell: ?*wlr.LayerShellV1 = null,
    outputs: OutputList,
    fn destroy(self: *@This()) void {
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
    pub fn init(allocator: std.mem.Allocator) !@This() {
        const display = try wl.Display.connect(null);
        const registry = try display.getRegistry();
        var context = @This(){
            .display = display,
            .outputs = OutputList.init(allocator),
            .scheduler = Scheduler.init(allocator),
        };

        registry.setListener(*Context, registryListener, &context);
        // gather context
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        // gather output info
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        return context;
    }
    pub fn displayFd(self: *const @This()) c_int {
        return self.display.getFd();
    }
};

pub fn main() !void {
    // var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = GPA.allocator();
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();
    var context = try Context.init(allocator);

    const options = Options.parseArgs();
    var windows = Windows.init(allocator);
    var image = widgets.Image{ .surface = cairo.Surface.createFromPng(options.filename.?.ptr) };
    // _ = image;
    try windows.append(.{
        // Background
        .widget = .{ .image = &image },
        // .widget = .{ .text = &text },
        .layer = .background,
        .anchor = .{ .top = true, .bottom = true, .left = true, .right = true },
        .surface = null,
        .exclusiveZone = -1,
        .namespace = "background",
    });

    const output = context.outputs.items[0];
    const window = &windows.items[0];
    var surface = try output.initLayerSurface(context, window);
    surface.registerListeners();
    if (context.display.dispatch() != .SUCCESS) return error.DispatchFailed;

    windows.items[0].surface = &surface;

    var text_buf: [1024]u8 = undefined;
    text_buf[0] = 0;
    var text = widgets.Text{ .text = text_buf[0..0 :0] };
    var box = widgets.Box{ .x = 10, .y = 10, .width = 100, .height = 100 };
    var frame_data = FrameData{
        .buf = &text_buf,
        .image_widget = &image,
        .text_widget = &text,
        .box_widget = &box,
        .surface = &surface,
    };
    const scheduler = &context.scheduler;
    try scheduler.addRepeatTask(Task.create(*FrameData, FrameData.timerTask, &frame_data), 1000);
    var pollfds = [_]std.posix.pollfd{
        .{
            .events = std.posix.POLL.IN,
            .fd = context.displayFd(),
            .revents = 0,
        },
    };
    log.debug("Starting event loop", .{});
    while (true) {
        // log.debug("starting poll", .{});
        const timeout = context.scheduler.runPendingGetTimeInterval();
        if (context.display.flush() != .SUCCESS) return error.DispatchFailed;
        // should we block indefinitely?
        switch (try std.posix.poll(&pollfds, timeout orelse 1)) {
            0 => {
                // timeout
            },
            else => |num_events| {
                // events
                // log.debug("Got input from {} fd's", .{num_events});
                var num_events_remaining = num_events;
                for (pollfds) |pollfd| {
                    if (pollfd.revents != 0) {
                        num_events_remaining -= 1;
                        // something happened!
                        // log.debug("got events 0x{x}", .{pollfd.revents});
                        if (context.display.dispatch() != .SUCCESS) return error.DispatchFailed;
                        if (num_events_remaining == 0) break;
                    }
                }
                assert(num_events_remaining == 0);
            },
        }
        // std.time.ns_per_ms
        // log.debug("{}", .{context.display.dispatchPending()});
        // if (context.display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }
}

fn outputListener(_: *wl.Output, event: wl.Output.Event, output: *Output) void {
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

pub const Windows = std.ArrayList(Window);

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, wlr.LayerShellV1.interface.name) == .eq) {
                context.layer_shell = registry.bind(global.name, wlr.LayerShellV1, 1) catch return;
                log.debug("Bound To: {s}", .{global.interface});
            } else if (std.mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
                log.debug("Bound To: {s}", .{global.interface});
            } else if (std.mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
                log.debug("Bound To: {s}", .{global.interface});
            } else if (std.mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
                log.debug("Bound To: {s}", .{global.interface});
            } else if (std.mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                const wl_output = registry.bind(global.name, wl.Output, 1) catch return;
                context.outputs.append(Output{
                    .wl_output = wl_output,
                }) catch return;
                wl_output.setListener(*Output, outputListener, &context.outputs.items[context.outputs.items.len - 1]);
                log.debug("Bound To: {s}", .{global.interface});
            } else {
                // uncomment to see all globals
                // log.debug("Not Bound: {s}", .{global.interface});
            }
        },
        .global_remove => {},
    }
}

const FrameData = struct {
    buf: []u8,
    image_widget: *widgets.Image,
    text_widget: *widgets.Text,
    box_widget: *widgets.Box,
    counter: u32 = 0,
    surface: *Surface,
    pub fn timerTask(self: *FrameData) void {
        // self.text_widget.text = std.fmt.bufPrintZ(self.buf, "{}", .{self.counter}) catch unreachable;
        const time = std.time.timestamp();
        const time_string = c.ctime((&time));
        const time_string_len = std.mem.len(time_string);
        self.text_widget.text = std.fmt.bufPrintZ(self.buf, "{s}", .{time_string[0 .. time_string_len - 1]}) catch unreachable;
        // log.debug("{} drawing frame {}", .{ @mod(std.time.militaristic(), 60000), self.counter });
        log.debug("{s}: drawing frame {}", .{ time_string[0 .. time_string_len - 1], self.counter });
        self.counter += 1;
        {
            self.surface.beginFrame();
            defer self.surface.endFrame();
            self.surface.drawWidget(.{ .image = self.image_widget });
            self.surface.drawWidget(.{ .text = self.text_widget });
            self.surface.drawWidget(.{ .box = self.box_widget });
        }
    }
};
