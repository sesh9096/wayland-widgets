//! A Double Buffered Surface
//! Create with `fromWlSurface` and then call `registerListeners` and then wait for surface to handle configure event.
const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const main = @import("./main.zig");
const Context = @import("./Context.zig");
const Seat = Context.Seat;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;
const cairo = @import("./cairo.zig");
const common = @import("./common.zig");
const Widget = common.Widget;
const Rect = common.Rect;
const Vec2 = common.Vec2;
const UVec2 = common.UVec2;
const Style = common.Style;
const WidgetFromId = std.AutoHashMap(u32, *anyopaque);
const WidgetList = std.ArrayList(Widget);

wl_surface: *wl.Surface,
wl_shm: *wl.Shm,
shared_memory: []align(std.mem.page_size) u8 = &.{},
buffers: [2]Buffer,
current_buffer: u1 = 0,
size: UVec2,
request_resize: *const fn (self: *Self, size: UVec2) void = requestResizeExample,
precommit: ?*const fn (self: *Self) void = null,
widget: ?Widget = null,
widget_storage: WidgetFromId,
allocator: std.mem.Allocator,
seat: *Seat,
/// Default Style for all widgets
style: Style,
/// list of widgets which have been updated and need to be redrawn
redraw_list: WidgetList,
/// what the pointer is currently hovering over
pointer_widget: ?Widget = null,
/// what the pointer has clicked on or is receiving keyboard input
focused_widget: ?Widget = null,
/// if we need a redraw
updated: bool = true,
clip: Rect = Rect.inf,
const Self = @This();

// const RedrawList = struct {
//     rect_list: RectList,
//     const RectList = std.ArrayList(Rect);
//     pub fn init(allocator: std.mem.Allocator) RedrawList {
//         return .{
//             .rect_list = RectList.init(allocator),
//         };
//     }
//     pub fn add(self: *RedrawList, rect: Rect) !void {
//         for (0.., self.rect_list.items) |i, item| {
//             if (item.contains(rect)) {
//                 return;
//             } else if (rect.contains(item)) {
//                 self.rect_list.items[i] = rect;
//                 for ((i + 1).., self.rect_list.items[(i + 1)..]) |j, item_check| {
//                     if (rect.contains(item_check)) {
//                         self.rect_list.orderedRemove(j);
//                     }
//                 }
//                 return;
//             }
//         }
//         self.rect_list.append(rect);
//     }
//     pub fn clear(self: *RedrawList) void {}
//     pub fn damage(self: *RedrawList, wl_surface: *wl.Surface) void {
//         for (self.rect_list.items) |rect| {
//             wl_surface.damage(
//                 @intFromFloat(rect.x),
//                 @intFromFloat(rect.y),
//                 @intFromFloat(rect.w),
//                 @intFromFloat(rect.h),
//             );
//         }
//     }
// };

fn deinit(self: *Self) void {
    if (self.wl_surf) |surface| {
        surface.destroy();
    }
    self.destroyBuffers();
    self.widget_storage.deinit();
    self.redraw_list.deinit();
}

/// Note: Prefer not to use directly, use configure instead
fn fromWlSurface(
    allocator: std.mem.Allocator,
    wl_shm: *wl.Shm,
    seat: *Context.Seat,
    wl_surface: *wl.Surface,
) Self {
    return Self{
        .wl_surface = wl_surface,
        .wl_shm = wl_shm,
        .size = undefined,
        .widget_storage = WidgetFromId.init(allocator),
        .redraw_list = WidgetList.init(allocator),
        .allocator = allocator,
        .seat = seat,
        .style = .{},
        .buffers = undefined,
    };
    // const buffer = try shm_pool.createBuffer(0, width, height, width * 4, .xrgb8888);
}

pub fn configure(
    self: *Self,
    allocator: std.mem.Allocator,
    wl_shm: *wl.Shm,
    seat: *Context.Seat,
    wl_surface: *wl.Surface,
) !void {
    self.* = fromWlSurface(allocator, wl_shm, seat, wl_surface);
    self.wl_surface.setListener(*Self, surfaceListener, self);
    try self.seat.registerSurface(self);
}

