//! To implement a widget, create a struct with a `vtable` constant of type Vtable
//! it is also recommended that you create a configure and
const std = @import("std");
const assert = std.debug.assert;
const log = std.log;
const common = @import("./common.zig");
const Surface = common.Surface;
const Rect = common.Rect;
const Style = common.Style;
const Widget = @This();
const Self = @This();

ptr: *anyopaque,
vtable: *const Vtable = &.{},

pub const Metadata = struct {
    parent: ?Widget = null,
    surface: *Surface,
    style: *const Style,
    rect: Rect = .{},
    in_frame: bool = false,
    redraw: bool = true,

    pub fn drawDecorationAdjustSize(md: *const Metadata) Rect {
        const surface = md.surface;
        const cr = surface.getCairoContext();
        const rect = md.rect;
        const style = md.style;
        const padding = style.getAttribute(.padding);
        const margin = style.getAttribute(.margin);
        const border_rect = rect.subtractSpacing(margin, margin);
        cr.setLineWidth(style.getAttribute(.border_width));
        cr.roundRect(border_rect, style.getAttribute(.border_radius));
        cr.setSourceColor(style.getAttribute(.border_color));
        cr.strokePreserve();
        cr.setSourceColor(style.getAttribute(.bg_color));
        cr.fill();
        return rect.subtractSpacing(padding, padding);
    }

    /// the contents of the widget has changed requiring a rerender
    pub fn updated(md: *Metadata, wid: anytype) !void {
        const surface = md.surface;
        md.redraw = true;
        const widget = from(wid);
        if (widget.needResize()) {
            if (md.parent) |parent| {
                try parent.childUpdated(widget);
            } else {
                if (surface.widget != null and std.meta.eql(widget, surface.widget.?)) {
                    try surface.redraw_list.append(widget);
                    log.err("Surface too small to draw widget, has size {}, needs size {}", .{ surface.size, md.rect.size() });
                }
            }
        } else {
            try surface.redraw_list.append(widget);
        }
    }
};
pub fn getMetadata(self: Self) *Metadata {
    return @alignCast(@ptrCast(@as([*]u8, @ptrCast(self.ptr)) + self.vtable.metadata_offset));
}
pub inline fn getMetadataOffset(T: type) u64 {
    for (@typeInfo(T).Struct.fields) |field| {
        if (field.type == Metadata) {
            return @offsetOf(T, field.name);
        }
    }
}
pub const Vtable = struct {
    /// do something to child
    childAction: *const fn (self: *anyopaque, action: Action, child: Widget) (std.mem.Allocator.Error || ChildActionError)!void = childActionDefault,
    /// List all children, useful for debugging and to find a widget at a certain point
    /// children should be in ordered so those on top should be at the end
    getChildren: *const fn (self: *anyopaque) []Widget = getChildrenDefault,
    /// draw the widget on the surface
    /// use widget.rect as the rect for drawing
    /// prefer widget.draw(rect), do not use directly unless you have a very good reason
    draw: *const fn (self: *anyopaque) anyerror!void = drawDefault,
    /// handle input, call the corresponding function on parent if not handled
    handleInput: *const fn (self: *anyopaque) anyerror!void = handleInputDefault,
    /// Propose a size to the parent by setting w/h of `widget.rect`.
    /// Can check children first if desired
    proposeSize: *const fn (self: *anyopaque, rect: *Rect) void = proposeSizeDefault,
    /// number of bytes to add to base pointer to get metadata
    metadata_offset: u64 = 0,

    /// for widgets which are base nodes
    pub fn childActionDefault(_: *anyopaque, action: Action, _: Widget) !void {
        if (action != .clear) return error.NoChildrenAllowed;
    }

    /// for widgets which are base nodes
    pub fn getChildrenDefault(_: *anyopaque) []Widget {
        // don't try to dereference this
        return &.{};
    }

    /// draw nothing
    pub fn drawDefault(_: *anyopaque) !void {}

    pub fn handleInputDefault(_: *anyopaque) !void {}

    /// propose a size of nothing by default
    pub fn proposeSizeDefault(_: *anyopaque, rect: *Rect) void {
        rect.w = 0;
        rect.h = 0;
    }

    pub inline fn forType(T: type) Vtable {
        var vtable = Vtable{};
        for (@typeInfo(Vtable).Struct.fields) |field| {
            if (@hasDecl(T, field.name)) {
                if (@typeInfo(field.type) == .Pointer) {
                    const fun = @field(T, field.name);
                    const fn_info = @typeInfo(@TypeOf(fun)).Fn;
                    const target_fn_info = @typeInfo(@typeInfo(field.type).Pointer.child).Fn;
                    const error_msg = @typeName(T) ++ "." ++ field.name ++ " has type " ++ @typeName(@TypeOf(fun)) ++ " which is incompatible with " ++ @typeName(@TypeOf(@field(vtable, field.name)));
                    // check first arg
                    if (fn_info.params[0].type != *T and fn_info.params[0].type != *anyopaque) @compileError("function " ++ field.name ++ " of type " ++ @typeName(T) ++ " must have first argument of type *" ++ @typeName(T));
                    // check remaining args
                    if (fn_info.params.len != target_fn_info.params.len) {
                        @compileError(error_msg);
                    }
                    for (fn_info.params[1..], target_fn_info.params[1..]) |param, target_param| {
                        if (param.type != target_param.type) {
                            @compileError(error_msg);
                        }
                    }
                    // check return type
                    const return_type_info = @typeInfo(fn_info.return_type.?);
                    const target_return_type_info = @typeInfo(target_fn_info.return_type.?);
                    if (return_type_info == .ErrorUnion) {
                        const error_set = return_type_info.ErrorUnion.error_set;
                        const desired_error_set = target_return_type_info.ErrorUnion.error_set;
                        if ((error_set || desired_error_set) != desired_error_set) {
                            @compileError(@typeName(error_set || desired_error_set));
                            // @compileError(error_msg);
                        }
                        if (return_type_info.ErrorUnion.payload != target_return_type_info.ErrorUnion.payload) {
                            @compileError(error_msg);
                        }
                    } else {
                        if (!std.meta.eql(fn_info.return_type, target_fn_info.return_type)) {
                            @compileError(error_msg);
                        }
                    }
                    @field(vtable, field.name) = @ptrCast(&fun);
                } else {
                    @field(vtable, field.name) = @intCast(@field(T, field.name));
                }
            } else if (std.mem.eql(u8, field.name, "metadata_offset")) {
                for (@typeInfo(T).Struct.fields) |sfield| {
                    if (sfield.type == Metadata) {
                        vtable.metadata_offset = @offsetOf(T, sfield.name);
                    }
                }
            }
        }
        return vtable;
    }
};
pub const Action = enum { add, remove, updated, clear };
pub const ChildActionError = error{ NoChildrenAllowed, InvalidChild };

