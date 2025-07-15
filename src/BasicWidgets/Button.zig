const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const Rect = common.Rect;
const Vec2 = common.Vec2;
const Styles = common.style.Styles;
const Button = @This();

child: ?*Widget,
clicked: bool = false,
pub fn configure(self: *Button) void {
    self.child = null;
}
fn draw(widget: *Widget) !void {
    // draw itself
    // const cr = surface.getCairoContext();
    const rect = widget.drawDecorationAdjustSize();
    if (widget.getInner(@This()).child) |child| {
        try child.draw(rect);
    }
}
pub fn childAction(widget: *Widget, action: Widget.Action, child: *Widget) !void {
    // log.debug("adding child", .{});
    const button = widget.getInner(@This());
    switch (action) {
        .add => {
            if (button.child) |_| {
                return error.InvalidChild;
            } else button.child = child;
        },
        .clear => button.child = null,
        .remove => {
            if (button.child == child) {
                button.child = null;
            } else {
                return error.InvalidChild;
            }
        },
        .updated => {
            try widget.parent.?.vtable.childAction(widget.parent.?, .updated, widget);
        },
    }
}
pub fn getChildren(widget: *Widget) []*Widget {
    // don't try to dereference this
    if (widget.getInner(@This()).child) |*child_ptr| {
        // var ret: []*Widget = undefined;
        // ret.ptr = child_ptr;
        return child_ptr[0..1];
    } else {
        var ret: []*Widget = undefined;
        return ret[0..0];
    }
}
pub fn handleInput(widget: *Widget) !void {
    const surface = widget.surface;
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
pub fn proposeSize(widget: *Widget) void {
    if (widget.getInner(@This()).child) |child| {
        child.vtable.proposeSize(child);
        widget.rect.w = child.rect.w;
        widget.rect.h = child.rect.h;
    } else {
        widget.rect.w = 1;
        widget.rect.h = 1;
    }
}
pub const default_style = Styles{
    .parent = null,
    .items = &.{ .{ .border_radius = 4 }, .{ .border_width = 1 } },
};
pub var style = &default_style;
pub const vtable = Widget.Vtable{
    .childAction = childAction,
    .getChildren = getChildren,
    .draw = draw,
    .handleInput = handleInput,
    .proposeSize = proposeSize,
};
