//! A Double Buffered Surface
//! Create with `fromWlSurface` and then call `registerListeners` and then wait for surface to handle configure event.
const std = @import("std");
const log = std.log;
const math = std.math;
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
    return Self{ .wl_surface = wl_surface, .width = width, .height = height, .shared_memory = pool, .buffers = .{
        Buffer{
            .wl_buffer = try shm_pool.createBuffer(0, width, height, width * 4, .xrgb8888),
            .shared_memory = pool[0..@intCast(buffer_size)],
            .cairo_surf = cairo.Surface.createForData(pool.ptr, .ARGB32, width, height, width * 4),
        },
        Buffer{
            .wl_buffer = try shm_pool.createBuffer(buffer_size, width, height, width * 4, .xrgb8888),
            .shared_memory = pool[@intCast(buffer_size)..],
            .cairo_surf = cairo.Surface.createForData(pool.ptr + @as(usize, @intCast(buffer_size)), .ARGB32, width, height, width * 4),
        },
    } };
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

/// draw widget
pub fn drawWidget(self: *Self, widget: widgets.Widget) void {
    const cr = cairo.Context.create(self.currentBuffer().cairo_surf);
    defer cr.destroy();
    switch (widget) {
        // .overlay => |data| {
        //     self.drawWidget(data.top);
        // },
        .box => |data| {
            cr.setSourceRgb(1, 1, 1);
            cr.roundRect(
                @floatFromInt(data.x),
                @floatFromInt(data.y),
                @floatFromInt(data.width),
                @floatFromInt(data.height),
                10,
            );
        },
        .image => |data| {
            cr.setSourceSurface(data.surface, 0, 0);
            cr.paint();
        },
        .text => |data| {
            const FONT_FAMILY = "sans-serif";
            cr.selectFontFace(FONT_FAMILY.ptr, .Normal, .Normal);
            cr.setFontSize(90);
            cr.setSourceRgb(1, 1, 1);
            cr.moveTo(100, 100);
            cr.showText(data.text);
        },
    }
}

pub fn endFrame(self: *Self) void {
    _ = self.buffers[0].cairo_surf.writeToPng("debug1.png");
    _ = self.buffers[1].cairo_surf.writeToPng("debug2.png");
    self.currentBuffer().usable = false;
    self.wl_surface.damage(0, 0, math.maxInt(@TypeOf(self.width)), math.maxInt(@TypeOf(self.height)));
    self.wl_surface.commit();
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
    }
};
