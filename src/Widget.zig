const std = @import("std");
const common = @import("./common.zig");
const Surface = common.Surface;
const Rect = common.Rect;
const Styles = common.style.Styles;
const Widget = @This();

inner: *anyopaque,
parent: ?*Widget = null,
rect: Rect = .{},
styles: ?*const Styles = null,
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
    _ = widget.drawDecorationAdjustSize(surface);
}

/// send input to parent
pub fn handleInputDefault(_: *Widget, _: *Surface) !void {}

/// propose a size of nothing by default
pub fn proposeSizeNull(widget: *Widget, _: *Surface) void {
    widget.rect.w = 0;
    widget.rect.h = 0;
}

pub fn createWidget(surface: *Surface, T: type) !*Widget {
    const allocator = surface.allocator;
    const wid = try allocator.create(Widget);
    errdefer allocator.destroy(wid);
    const inner = try allocator.create(T);
    if (@hasDecl(T, "init")) inner.init(surface.allocator);
    if (@hasDecl(T, "surface")) inner.surface = surface;
    wid.* = Widget{
        .vtable = &T.vtable,
        .inner = inner,
        .styles = if (@hasDecl(T, "style")) T.style else null,
    };
    return wid;
}

pub fn drawDecorationAdjustSize(widget: *Widget, surface: *Surface) Rect {
    const cr = surface.getCairoContext();
    const rect = widget.rect;
    const style = if (widget.styles) |style| style else surface.styles;
    const fallback = if (widget.styles) |_| surface.styles else null;
    const padding = style.getAttribute(.padding, fallback);
    const margin = style.getAttribute(.margin, fallback);
    const border_rect = rect.subtractSpacing(margin, margin);
    cr.setLineWidth(style.getAttribute(.border_width, fallback));
    cr.roundRect(border_rect, style.getAttribute(.border_radius, fallback));
    cr.setSourceColor(style.getAttribute(.border_color, fallback));
    cr.strokePreserve();
    cr.setSourceColor(style.getAttribute(.bg_color, fallback));
    cr.fill();
    return rect.subtractSpacing(padding, padding);
}

/// call widget.vtable.draw on widget
pub fn draw(widget: *Widget, surface: *Surface, bounding_box: Rect) anyerror!void {
    widget.rect = bounding_box;
    try widget.vtable.draw(widget, surface);
}
