//! Layer Shell Window
const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const wayland = @import("wayland");
const wlr = wayland.client.zwlr;

const common = @import("./common.zig");
const UVec2 = common.UVec2;
const Surface = common.Surface;
const Context = @import("./Context.zig");

pub const OutputPreference = union(enum) {
    name: []u8,
    all: void,
    default: void,
};

const Self = @This();

layer: wlr.LayerShellV1.Layer,
layer_surface: *wlr.LayerSurfaceV1,
namespace: [*:0]const u8,
anchor: wlr.LayerSurfaceV1.Anchor,
margins: Margins = .{},
output: ?*Context.Output = null,
exclusive: ExclusiveOption = .move,
surface: Surface = undefined,
min_size: common.UVec2 = .{},

pub const ExclusiveOption = enum { ignore, move, exclude };

pub const Margins = struct {
    top: i32 = 0,
    right: i32 = 0,
    bottom: i32 = 0,
    left: i32 = 0,
};

pub fn deinit(self: *Self) void {
    self.surface.deinit();
    self.layer_surface.deinit();
}

pub fn init(
    self: *Self,
    context: *Context,
    layer: wlr.LayerShellV1.Layer,
    output_name: ?[:0]const u8,
    namespace: [*:0]const u8,
    size: common.UVec2,
    anchor: wlr.LayerSurfaceV1.Anchor,
    exclusive: ExclusiveOption,
) !void {
    try self.configure(context, layer, output_name, namespace);
    self.setSize(size);
    self.setAnchor(anchor);
    self.setExclusive(exclusive);
    self.surface.wl_surface.commit();
}

/// configures an uninitialized layer surface, requires stable address in memory
fn configure(
    self: *Self,
    context: *Context,
    layer: wlr.LayerShellV1.Layer,
    output_name: ?[:0]const u8,
    namespace: [*:0]const u8,
) !void {
    const output = if (output_name) |name| (if (context.getOutputWithName(name)) |output| output else blk: {
        log.warn("Layer Surface: output {s} not found", .{name});
        break :blk null;
    }) else null;
    const compositor = context.compositor;
    const wl_surface = try compositor.createSurface();
    const layer_shell = context.layer_shell orelse return error.NoZwlrLayerShell;
    const layer_surface = try layer_shell.getLayerSurface(wl_surface, if (output == null) null else output.?.wl_output, layer, namespace);
    layer_surface.setListener(*Self, listener, self);

    self.layer = layer;
    self.output = output;
    self.namespace = namespace;
    self.layer_surface = layer_surface;
    try self.surface.configure(context.allocator, context.shm, &context.seat, wl_surface);
    self.surface.request_resize = setSizeSurface;
}

fn updateExclusive(self: *Self) void {
    const exclusive = self.exclusive;
    const anchor = self.anchor;
    const layer_surface = self.layer_surface;
    if (exclusive == .ignore) {
        layer_surface.setExclusiveZone(-1);
    } else if (exclusive == .exclude) {
        if (anchor.top != anchor.bottom) {
            layer_surface.setExclusiveZone(@intCast(self.surface.size.y));
        } else if (anchor.left != anchor.right) {
            layer_surface.setExclusiveZone(@intCast(self.surface.size.x));
        }
    }
}
pub fn setExclusive(self: *Self, exclusive: ExclusiveOption) void {
    self.exclusive = exclusive;
    self.updateExclusive();
}
pub fn setLayer(self: *Self, layer: wlr.LayerShellV1.Layer) void {
    self.layer_surface.setLayer(layer);
    self.layer = layer;
}
pub fn setAnchor(self: *Self, anchor: wlr.LayerSurfaceV1.Anchor) void {
    self.anchor = anchor;
    self.layer_surface.setAnchor(anchor);
    self.updateExclusive();
}
pub fn setSize(self: *Self, size: UVec2) void {
    self.layer_surface.setSize(size.x, size.y);
    self.min_size = size;
    // try self.surface.resize(@intCast(width), @intCast(height));
}
pub fn setSizeSurface(surface: *Surface, size: UVec2) void {
    const self: *Self = @fieldParentPtr("surface", surface);
    // log.debug("{}, {}", .{ @max(size.x, self.min_size.x), @max(size.y, self.min_size.y) });
    self.layer_surface.setSize(@max(size.x, self.min_size.x), @max(size.y, self.min_size.y));
}
pub fn getSurface(self: *Self) *Surface {
    return &self.surface;
}

pub fn listener(layer_surface: *wlr.LayerSurfaceV1, event: wlr.LayerSurfaceV1.Event, self: *Self) void {
    switch (event) {
        .configure => |data| {
            // log.debug("Acking layer surface configure, {}", .{data});
            // const w: u32 = if (self.min_size.x == 0) data.width else self.min_size.x;
            // const h: u32 = if (self.min_size.y == 0) data.height else self.min_size.y;
            self.surface.resize(@intCast(data.width), @intCast(data.height)) catch return;
            layer_surface.ackConfigure(data.serial);
            self.layer_surface.setSize(data.width, data.height);
            self.updateExclusive();

            // wl_surface.commit();
        },
        else => {},
    }
}

pub fn surfaceRequestResize(surface: *Surface, new_size: common.UVec2) bool {
    const self: *Self = @fieldParentPtr("surface", surface);
    self.setSize(new_size);
}
