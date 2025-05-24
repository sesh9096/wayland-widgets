const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const SourceLocation = std.builtin.SourceLocation;
const cairo = @import("./cairo.zig");
const pango = @import("./pango.zig");
const Surface = @import("./Surface.zig");
// const c = @cImport({
//     @cInclude("freetype/freetype.h");
// });

// var ft_library: c.FT_Library = null;
pub const Widget = struct {
    // pub const Inner = union(enum) {
    //     image: *Image,
    //     text: *Text,
    //     box: *Box,
    //     overlay: *Overlay,
    // };
    pub const Vtable = struct {
        addChild: *const fn (self: *Widget, child: *Widget) (anyerror || AddChildError)!void = addChildNotAllowed,
        draw: *const fn (self: *Widget, surface: *Surface, bounding_box: Rect) anyerror!void = drawBounding,
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
    pub fn drawBounding(_: *Widget, surface: *Surface, bounding_box: Rect) !void {
        // log.debug("Default drawing", .{});
        const cr = surface.currentBuffer().cairo_context;
        const thickness = 3;
        cr.setLineWidth(thickness);
        cr.setSourceRgb(1, 0.5, 0.5);
        cr.roundRect(
            bounding_box.x,
            bounding_box.y,
            bounding_box.width,
            bounding_box.height,
            10,
        );
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
    pub fn create(image: *Image) Widget {
        return Widget{
            .inner = .image{image},
            .draw = Image.draw,
        };
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
    pub fn configure(self: *@This(), surface: *const cairo.Surface) void {
        self.* = Image{ .surface = surface };
    }
};

pub const Text = struct {
    text: [:0]const u8,
    // style: ?Style,
    pub fn draw(self: *Widget, surface: *Surface, bounding_box: Rect) !void {
        const cr = surface.currentBuffer().cairo_context;
        const font_description = pango.FontDescription.fromString("monospace");
        font_description.setAbsoluteSize(pango.SCALE * 11);
        const layout = pango.PangoCairo.createLayout(cr);
        defer layout.free();
        defer font_description.free();
        layout.setFontDescription(font_description);
        layout.setWidth(@intFromFloat(bounding_box.width * pango.SCALE));
        layout.setHeight(@intFromFloat(bounding_box.height * pango.SCALE));
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
    pub fn configure(self: *@This(), text: [:0]const u8) void {
        self.text = text;
    }
};
pub const Overlay = struct {
    // Surface on top of another surface
    children: WidgetList,
    // top_rect: Rect = .{},
    // movable: bool = false,
    fn draw(self: *Widget, surface: *Surface, bounding_box: Rect) !void {
        const overlay = self.getInner(Overlay);
        for (overlay.children.items) |child| {
            try child.vtable.draw(child, surface, bounding_box);
        }
        // try top.vtable.draw(top, surface, self.inner.overlay.top_rect);
    }
    pub fn addChild(self: *Widget, child: *Widget) !void {
        // log.debug("adding child", .{});
        const overlay = self.getInner(Overlay);
        try overlay.children.append(child);
        // try overlay.inner.box.children.append(child);
    }
    pub fn configure(self: *Overlay) void {
        self.children.items.len = 0;
    }
    pub fn init(self: *Overlay, allocator: std.mem.Allocator) void {
        self.children = WidgetList.init(allocator);
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
            bounding_box.width - margin * 2,
            bounding_box.height - margin * 2,
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
                    .width = 0,
                    .height = bounding_box.height - spacing * 2,
                };
                const scale = (bounding_box.width - spacing * 2) / @as(f32, @floatFromInt(box.children.items.len));
                for (box.children.items) |child| {
                    const weight = 1;
                    child_box.x = child_box.x + child_box.width;
                    child_box.width = scale * weight;
                    try child.vtable.draw(child, surface, child_box);
                }
            },
            .right => {},
            .up => {},
            .down => {
                var child_box = Rect{
                    .x = bounding_box.x + spacing,
                    .y = bounding_box.y + spacing,
                    .width = bounding_box.width - spacing * 2,
                    .height = 0,
                };
                const scale = (bounding_box.height - spacing * 2) / @as(f32, @floatFromInt(box.children.items.len));
                for (box.children.items) |child| {
                    const weight = 1;
                    child_box.y = child_box.y + child_box.height;
                    child_box.height = scale * weight;
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
    pub fn init(self: *Box, allocator: std.mem.Allocator) void {
        self.children = WidgetList.init(allocator);
    }
    pub fn configure(self: *Box, direction: Direction) void {
        self.children.items.len = 0;
        self.direction = direction;
    }
};
// pub const Style = struct {};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
};

/// Config for generating Id's, use `.id` for direct control or `.src` and optionally `.extra`
pub const IdGenerator = struct {
    src: ?SourceLocation = null,
    extra: ?u32 = null,
    id: ?u32 = null,
    const hash_u32 = std.hash.uint32;
    fn idFromSourceLocation(location: SourceLocation) u32 {
        return hash_u32(location.line) ^ hash_u32(location.column);
    }
    pub fn toId(self: @This()) u32 {
        if (self.id) |id| {
            return id;
        } else {
            const component_location = if (self.src) |loc| idFromSourceLocation(loc) else 0;
            const component_extra = if (self.extra) |extra| hash_u32(extra) else 0;
            const id = component_location ^ component_extra;
            // assert(id != 0);
            return id;
        }
    }
};

test "different sources" {
    const id1 = IdGenerator.toId(.{ .src = @src() });
    const id2 = IdGenerator.toId(.{ .src = @src() });
    if (id1 == id2) return error.DuplicateId;
}

test "different extra" {
    const src = @src();
    const id1 = IdGenerator.toId(.{ .src = src });
    const id2 = IdGenerator.toId(.{ .src = src });
    if (id1 != id2) return error.DifferentId;
    const id3 = IdGenerator.toId(.{ .src = src, .extra = 0 });
    const id4 = IdGenerator.toId(.{ .src = src, .extra = 1 });
    if (id3 == id4) return error.DuplicateId;
}

test "identical id" {
    const id1 = IdGenerator.toId(.{ .id = 3 });
    const id2 = IdGenerator.toId(.{ .id = 3 });
    if (id1 != id2) return error.DifferentId;
}
