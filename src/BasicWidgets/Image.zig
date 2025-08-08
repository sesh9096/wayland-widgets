const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const Rect = common.Rect;
const Vec2 = common.Vec2;
const Style = common.Style;
const Self = @This();

md: Widget.Metadata,
surface: *const cairo.Surface,
option: Option = .stretch,
size: Vec2,
hash: u32,
pub const Option = enum { stretch, fit, fill, center, tile };
pub fn configure(self: *Self, surface: *const cairo.Surface, option: Option) void {
    if (self.surface != surface) {
        Widget.updated(self) catch unreachable;
        self.surface = surface;
    }
    self.option = option;
    self.size = .{ .x = @floatFromInt(surface.getWidth()), .y = @floatFromInt(surface.getHeight()) };
}
pub fn draw(self: *Self) !void {
    const md = self.md;
    const surface = md.surface;
    const rect = md.rect;
    const cr = surface.currentBuffer().cairo_context;
    const image_surface = self.surface;
    const option = self.option;
    const size = self.size;
    cr.save();
    defer cr.restore();
    switch (option) {
        .stretch => {
            cr.scale(rect.w / size.x, rect.h / size.y);
            cr.setSourceSurface(image_surface, rect.x, rect.y);
        },
        .fit => {
            cr.setSourceSurface(image_surface, rect.x, rect.y);
        },
        .fill => {
            cr.setSourceSurface(image_surface, rect.x, rect.y);
        },
        .center => {
            cr.setSourceSurface(image_surface, rect.x, rect.y);
        },
        .tile => {
            cr.setSourceSurface(image_surface, rect.x, rect.y);
        },
    }
    cr.paint();
}
pub const vtable = Widget.Vtable.forType(Self);