pub const ResizeError = std.posix.TruncateError || std.posix.MemFdCreateError || std.posix.MMapError;

/// set size, reallocate memory if needed, notify compositor
pub fn resize(self: *Self, width: i32, height: i32) ResizeError!void {
    // if are resizing to the same size, we don't need to do anything
    if (self.size.x == width and self.size.y == height) return;
    self.updated = true;
    if (self.shared_memory.len != 0) {
        try self.destroyBuffers();
    }
    // if we have no area, we do not need buffers
    self.size = .{ .x = @intCast(width), .y = @intCast(height) };
    if (width <= 0 or height <= 0) return;

    const cairo_format = .ARGB32;
    const stride = cairo.formatStrideForWidth(cairo_format, width);
    const buffer_size = stride * height;
    const shm_len = buffer_size * 2; // we need 2 surfaces for double buffering

    const shm_fd = try std.posix.memfd_create("shared_memory_buffer", 0);
    defer std.posix.close(shm_fd);
    const pool = try std.posix.mmap(
        null,
        @intCast(shm_len),
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        shm_fd,
        0,
    );
    try std.posix.ftruncate(shm_fd, @intCast(shm_len));

    const shm_pool = try self.wl_shm.createPool(shm_fd, shm_len);
    defer shm_pool.destroy();

    // const cairo_surf = cairo.Surface.createForData(pool.ptr, .ARGB32, width, height, width * 4);
    // indicates there is a previously sized surface
    const cairo_surf0 = cairo.Surface.createForData(pool.ptr, cairo_format, width, height, stride);
    const cairo_surf1 = cairo.Surface.createForData(pool.ptr + @as(usize, @intCast(buffer_size)), cairo_format, width, height, stride);
    self.buffers = .{
        .{
            .wl_buffer = try shm_pool.createBuffer(0, width, height, stride, .argb8888),
            .shared_memory = pool[0..@intCast(buffer_size)],
            .cairo_surf = cairo_surf0,
            .cairo_context = cairo.Context.create(cairo_surf0),
        },
        .{
            .wl_buffer = try shm_pool.createBuffer(buffer_size, width, height, stride, .argb8888),
            .shared_memory = pool[@intCast(buffer_size)..],
            .cairo_surf = cairo_surf1,
            .cairo_context = cairo.Context.create(cairo_surf1),
        },
    };
    self.buffers[0].setListener();
    self.buffers[1].setListener();
    self.shared_memory = pool;
}
pub fn destroyBuffers(self: *Self) !void {
    for (&self.buffers) |*buffer| {
        buffer.deinit();
    }
    std.posix.munmap(self.shared_memory);
    self.shared_memory = &.{};
    self.current_buffer = 0;
}
pub fn requestResizeExample(_: *Self, _: UVec2) void {}

pub fn notify(self: *Self, event: anytype) void {
    self.updated = true;
    const eventType = @TypeOf(event);
    if (eventType == wl.Pointer.Event) {}
    // _ = self;
}
pub fn getPointer(self: *Self) ?*Seat.Pointer {
    const pointer = &self.seat.pointer;
    return if (pointer.surface == self) pointer else null;
}

