const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const Rect = common.Rect;
const Point = common.Point;
const Styles = common.style.Styles;
const Button = @This();

child: ?*Widget,
clicked: bool = false,
pub fn configure(self: *Button) void {
    self.child = null;
}
fn draw(widget: *Widget, surface: *Surface) !void {
    // draw itself
    // const cr = surface.getCairoContext();
    const rect = widget.drawDecorationAdjustSize(surface);
    if (widget.getInner(@This()).child) |child| {
        child.rect = rect;
        try child.vtable.draw(child, surface);
    }
}
pub fn addChild(widget: *Widget, child: *Widget) !void {
    // log.debug("adding child", .{});
    const button = widget.getInner(@This());
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
pub fn proposeSize(self: *Widget, surface: *Surface) void {
    if (self.getInner(@This()).child) |child| {
        child.vtable.proposeSize(child, surface);
        self.rect.w = child.rect.w;
        self.rect.h = child.rect.h;
    } else {
        self.rect.w = 1;
        self.rect.h = 1;
    }
}
pub const default_style = Styles{
    .parent = null,
    .items = &.{ .{ .border_radius = 4 }, .{ .border_width = 1 } },
};
pub var style = &default_style;
pub const vtable = Widget.Vtable{
    .addChild = addChild,
    .getChildren = getChildren,
    .draw = draw,
    .handleInput = handleInput,
    .proposeSize = proposeSize,
};
