const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const cairo = @import("./cairo.zig");
const pango = @import("./pango.zig");
const Surface = @import("./Surface.zig");
const common = @import("./common.zig");
const Rect = common.Rect;
const Point = common.Point;
pub const Widget = struct {
    pub const Vtable = struct {
        /// add a child to the widget
        addChild: *const fn (self: *Widget, child: *Widget) (std.mem.Allocator.Error || AddChildError)!void = addChildNotAllowed,
        /// List all children, useful for debugging and to find a widget at a certain point
        /// children should be in ordered so those on top should be at the end
        getChildren: *const fn (self: *Widget) []*Widget = getChildrenNone,
        /// draw the widget on the surface
        /// use widget.rect as the rect for drawing
        draw: *const fn (self: *Widget, surface: *Surface) anyerror!void = drawBounding,
        /// handle input, call the corresponding function on parent if not handled
        handleInput: *const fn (self: *Widget, Surface: *Surface) anyerror!void = handleInputDefault,
        /// Propose a size to the parent by setting w/h of `widget.rect`.
        /// Can check children first if desired
        proposeSize: *const fn (self: *Widget) void = proposeSizeNull,
    };
    inner: *anyopaque,
    parent: ?*Widget = null,
    rect: Rect = .{},
    vtable: *const Vtable = &.{},
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
    pub fn proposeSizeNull(self: *Widget) void {
        self.rect.w = 0;
        self.rect.h = 0;
    }
};
const WidgetList = std.ArrayList(*Widget);

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

pub const Image = struct {
    surface: *const cairo.Surface,
    pub fn configure(self: *@This(), surface: *const cairo.Surface) void {
        self.* = Image{ .surface = surface };
    }
    pub fn draw(self: *Widget, surface: *Surface) !void {
        const bounding_box = self.rect;
        const cr = surface.currentBuffer().cairo_context;
        cr.setSourceSurface(self.getInner(@This()).surface, bounding_box.x, bounding_box.y);
        // log.debug("Drawing image at {} {}", .{ bounding_box.x, bounding_box.y });
        cr.paint();
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
    };
};

pub const Text = struct {
    text: [:0]const u8,
    pub fn configure(self: *@This(), text: [:0]const u8) void {
        self.text = text;
    }
    pub fn draw(self: *Widget, surface: *Surface) !void {
        const bounding_box = self.rect;
        const cr = surface.currentBuffer().cairo_context;
        const font_description = pango.FontDescription.fromString("monospace");
        font_description.setAbsoluteSize(pango.SCALE * 11);
        const layout = pango.PangoCairo.createLayout(cr);
        defer layout.free();
        defer font_description.free();
        layout.setFontDescription(font_description);
        layout.setWidth(@intFromFloat(bounding_box.w * pango.SCALE));
        layout.setHeight(@intFromFloat(bounding_box.h * pango.SCALE));
        const text = self.getInner(@This()).text;
        layout.setText(text, -1);
        cr.setSourceRgb(1, 1, 1);
        cr.moveTo(bounding_box.x, bounding_box.y);
        pango.PangoCairo.showLayout(cr, layout);
        // log.debug("Drawing text {} at {} {}", .{ text, bounding_box.x, bounding_box.y });
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
    };
};

