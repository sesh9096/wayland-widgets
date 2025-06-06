const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const Rect = common.Rect;
const Point = common.Point;
const Button = @This();

child: ?*Widget,
clicked: bool = false,
pub fn configure(self: *Button) void {
    self.child = null;
}
fn draw(self: *Widget, surface: *Surface) !void {
    // draw itself
    const border_width = 2;
    const margin = 2;
    const cr = surface.currentBuffer().cairo_context;
    cr.setLineWidth(border_width);
    const rect = self.rect;
    // log.debug("Drawing {d}x{d} Box at ({d},{d})", .{ rect.width, rect.height, rect.x, rect.y });
    cr.setSourceRgb(1, 1, 1);
    cr.roundRect(
        rect.x + margin,
        rect.y + margin,
        rect.w - margin * 2,
        rect.h - margin * 2,
        4,
    );
    if (self.getInner(@This()).child) |child| {
        child.rect = rect.subtractSpacing(margin, margin);
        try child.vtable.draw(child, surface);
    }
}
pub fn addChild(self: *Widget, child: *Widget) !void {
    // log.debug("adding child", .{});
    const button = self.getInner(@This());
    if (button.child) |_| {
        return error.InvalidChild;
    } else button.child = child;
}
pub fn getChildren(self: *Widget) []*Widget {
    // don't try to dereference this
    if (self.getInner(@This()).child) |*child_ptr| {
        // var ret: []*Widget = undefined;
        // ret.ptr = child_ptr;
        return child_ptr[0..1];
    } else {
        var ret: []*Widget = undefined;
        return ret[0..0];
    }
}
pub fn handleInput(widget: *Widget, surface: *Surface) !void {
    const button = widget.getInner(@This());
    if (surface.getPointer()) |pointer| {
        // pointer events possible
        if (!pointer.handled and pointer.in(widget.rect)) {
            pointer.setShape(.pointer);
            if (pointer.button == .left and pointer.state == .released) {
                button.clicked = true;
            } else {
                button.clicked = false;
            }
            pointer.handled = true;
        } else {
            button.clicked = false;
        }
    }
}
pub fn proposeSize(self: *Widget) void {
    if (self.getInner(@This()).child) |child| {
        child.vtable.proposeSize(child);
        self.rect.w = child.rect.w;
        self.rect.h = child.rect.h;
    } else {
        self.rect.w = 1;
        self.rect.h = 1;
    }
}
pub const vtable = Widget.Vtable{
    .addChild = addChild,
    .getChildren = getChildren,
    .draw = draw,
    .handleInput = handleInput,
    .proposeSize = proposeSize,
};
