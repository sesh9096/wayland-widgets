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
child: ?Widget,
clicked: bool = false,
pub fn configure(self: *Self) void {
    self.child = null;
}
fn draw(self: *Self) !void {
    // draw itself
    // const cr = surface.getCairoContext();
    const rect = self.md.drawDecorationAdjustSize();
    if (self.child) |child| {
        try child.draw(rect);
    }
}
pub fn childAction(self: *Self, action: Widget.Action, child: Widget) !void {
    // log.debug("adding child", .{});
    switch (action) {
        .add => {
            if (self.child) |_| {
                return error.InvalidChild;
            } else self.child = child;
        },
        .clear => self.child = null,
        .remove => {
            if (std.meta.eql(self.child, @as(?Widget, child))) {
                self.child = null;
            } else {
                return error.InvalidChild;
            }
        },
        .updated => {
            try self.md.updated(self);
        },
    }
}
pub fn getChildren(self: *Self) []Widget {
    // don't try to dereference this
    if (self.child) |*child| {
        // var ret: []*Widget = undefined;
        // ret.ptr = child_ptr;
        return child[0..1];
    } else {
        return &.{};
    }
}
pub fn handleInput(self: *Self) !void {
    const surface = self.md.surface;
    if (surface.getPointer()) |pointer| {
        // pointer events possible
        if (!pointer.handled and pointer.in(self.md.rect)) {
            pointer.setShape(.pointer);
            if (pointer.button == .left and pointer.state == .released) {
                self.clicked = true;
            } else {
                self.clicked = false;
            }
            pointer.handled = true;
        } else {
            self.clicked = false;
        }
    }
}
pub fn proposeSize(self: *Self, rect: *Rect) void {
    if (self.child) |child| {
        const child_rect = &child.getMetadata().rect;
        child.vtable.proposeSize(child.ptr, child_rect);
        rect.w = child_rect.w;
        rect.h = child_rect.h;
    } else {
        rect.w = 1;
        rect.h = 1;
    }
}
pub const default_style = Style{
    .parent = null,
    .items = &.{ .{ .border_radius = 4 }, .{ .border_width = 1 } },
};
pub var style = &default_style;
pub const vtable = Widget.Vtable.forType(Self);
