const std = @import("std");
const common = @import("./common.zig");
const Surface = common.Surface;
const Rect = common.Rect;
const Widget = @This();

inner: *anyopaque,
parent: ?*Widget = null,
rect: Rect = .{},
vtable: *const Vtable = &.{},
pub const Vtable = struct {
    /// add a child to the widget
    addChild: *const fn (self: *Widget, child: *Widget) (std.mem.Allocator.Error || AddChildError)!void = addChildNotAllowed,
    /// List all children, useful for debugging and to find a widget at a certain point
    /// children should be in ordered so those on top should be at the end
    getChildren: *const fn (widget: *Widget) []*Widget = getChildrenNone,
    /// draw the widget on the surface
    /// use widget.rect as the rect for drawing
    draw: *const fn (widget: *Widget, surface: *Surface) anyerror!void = drawBounding,
    /// handle input, call the corresponding function on parent if not handled
    handleInput: *const fn (widget: *Widget, Surface: *Surface) anyerror!void = handleInputDefault,
    /// Propose a size to the parent by setting w/h of `widget.rect`.
    /// Can check children first if desired
    proposeSize: *const fn (widget: *Widget, surface: *Surface) void = proposeSizeNull,
};
/// convenience function which does some coercion
pub fn getInner(self: *Widget, T: type) *T {
    return @ptrCast(@alignCast(self.inner));
}
pub const AddChildError = error{ NoChildrenAllowed, InvalidChild };

/// for widgets which are base nodes
pub fn addChildNotAllowed(_: *Widget, _: *Widget) !void {
    return Widget.AddChildError.NoChildrenAllowed;
}

/// for widgets which are base nodes
pub fn getChildrenNone(_: *Widget) []*Widget {
    // don't try to dereference this
    var ret: []*Widget = undefined;
    return ret[0..0];
}

/// for widgets which are base nodes
pub fn drawBounding(widget: *Widget, surface: *Surface) !void {
    // log.debug("Default drawing", .{});
    const cr = surface.currentBuffer().cairo_context;
    const bounding_box = widget.rect;
    const thickness = 3;
    cr.setLineWidth(thickness);
    cr.setSourceRgb(1, 0.5, 0.5);
    cr.roundRect(
        bounding_box.x,
        bounding_box.y,
        bounding_box.w,
        bounding_box.h,
        10,
    );
}

/// send input to parent
pub fn handleInputDefault(_: *Widget, _: *Surface) !void {}

/// propose a size of nothing by default
pub fn proposeSizeNull(widget: *Widget, _: *Surface) void {
    widget.rect.w = 0;
    widget.rect.h = 0;
}

pub fn allocateWidget(allocator: std.mem.Allocator, T: type) !*Widget {
    const wid = try allocator.create(Widget);
    errdefer allocator.destroy(wid);
    const wid_data = try allocator.create(T);
    wid.* = Widget{
        .vtable = &T.vtable,
        .inner = wid_data,
    };
    return wid;
}
