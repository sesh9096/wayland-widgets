//! A Double Buffered Surface
//! Create with `fromWlSurface` and then call `registerListeners` and then wait for surface to handle configure event.
const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const main = @import("./main.zig");
const Context = main.Context;
const Seat = main.Seat;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;
const cairo = @import("./cairo.zig");
const common = @import("./common.zig");
const Widget = common.Widget;
const Rect = common.Rect;
const Point = common.Point;
const WidgetFromId = std.AutoHashMap(u32, *Widget);

wl_surface: *wl.Surface,
shared_memory: []align(std.mem.page_size) u8,
width: i32,
height: i32,
buffers: [2]Buffer,
current_buffer: u1 = 0,
widget: ?*Widget = null,
widget_storage: WidgetFromId,
allocator: std.mem.Allocator,
seat: *Seat,
context: *Context,
redraw: bool = false,
pointer_widget: ?*Widget = null,

const Self = @This();

fn deinit(self: *@This()) void {
    if (self.wl_surf) |surface| {
        surface.destroy();
    }
    if (self.cairo_surf) |surface| {
        surface.destroy();
    }
    if (self.shared_memory) |mem| {
        std.posix.munmap(mem);
    }
    for (self.buffers) |buffer| {
        buffer.deinit();
    }
    self.widget_storage.deinit();
}

pub fn fromWlSurface(context: *Context, wl_surface: *wl.Surface, width: i32, height: i32) !Self {
    const allocator = context.allocator;
    const shm = context.shm;
    const shm_fd = try std.posix.memfd_create("shared_memory_buffer", 0);
    defer std.posix.close(shm_fd);
    const buffer_size = 4 * width * height;
    const shm_len = buffer_size * 2; // we need 2 surfaces for double buffering
    const pool = try std.posix.mmap(
        null,
        @intCast(shm_len),
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        shm_fd,
        0,
    );
    try std.posix.ftruncate(shm_fd, @intCast(shm_len));
    const shm_pool = try shm.createPool(shm_fd, shm_len);
    defer shm_pool.destroy();

    // const cairo_surf = cairo.Surface.createForData(pool.ptr, .ARGB32, width, height, width * 4);
    const cairo_surf0 = cairo.Surface.createForData(pool.ptr, .ARGB32, width, height, cairo.formatStrideForWidth(.ARGB32, width));
    const cairo_surf1 = cairo.Surface.createForData(pool.ptr + @as(usize, @intCast(buffer_size)), .ARGB32, width, height, cairo.formatStrideForWidth(.ARGB32, width));
    return Self{
        .wl_surface = wl_surface,
        .context = context,
        .width = width,
        .height = height,
        .shared_memory = pool,
        .widget_storage = WidgetFromId.init(allocator),
        .allocator = allocator,
        .seat = &context.seat,
        .buffers = .{
            Buffer{
                .wl_buffer = try shm_pool.createBuffer(0, width, height, width * 4, .argb8888),
                .shared_memory = pool[0..@intCast(buffer_size)],
                .cairo_surf = cairo_surf0,
                .cairo_context = cairo.Context.create(cairo_surf0),
            },
            Buffer{
                .wl_buffer = try shm_pool.createBuffer(buffer_size, width, height, width * 4, .argb8888),
                .shared_memory = pool[@intCast(buffer_size)..],
                .cairo_surf = cairo_surf1,
                .cairo_context = cairo.Context.create(cairo_surf1),
            },
        },
    };
    // const buffer = try shm_pool.createBuffer(0, width, height, width * 4, .xrgb8888);
}

/// set listeners
pub fn setListeners(self: *Self) !void {
    self.buffers[0].wl_buffer.setListener(*Buffer, Buffer.bufferListener, &self.buffers[0]);
    self.buffers[1].wl_buffer.setListener(*Buffer, Buffer.bufferListener, &self.buffers[1]);
    self.wl_surface.setListener(*Self, surfaceListener, self);
    try self.seat.registerSurface(self);
}
pub fn notify(self: *Self, event: anytype) void {
    self.redraw = true;
    const eventType = @TypeOf(event);
    if (eventType == wl.Pointer.Event) {}
}
pub fn getPointer(self: *Self) ?*Seat.Pointer {
    const pointer = &self.seat.pointer;
    return if (pointer.surface == self) pointer else null;
}