pub fn getDeepestWidgetAtPoint(self: *Self, point: Vec2) ?Widget {
    if (self.widget) |initial_widget| {
        var widget = initial_widget;
        outer: for (1..1000) |_| { // No Infinite Loops
            const children = widget.vtable.getChildren(widget.ptr);
            for (0..children.len) |from_end| {
                const i = children.len - from_end - 1;
                if (point.in(children[i].getMetadata().rect)) {
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
    self.updated = true;
    self.seat.reset();
    if (self.getPointer()) |pointer| {
        if (self.getDeepestWidgetAtPoint(pointer.pos)) |widget_initial| {
            var widget_opt: ?Widget = widget_initial;
            while (widget_opt) |widget| {
                widget.vtable.handleInput(widget.ptr) catch {};
                if (pointer.handled) {
                    break;
                } else {
                    widget_opt = widget.getMetadata().parent;
                }
            } else {
                pointer.setShape(.default);
            }
            if (self.pointer_widget) |prev| {
                // we have already handled in this case
                if (!std.meta.eql(@as(?Widget, prev), widget_opt)) prev.vtable.handleInput(prev.ptr) catch {};
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
    self.beginFrameRetained();
    if (self.widget) |widget| resetInFrame(widget);
    self.widget = null;
}
pub fn beginFrameRetained(self: *Self) void {
    // Check for inputs
    self.handleInputs();

    // Attach correct buffer
    if (!self.currentBuffer().usable) {
        // log.debug("Buffer {} not ready, switching to {}", .{ self.current_buffer, self.current_buffer ^ 1 });
        self.current_buffer ^= 1;
    }
    self.wl_surface.attach(self.currentBuffer().wl_buffer, 0, 0);
}
pub fn resetInFrame(widget: Widget) void {
    // TODO: FIX
    widget.getMetadata().in_frame = false;
    const children = widget.vtable.getChildren(widget.ptr);
    for (children) |child| {
        resetInFrame(child);
    }
}
pub fn clear(self: *Self, color: Style.Color) void {
    @memset(std.mem.bytesAsSlice(u32, self.currentBuffer().shared_memory), @bitCast(color));
}

pub fn endFrame(self: *Self) void {
    // _ = self.currentBuffer().cairo_surf.writeToPng("debug1.png");
    // draw
    // if (self.widget) |widget| {
    //     // log.debug("Attempting to draw widgets", .{});
    //     widget.vtable.proposeSize(widget);
    //     widget.draw(Rect{ .w = @floatFromInt(self.width), .h = @floatFromInt(self.height) }) catch {};
    // }
    if (self.widget == null) return;
    const surface_size = self.size.toVec2();
    // check if we were resized and need to redraw everything
    const root = self.widget.?;
    const root_size = root.getMetadata().size;
    // log.debug("{} {}", .{ surface_size, root_size });
    if (!(std.meta.eql(root_size, surface_size))) {
        if (root_size.larger(surface_size)) {
            self.request_resize(self, root_size.toUVec2());
            // self.resize(@intFromFloat(root_size.x), @intFromFloat(root_size.y)) catch |err| log.err("{}", .{err});
        }
        // log.debug("full redraw, {}", .{rect.getSize()});
        self.redraw_list.clearRetainingCapacity();
        self.redraw_list.append(root) catch unreachable; // root should already be in the list
        root.getMetadata().rect = surface_size.toRectSize();
    }
    for (self.redraw_list.items) |widget| {
        // TODO: draw widgets which appear on top and below if needed
        // Rect{ .w = @floatFromInt(self.width), .h = @floatFromInt(self.height) }
        const md = widget.getMetadata();
        // log.debug("redrawing {} at {}, size: {}", .{ widget, md.rect.point(), md.rect.getSize() });
        self.clip = md.rect;
        const cr = self.getCairoContext();
        cr.clipRect(self.clip);
        defer cr.resetClip();
        // widget.draw(md.rect) catch {};
        root.draw(root.getMetadata().rect) catch {};
        self.wl_surface.damage(
            @intFromFloat(md.rect.x),
            @intFromFloat(md.rect.y),
            @intFromFloat(md.rect.w),
            @intFromFloat(md.rect.h),
        );
        //self.wl_surface.damage( 0, 0, math.maxInt(@TypeOf(self.width)), math.maxInt(@TypeOf(self.height)));
    }
    self.currentBuffer().usable = false;
    if (self.precommit) |precommit| precommit(self);
    self.wl_surface.commit();
    self.redraw_list.clearRetainingCapacity();
    self.seat.transitionState();
    self.updated = false;
}

/// make it so subsequent widgets will be appended to the widget's parent
pub fn end(self: *Self, widget: Widget) void {
    assert(std.meta.eql(@as(?Widget, widget), self.widget));
    if (widget.getMetadata().parent) |parent| {
        self.widget = parent;
    }
}
/// convenience function to draw a frame
pub fn frame(self: *Self) void {
    self.beginFrameRetained();
    self.endFrame();
}
/// attaches a null buffer and commits, does not call precommit
/// this has the result of telling the wayland compositor the surface cannot be shown
pub fn unmap(self: *Self) void {
    self.updated = false;
    self.wl_surface.attach(null, 0, 0);
    self.wl_surface.commit();
}
pub fn remap(self: *Self) void {
    self.wl_surface.commit();
}

pub fn markRedraw(self: *Self, widget: Widget) !void {
    self.updated = true;
    const rect = widget.getMetadata().rect;

    for (0.., self.redraw_list.items) |i, item| {
        const item_rect = item.getMetadata().rect;
        if (item_rect.contains(rect)) {
            return;
        } else if (rect.contains(item_rect)) {
            self.redraw_list.items[i] = widget;
            for ((i + 1).., self.redraw_list.items[(i + 1)..]) |j, item_check| {
                const item_check_rect = item_check.getMetadata().rect;
                if (rect.contains(item_check_rect)) {
                    _ = self.redraw_list.orderedRemove(j);
                }
            }
            return;
        }
    }
    try self.redraw_list.append(widget);
}

/// Add widget as a child of the current widget.
/// Use this if the widget will have no children and subsequent widgets should be added to the parent.
pub fn addWidget(self: *const Self, widget: anytype) !void {
    const wid: Widget = if (@TypeOf(widget) == Widget) widget else Widget.from(widget);
    const md = wid.getMetadata();
    if (self.widget) |parent| {
        md.parent = parent;
        try parent.addChild(wid);
    } else {
        md.parent = null;
    }
}
/// Add widget as a child of the current widget and then make it the current widget.
/// Use this if you wish to add children to the widget.
pub fn addWidgetSetCurrent(self: *Self, widget: anytype) !void {
    try self.addWidget(widget);
    self.setCurrent(widget);
}

pub fn setCurrent(self: *Self, widget: anytype) void {
    const wid: Widget = if (@TypeOf(widget) == Widget) Widget else Widget.from(widget);
    self.widget = wid;
}

pub fn getWidget(self: *Self, id_gen: common.IdGenerator, T: type) !*T {
    const id = id_gen.toId();
    const get_or_put_res = try self.widget_storage.getOrPut(id);
    const ptr: *T = if (get_or_put_res.found_existing) @alignCast(@ptrCast(get_or_put_res.value_ptr.*)) else blk: {
        const wid = try Widget.initWidget(self, T);
        // log.debug("Created {s} widget with id {x} at {*}", .{ @typeName(T), id, wid });
        get_or_put_res.value_ptr.* = wid;
        break :blk wid;
    };
    // check that the widget has not already been used elsewhere in frame
    // log.debug("Created {s} widget with id {x}", .{ @typeName(T), id });
    const widget = Widget.from(ptr);
    if (widget.getMetadata().in_frame) return error.DuplicateId;
    widget.getMetadata().in_frame = true;
    return ptr;
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
    pub fn listener(_: *wl.Buffer, event: wl.Buffer.Event, buffer: *Buffer) void {
        _ = event; // the only event is release
        buffer.usable = true;
        // log.debug("{} Release {*}", .{ @mod(std.time.milliTimestamp(), 60000), buffer });
    }
    pub fn deinit(self: *Buffer) void {
        self.wl_buffer.destroy();
        self.cairo_surf.destroy();
        self.cairo_context.destroy();
    }
    pub fn setListener(self: *Buffer) void {
        self.wl_buffer.setListener(*Buffer, Buffer.listener, self);
    }
};
