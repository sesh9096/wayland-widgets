//! Layer Shell Window
const wayland = @import("wayland");
const wlr = wayland.client.zwlr;

const widgets = @import("./widgets.zig");
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
widget: widgets.Widget,
namespace: [*:0]const u8,
exclusiveZone: i32,
anchor: wlr.LayerSurfaceV1.Anchor,
margins: Margins = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
width: u32 = 0,
height: u32 = 0,

surface: ?*Surface,
pub const Margins = struct {
    top: i32,
    right: i32,
    bottom: i32,
    left: i32,
};
pub fn drawWidgets(self: *Self) void {
    self.surface.?.drawWidget(self.widget);
}

pub fn deinit(self: *Self) void {
    if (self.surface) |surface| {
        surface.deinit();
    }
}