pub fn getDeepestWidgetAtPoint(self: *Self, point: Point) ?*Widget {
    if (self.widget) |initial_widget| {
        var widget = initial_widget;
        outer: for (1..1000) |_| { // No Infinite Loops
            const children = widget.vtable.getChildren(widget);
            for (0..children.len) |from_end| {
                const i = children.len - from_end - 1;
                if (point.in(children[i].rect)) {
                    widget = children[i];
                    continue :outer;
                }
            }
            return widget;
        }
        unreachable;
    } else {
        return null;
    }
}

/// Send inputs to the relevant widgets
pub fn handleInputs(self: *Self) void {
    self.seat.reset();
    if (self.getPointer()) |pointer| {
        if (self.getDeepestWidgetAtPoint(pointer.pos)) |widget_initial| {
            var widget_opt: ?*Widget = widget_initial;
            while (widget_opt) |widget| {
                widget.vtable.handleInput(widget, self) catch {};
                if (pointer.handled) {
                    break;
                } else {
                    widget_opt = widget.parent;
                }
            } else {
                pointer.setShape(.default);
            }
            if (self.pointer_widget) |prev| {
                // we have already handled in this case
                if (prev != widget_opt) prev.vtable.handleInput(prev, self) catch {};
            }
            self.pointer_widget = widget_opt;
        }
    }
}

pub fn currentBuffer(self: *Self) *Buffer {
    return &self.buffers[self.current_buffer];
}
pub fn getCairoContext(self: *Self) *cairo.Context {
    return self.currentBuffer().cairo_context;
}

pub fn beginFrame(self: *Self) void {
    // Check for inputs
    self.handleInputs();
    self.widget = null;

    // Attach correct buffer
    if (!self.currentBuffer().usable) {
        // log.debug("Buffer {} not ready, switching to {}", .{ self.current_buffer, self.current_buffer ^ 1 });
        self.current_buffer ^= 1;
    }
    self.wl_surface.attach(self.currentBuffer().wl_buffer, 0, 0);
}

pub fn endFrame(self: *Self) void {
    // _ = self.currentBuffer().cairo_surf.writeToPng("debug1.png");
    // draw
    if (self.widget) |widget| {
        // log.debug("Attempting to draw widgets", .{});
        widget.vtable.proposeSize(widget, self);
        widget.rect = Rect{ .w = @floatFromInt(self.width), .h = @floatFromInt(self.height) };
        widget.vtable.draw(widget, self) catch {};
    }
    self.currentBuffer().usable = false;
    self.wl_surface.damage(0, 0, math.maxInt(@TypeOf(self.width)), math.maxInt(@TypeOf(self.height)));
    self.wl_surface.commit();
    self.redraw = false;
    self.seat.transitionState();
}

pub fn end(self: *Self, widget: *Widget) void {
    assert(widget == self.widget);
    if (widget.parent) |parent| {
        self.widget = parent;
    }
}

/// attempt to add child
fn addChildToCurrentWidget(self: *Self, widget: *Widget) !void {
    widget.parent = self.widget;
    if (self.widget) |parent| {
        try parent.vtable.addChild(parent, widget);
    }
}
pub fn getWidget(self: *Self, id_gen: common.IdGenerator, T: type) !*Widget {
    const id = id_gen.toId();
    const get_or_put_res = try self.widget_storage.getOrPut(id);
    const widget = if (get_or_put_res.found_existing) get_or_put_res.value_ptr.* else blk: {
        // log.debug("Created {s} widget with id {}", .{ @typeName(T), id });
        const wid = try Widget.allocateWidget(self.allocator, T);
        get_or_put_res.value_ptr.* = wid;
        const inner: *T = @ptrCast(@alignCast(wid.inner));
        if (@hasDecl(T, "init")) inner.init(self.allocator);
        if (@hasDecl(T, "surface")) inner.surface = self;
        break :blk wid;
    };
    return widget;
}

pub fn surfaceListener(_: *wl.Surface, event: wl.Surface.Event, surface: *Self) void {
    _ = surface;
    _ = event;
    // log.debug("Surface Listener: {}", .{event});
}

/// representation of wl_buffer and related info, width/height is stored by surface
const Buffer = struct {
    wl_buffer: *wl.Buffer,
    cairo_surf: *cairo.Surface,
    cairo_context: *cairo.Context,
    shared_memory: []u8,
    usable: bool = true,
    pub fn bufferListener(_: *wl.Buffer, event: wl.Buffer.Event, buffer: *Buffer) void {
        _ = event; // the only event is release
        buffer.usable = true;
        // log.debug("{} Release {*}", .{ @mod(std.time.milliTimestamp(), 60000), buffer });
    }
    pub fn deinit(self: *Buffer) void {
        self.wl_buffer.destroy();
        self.cairo_surf.destroy();
        self.cairo_context.destroy();
    }
};
