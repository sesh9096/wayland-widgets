const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const SourceLocation = std.builtin.SourceLocation;
const cairo = @import("./cairo.zig");
const pango = @import("./pango.zig");
const Surface = @import("./Surface.zig");
const common = @import("./common.zig");
const Rect = common.Rect;
const Point = common.Point;
const IdGenerator = common.IdGenerator;
const Input = Surface.Input;
pub const Widget = struct {
    // pub const Inner = union(enum) {
    //     image: *Image,
    //     text: *Text,
    //     box: *Box,
    //     overlay: *Overlay,
    // };
    pub const Vtable = struct {
        /// add a child to the widget
        addChild: *const fn (self: *Widget, child: *Widget) (std.mem.Allocator.Error || AddChildError)!void = addChildNotAllowed,
        /// List all children, useful for debugging and to find a widget at a certain point
        /// children should be in ordered so those on top should be at the end
        getChildren: *const fn (self: *Widget) []*Widget = getChildrenNone,
        /// draw the widget on the surface
        draw: *const fn (self: *Widget, surface: *Surface, bounding_box: Rect) anyerror!void = drawBounding,
        /// handle input, call the corresponding function on parent if not handled
        handleInput: *const fn (self: *Widget, input: *Input) anyerror!void = handleInputDefault,
        /// Propose a size to the parent by setting w/h of `widget.rect`.
        /// Can check children first if desired
        proposeSize: *const fn (self: *Widget) void = proposeSizeNull,
    };
    // inner: Inner,
    inner: *anyopaque,
    parent: *Widget = undefined,
    rect: Rect = .{},
    vtable: *const Vtable = &.{},
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
    pub fn drawBounding(_: *Widget, surface: *Surface, bounding_box: Rect) !void {
        // log.debug("Default drawing", .{});
        const cr = surface.currentBuffer().cairo_context;
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
    pub fn handleInputDefault(widget: *Widget, input: *Input) !void {
        return if (widget != widget.parent) widget.parent.vtable.handleInput(widget.parent, input);
    }

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
    pub fn draw(self: *Widget, surface: *Surface, bounding_box: Rect) !void {
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
    pub fn draw(self: *Widget, surface: *Surface, bounding_box: Rect) !void {
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
    fn draw(self: *Widget, surface: *Surface, bounding_box: Rect) !void {
        const overlay = self.getInner(Overlay);
        for (overlay.children.items) |child| {
            try child.vtable.draw(child, surface, bounding_box);
        }
        // try top.vtable.draw(top, surface, self.inner.overlay.top_rect);
    }
    pub fn addChild(self: *Widget, child: *Widget) !void {
        // TODO: create an special child type to allow for placing items at specific locations
        const overlay = self.getInner(Overlay);
        try overlay.children.append(child);
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
        .addChild = addChild,
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
    fn draw(self: *Widget, surface: *Surface, bounding_box: Rect) !void {
        // draw itself
        const border_width = 2;
        const margin = 2;
        const padding = 3;
        const cr = surface.currentBuffer().cairo_context;
        cr.setLineWidth(border_width);
        // log.debug("Drawing {d}x{d} Box at ({d},{d})", .{ bounding_box.width, bounding_box.height, bounding_box.x, bounding_box.y });
        cr.setSourceRgb(1, 1, 1);
        cr.roundRect(
            bounding_box.x + margin,
            bounding_box.y + margin,
            bounding_box.w - margin * 2,
            bounding_box.h - margin * 2,
            4,
        );

        // draw children
        const box = self.getInner(@This());
        const spacing = margin + padding;
        switch (box.direction) {
            .left => {
                var child_box = Rect{
                    .x = bounding_box.x + spacing,
                    .y = bounding_box.y + spacing,
                    .w = 0,
                    .h = bounding_box.h - spacing * 2,
                };
                const scale = (bounding_box.w - spacing * 2) / @as(f32, @floatFromInt(box.children.items.len));
                for (box.children.items) |child| {
                    const weight = 1;
                    child_box.x = child_box.x + child_box.w;
                    child_box.w = scale * weight;
                    try child.vtable.draw(child, surface, child_box);
                }
            },
            .right => {},
            .up => {},
            .down => {
                var child_box = Rect{
                    .x = bounding_box.x + spacing,
                    .y = bounding_box.y + spacing,
                    .w = bounding_box.w - spacing * 2,
                    .h = 0,
                };
                const scale = (bounding_box.h - spacing * 2) / @as(f32, @floatFromInt(box.children.items.len));
                for (box.children.items) |child| {
                    const weight = 1;
                    child_box.y = child_box.y + child_box.h;
                    child_box.h = scale * weight;
                    try child.vtable.draw(child, surface, child_box);
                }
            },
        }
    }
    pub fn addChild(self: *Widget, child: *Widget) !void {
        // log.debug("adding child", .{});
        try self.getInner(@This()).children.append(child);
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
        .addChild = addChild,
    };
};

pub const Button = struct {
    child: ?*Widget,
    clicked: bool = false,
    pub fn configure(self: *Button) void {
        self.child = null;
    }
    fn draw(self: *Widget, surface: *Surface, bounding_box: Rect) !void {
        // draw itself
        const border_width = 2;
        const margin = 2;
        const cr = surface.currentBuffer().cairo_context;
        cr.setLineWidth(border_width);
        // log.debug("Drawing {d}x{d} Box at ({d},{d})", .{ bounding_box.width, bounding_box.height, bounding_box.x, bounding_box.y });
        cr.setSourceRgb(1, 1, 1);
        cr.roundRect(
            bounding_box.x + margin,
            bounding_box.y + margin,
            bounding_box.w - margin * 2,
            bounding_box.h - margin * 2,
            4,
        );
        try self.child.vtable.draw(self.child, surface, bounding_box.subtractSpacing(margin, margin));
    }
    pub fn addChild(self: *Widget, child: *Widget) !void {
        // log.debug("adding child", .{});
        if (self.getInner(@This()).child) |child_ptr| {
            child_ptr = child;
        }
    }
    pub fn handleInput(self: *Widget, input: *Input) !void {
        const child = self.getInner(@This()).child;
        const pointer = input.pointer;
        if (!pointer.handled) {
            // let child handle things first
            if (child != null and pointer.in(child.rect)) child.vtable.handleInput(child, input);
            // child might have handled things
            if (!pointer.handled and pointer.in(self.rect)) {
                // button press finished
                if (pointer.button == .left and pointer.state == .released) {
                    self.clicked = true;
                }
            }
        }
        return if (self != self.parent) self.parent.vtable.handleInput(self.parent, input);
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
        .addChild = addChild,
    };
};
