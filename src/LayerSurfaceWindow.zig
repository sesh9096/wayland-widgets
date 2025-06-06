//! Layer Shell Window
const std = @import("std");
const assert = std.debug.assert;
const wayland = @import("wayland");
const wlr = wayland.client.zwlr;

const Surface = @import("./Surface.zig");
const Context = @import("./main.zig").Context;
const Self = @This();
pub const OutputPreference = union(enum) {
    name: []u8,
    all: void,
    default: void,
};
output: OutputPreference = .default,
layer: wlr.LayerShellV1.Layer,
namespace: [*:0]const u8,
exclusiveZone: i32,
anchor: wlr.LayerSurfaceV1.Anchor,
margins: Margins = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
width: u32 = 0,
height: u32 = 0,

pub const Margins = struct {
    top: i32,
    right: i32,
    bottom: i32,
    left: i32,
};

pub fn deinit() void {}

pub fn listener(layer_surface: *wlr.LayerSurfaceV1, event: wlr.LayerSurfaceV1.Event, window: *const @This()) void {
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
