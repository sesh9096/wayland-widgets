//! To implement a widget, create a struct with a `vtable` constant of type Vtable
//! it is also recommended that you create a configure and
const std = @import("std");
const log = std.log;
const common = @import("./common.zig");
const Surface = common.Surface;
const Rect = common.Rect;
const Styles = common.style.Styles;
const Widget = @This();

inner: *anyopaque,
vtable: *const Vtable = &.{},
parent: ?*Widget = null,
surface: *Surface,
styles: ?*const Styles = null,
rect: Rect = .{},
in_frame: bool = false,
redraw: bool = true,
pub const Vtable = struct {
    /// do something to child
    childAction: *const fn (self: *Widget, action: Action, child: *Widget) (std.mem.Allocator.Error || ChildActionError)!void = childActionDefault,
    /// List all children, useful for debugging and to find a widget at a certain point
    /// children should be in ordered so those on top should be at the end
    getChildren: *const fn (widget: *Widget) []*Widget = getChildrenDefault,
    /// draw the widget on the surface
    /// use widget.rect as the rect for drawing
    /// prefer widget.draw(rect), do not use directly unless you have a very good reason
    draw: *const fn (widget: *Widget) anyerror!void = drawDefault,
    /// handle input, call the corresponding function on parent if not handled
    handleInput: *const fn (widget: *Widget) anyerror!void = handleInputDefault,
    /// Propose a size to the parent by setting w/h of `widget.rect`.
    /// Can check children first if desired
    proposeSize: *const fn (widget: *Widget) void = proposeSizeDefault,

    /// for widgets which are base nodes
    pub fn childActionDefault(_: *Widget, action: Action, _: *Widget) !void {
        if (action != .clear) return error.NoChildrenAllowed;
    }

    /// for widgets which are base nodes
    pub fn getChildrenDefault(_: *Widget) []*Widget {
        // don't try to dereference this
        return &.{};
    }

    /// draw where this would be
    pub fn drawDefault(widget: *Widget) !void {
        // log.debug("Default drawing", .{});
        _ = widget.drawDecorationAdjustSize();
    }

    pub fn handleInputDefault(_: *Widget) !void {}

    /// propose a size of nothing by default
    pub fn proposeSizeDefault(widget: *Widget) void {
        widget.rect.w = 0;
        widget.rect.h = 0;
    }
};
pub const Action = enum { add, remove, updated, clear };
pub const ChildActionError = error{ NoChildrenAllowed, InvalidChild };
/// convenience function which does some coercion
pub fn getInner(self: *Widget, T: type) *T {
    return @ptrCast(@alignCast(self.inner));
}

pub fn createWidget(surface: *Surface, T: type) !*Widget {
    const allocator = surface.allocator;
    const wid = try allocator.create(Widget);
    errdefer allocator.destroy(wid);
    const inner = try allocator.create(T);
    wid.* = Widget{
        .vtable = &T.vtable,
        .inner = inner,
        .styles = if (@hasDecl(T, "style")) T.style else null,
        .surface = surface,
        .rect = Rect{},
        .in_frame = false,
        .parent = null,
    };
    if (@hasDecl(T, "init")) T.init(wid);
    return wid;
}

pub fn drawDecorationAdjustSize(widget: *Widget) Rect {
    const surface = widget.surface;
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

/// call widget.vtable.draw on widget, set rectangle, and do some housekeeping
pub fn draw(widget: *Widget, bounding_box: Rect) anyerror!void {
    widget.rect = bounding_box;
    widget.in_frame = false;
    if (widget.redraw) {
        widget.redraw = false;
        try widget.vtable.draw(widget);
    }
}

/// helper function to check on change if we need parent to resize
pub fn needResize(widget: *Widget) bool {
    const rect = widget.rect;
    defer widget.rect = rect;
    widget.vtable.proposeSize(widget);
    return widget.rect.larger(rect);
}

pub fn addChild(widget: *Widget, child: *Widget) !void {
    return widget.vtable.childAction(widget, .add, child);
}

pub fn clearChildren(widget: *Widget) void {
    return widget.vtable.childAction(widget, .clear, undefined) catch unreachable;
}

/// the contents of the widget has changed requiring a rerender
pub fn updated(widget: *Widget) !void {
    widget.redraw = true;
    if (widget.needResize()) {
        if (widget.parent) |parent| {
            try parent.childUpdated(widget);
        } else {
            if (widget == widget.surface.widget) {
                try widget.surface.redraw_list.append(widget);
                log.err("Surface too small to draw widget, has size {}, needs size {}", .{ widget.surface.size, widget.rect.size() });
            }
        }
    } else {
        try widget.surface.redraw_list.append(widget);
    }
}

pub fn childUpdated(widget: *Widget, child: *Widget) !void {
    try widget.vtable.childAction(widget, .updated, child);
}