pub fn from(widget: anytype) Widget {
    const type_info = @typeInfo(@TypeOf(widget));
    assert(type_info == .Pointer);
    return .{
        .vtable = &type_info.Pointer.child.vtable,
        .ptr = @alignCast(@ptrCast(widget)),
    };
}

pub fn initWidget(surface: *Surface, T: type) !*T {
    const allocator = surface.allocator;
    const ptr = try allocator.create(T);
    from(ptr).getMetadata().* = .{
        .style = &surface.style,
        .surface = surface,
        .rect = Rect{},
        .in_frame = false,
        .parent = null,
    };
    if (@hasDecl(T, "init")) ptr.init();
    return ptr;
}
pub fn getInner(self: *Widget, T: type) *T {
    return @ptrCast(@alignCast(self.ptr));
}

/// call widget.vtable.draw on widget, set rectangle, and do some housekeeping
pub fn draw(widget: Widget, bounding_box: Rect) anyerror!void {
    const md = widget.getMetadata();
    md.rect = bounding_box;
    md.in_frame = false;
    if (md.redraw or !std.meta.eql(md.rect, bounding_box)) {
        md.redraw = false;
        try widget.vtable.draw(md);
    }
}

/// helper function to check on change if we need parent to resize
pub fn needResize(widget: Widget) bool {
    var rect: Rect = undefined;
    widget.vtable.proposeSize(widget.ptr, &rect);
    return rect.larger(widget.getMetadata().rect);
}

pub fn addChild(widget: Widget, child: Widget) !void {
    return widget.vtable.childAction(widget.ptr, .add, child);
}

pub fn clearChildren(widget: Widget) void {
    return widget.vtable.childAction(widget.ptr, .clear, undefined) catch unreachable;
}

pub fn childUpdated(widget: Widget, child: Widget) !void {
    try widget.vtable.childAction(widget.ptr, .updated, child);
}
