//! A Double Buffered Surface
//! Create with `fromWlSurface` and then call `registerListeners` and then wait for surface to handle configure event.
const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const Context = @import("./main.zig").Context;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;
const cairo = @import("./cairo.zig");
const widgets = @import("./widgets.zig");

wl_surface: *wl.Surface,
shared_memory: []align(std.mem.page_size) u8,
width: i32,
height: i32,
buffers: [2]Buffer,
current_buffer: u1 = 0,
widget: ?*widgets.Widget = null,
allocator: std.mem.Allocator,

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
}

pub fn fromWlSurface(context: Context, wl_surface: *wl.Surface, width: i32, height: i32) !Self {
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
    const cairo_surf0 = cairo.Surface.createForData(pool.ptr, .ARGB32, width, height, width * 4);
    const cairo_surf1 = cairo.Surface.createForData(pool.ptr + @as(usize, @intCast(buffer_size)), .ARGB32, width, height, width * 4);
    return Self{
        .wl_surface = wl_surface,
        .width = width,
        .height = height,
        .shared_memory = pool,
        .allocator = context.allocator,
        .buffers = .{
            Buffer{
                .wl_buffer = try shm_pool.createBuffer(0, width, height, width * 4, .xrgb8888),
                .shared_memory = pool[0..@intCast(buffer_size)],
                .cairo_surf = cairo_surf0,
                .cairo_context = cairo.Context.create(cairo_surf0),
            },
            Buffer{
                .wl_buffer = try shm_pool.createBuffer(buffer_size, width, height, width * 4, .xrgb8888),
                .shared_memory = pool[@intCast(buffer_size)..],
                .cairo_surf = cairo_surf1,
                .cairo_context = cairo.Context.create(cairo_surf1),
            },
        },
    };
    // const buffer = try shm_pool.createBuffer(0, width, height, width * 4, .xrgb8888);
}

/// register handlers
pub fn registerListeners(self: *Self) void {
    self.buffers[0].wl_buffer.setListener(*Buffer, Buffer.bufferListener, &self.buffers[0]);
    self.buffers[1].wl_buffer.setListener(*Buffer, Buffer.bufferListener, &self.buffers[1]);
    self.wl_surface.setListener(*Self, surfaceListener, self);
}

pub fn currentBuffer(self: *Self) *Buffer {
    return &self.buffers[self.current_buffer];
}

pub fn beginFrame(self: *Self) void {
    // Check for resizes

    // Attach correct buffer
    if (!self.currentBuffer().usable) {
        log.debug("Buffer {} not ready, switching to {}", .{ self.current_buffer, self.current_buffer ^ 1 });
        self.current_buffer ^= 1;
    }
    self.wl_surface.attach(self.currentBuffer().wl_buffer, 0, 0);
}

pub fn endFrame(self: *Self) void {
    // _ = self.buffers[0].cairo_surf.writeToPng("debug1.png");
    // _ = self.buffers[1].cairo_surf.writeToPng("debug2.png");
    if (self.widget) |widget| {
        log.debug("Attempting to draw widgets", .{});
        widget.vtable.draw(widget, self, widgets.Rect{ .width = @floatFromInt(self.width), .height = @floatFromInt(self.height) }) catch {};
        self.widget = null;
    }
    self.currentBuffer().usable = false;
    self.wl_surface.damage(0, 0, math.maxInt(@TypeOf(self.width)), math.maxInt(@TypeOf(self.height)));
    self.wl_surface.commit();
}

/// draw widget
fn drawWidget(self: *Self, widget: widgets.Widget) void {
    widget.draw(self, .{
        .width = @floatFromInt(self.width),
        .height = @floatFromInt(self.height),
    });
    self.widget = self.widget.?.parent;
}

pub fn end(self: *Self, widget: *widgets.Widget) void {
    assert(widget == self.widget);
    self.widget = widget.parent;
}

pub fn box(self: *Self, direction: widgets.Direction) !*widgets.Widget {
    const widget = try widgets.Box.widget(self.allocator, direction);
    if (self.widget) |parent| {
        widget.parent = parent;
        try parent.vtable.addChild(parent, widget);
    } else {
        widget.parent = widget;
    }
    self.widget = widget;
    return widget;
}

pub fn overlay(self: *Self) !*widgets.Widget {
    const widget = try widgets.Overlay.widget(self.allocator);
    if (self.widget) |parent| {
        widget.parent = parent;
        try parent.vtable.addChild(parent, widget);
    } else {
        widget.parent = widget;
    }
    self.widget = widget;
    return widget;
}

pub fn image(self: *Self, path: [:0]const u8) !void {
    const surface = cairo.Surface.createFromPng(path);
    if (surface.status() != .SUCCESS) {
        log.debug("{}", .{surface.status()});
    }
    const widget = try widgets.Image.widget(self.allocator, surface);
    if (self.widget) |parent| {
        widget.parent = parent;
        try parent.vtable.addChild(parent, widget);
    } else {
        widget.parent = widget;
    }

    widget.parent = self.widget orelse widget;
}
pub fn text(self: *Self, txt: [:0]const u8) !void {
    const widget = try widgets.Text.widget(self.allocator, txt);
    if (self.widget) |parent| {
        widget.parent = parent;
        try parent.vtable.addChild(parent, widget);
    } else {
        widget.parent = widget;
    }

    widget.parent = self.widget orelse widget;
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