/// draw multiple widgets on top of each other
pub const Overlay = struct {
    children: WidgetList,
    pub fn init(self: *Overlay, allocator: std.mem.Allocator) void {
        self.children = WidgetList.init(allocator);
    }
    pub fn configure(self: *Overlay) void {
        self.children.items.len = 0;
    }
    fn draw(self: *Widget, surface: *Surface) !void {
        const overlay = self.getInner(@This());
        for (overlay.children.items) |child| {
            child.rect = self.rect;
            try child.vtable.draw(child, surface);
        }
        // try top.vtable.draw(top, surface, self.inner.overlay.top_rect);
    }
    pub fn addChild(self: *Widget, child: *Widget) !void {
        // TODO: create an special child type to allow for placing items at specific locations
        const overlay = self.getInner(@This());
        try overlay.children.append(child);
    }
    pub fn getChildren(self: *Widget) []*Widget {
        // TODO: create an special child type to allow for placing items at specific locations
        const overlay = self.getInner(@This());
        return overlay.children.items;
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
        .addChild = addChild,
        .getChildren = getChildren,
    };
};
pub const Direction = enum {
    left,
    right,
    up,
    down,
};
pub const Box = struct {
    direction: Direction = .right,
    children: WidgetList,
    pub fn init(self: *Box, allocator: std.mem.Allocator) void {
        self.children = WidgetList.init(allocator);
    }
    pub fn configure(self: *Box, direction: Direction) void {
        self.children.items.len = 0;
        self.direction = direction;
    }

    pub fn addChild(widget: *Widget, child: *Widget) !void {
        // log.debug("adding child", .{});
        try widget.getInner(@This()).children.append(child);
    }
    pub fn getChildren(widget: *Widget) []*Widget {
        return widget.getInner(@This()).children.items;
    }
    pub fn proposeSize(widget: *Widget) void {
        // TODO: iterate
        const box = widget.getInner(@This());
        switch (box.direction) {
            .left, .right => {
                var w: f32 = 0;
                var h: f32 = 0;
                for (box.children.items) |child| {
                    child.vtable.proposeSize(child);
                    w += child.rect.w;
                    h = @max(h, child.rect.h);
                }
                widget.rect.h = h;
                widget.rect.w = w;
            },
            .down, .up => {
                var w: f32 = 0;
                var h: f32 = 0;
                for (box.children.items) |child| {
                    child.vtable.proposeSize(child);
                    w = @max(w, child.rect.w);
                    h += child.rect.h;
                }
                widget.rect.h = h;
                widget.rect.w = w;
            },
        }
    }
    fn draw(widget: *Widget, surface: *Surface) !void {
        // draw itself
        const rect = widget.rect;
        const border_width = 2;
        const margin = 2;
        const padding = 3;
        const cr = surface.currentBuffer().cairo_context;
        cr.setLineWidth(border_width);
        cr.setSourceRgb(1, 1, 1);
        cr.roundRect(
            rect.x + margin,
            rect.y + margin,
            rect.w - margin * 2,
            rect.h - margin * 2,
            4,
        );

        // draw children
        const box = widget.getInner(@This());
        const spacing = margin + padding;
        switch (box.direction) {
            .left => {
                var child_box = Rect{
                    .x = rect.x + spacing,
                    .y = rect.y + spacing,
                    .w = 0,
                    .h = rect.h - spacing * 2,
                };
                const scale = (rect.w - spacing * 2) / @as(f32, @floatFromInt(box.children.items.len));
                for (box.children.items) |child| {
                    const weight = 1;
                    child_box.x = child_box.x + child_box.w;
                    child_box.w = scale * weight;
                    child.rect = child_box;
                    try child.vtable.draw(child, surface);
                }
            },
            .right => {},
            .up => {},
            .down => {
                var child_box = Rect{
                    .x = rect.x + spacing,
                    .y = rect.y + spacing,
                    .w = rect.w - spacing * 2,
                    .h = 0,
                };
                const scale = (rect.h - spacing * 2) / @as(f32, @floatFromInt(box.children.items.len));
                for (box.children.items) |child| {
                    const weight = 1;
                    child_box.y = child_box.y + child_box.h;
                    child_box.h = scale * weight;
                    child.rect = child_box;
                    try child.vtable.draw(child, surface);
                }
            },
        }
    }
    pub const vtable = Widget.Vtable{
        .addChild = addChild,
        .getChildren = getChildren,
        .draw = draw,
        .proposeSize = proposeSize,
    };
};

pub const Button = struct {
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
};
