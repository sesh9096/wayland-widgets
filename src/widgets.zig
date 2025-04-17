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
    pub const Inner = union(enum) {
        image: *Image,
        text: *Text,
        box: *Box,
        overlay: *Overlay,
    };
    pub const Vtable = struct {
        addChild: *const fn (self: *Widget, child: *Widget) (anyerror || AddChildError)!void = addChildNotAllowed,
        draw: *const fn (self: *Widget, surface: *Surface, bounding_box: Rect) anyerror!void = drawBounding,
    };
    inner: Inner,
    parent: *Widget = undefined,
    rect: Rect = .{},
    vtable: *const Vtable = &.{},
    pub const AddChildError = error{ NoChildrenAllowed, InvalidChild };

    /// for widgets which are base nodes
    pub fn addChildNotAllowed(_: *Widget, _: *Widget) !void {
        return Widget.AddChildError.NoChildrenAllowed;
    }

    /// for widgets which are base nodes
    pub fn drawBounding(_: *Widget, surface: *Surface, bounding_box: Rect) !void {
        log.debug("Default drawing", .{});
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
        cr.setSourceSurface(self.inner.image.surface, bounding_box.x, bounding_box.y);
        log.debug("Drawing image at {} {}", .{ bounding_box.x, bounding_box.y });
        cr.paint();
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
    };
    pub fn widget(allocator: std.mem.Allocator, surface: *const cairo.Surface) !*Widget {
        const wid = try allocator.create(Widget);
        const wid_data = try allocator.create(Image);
        wid_data.* = Image{ .surface = surface };
        wid.* = Widget{
            .vtable = &vtable,
            .inner = .{ .image = wid_data },
        };
        return wid;
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
        layout.setText(self.inner.text.text, -1);
        cr.setSourceRgb(1, 1, 1);
        cr.moveTo(bounding_box.x, bounding_box.y);
        pango.PangoCairo.showLayout(cr, layout);
        // log.debug("Drawing text at {} {}", .{ bounding_box.x, bounding_box.y });
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
    };
    pub fn widget(allocator: std.mem.Allocator, text: [:0]const u8) !*Widget {
        const wid = try allocator.create(Widget);
        const wid_data = try allocator.create(Text);
        wid_data.* = Text{ .text = text };
        wid.* = Widget{
            .vtable = &vtable,
            .inner = .{ .text = wid_data },
        };
        return wid;
    }
};
pub const Overlay = struct {
    // Surface on top of another surface
    children: WidgetList,
    // top_rect: Rect = .{},
    // movable: bool = false,
    fn draw(self: *Widget, surface: *Surface, bounding_box: Rect) !void {
        for (self.inner.overlay.children.items) |child| {
            try child.vtable.draw(child, surface, bounding_box);
        }
        // try top.vtable.draw(top, surface, self.inner.overlay.top_rect);
    }
    pub fn addChild(self: *Widget, child: *Widget) !void {
        // log.debug("adding child", .{});
        const overlay = self.inner.overlay;
        try overlay.children.append(child);
        // try overlay.inner.box.children.append(child);
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
        .addChild = addChild,
    };
    pub fn widget(allocator: std.mem.Allocator) !*Widget {
        const wid = try allocator.create(Widget);
        errdefer allocator.destroy(wid);
        const wid_data = try allocator.create(Overlay);
        errdefer allocator.destroy(wid_data);
        wid_data.* = Overlay{
            .children = WidgetList.init(allocator),
        };
        wid.* = Widget{
            .inner = .{ .overlay = wid_data },
            .vtable = &@This().vtable,
        };
        return wid;
    }
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
        log.debug("Drawing {d}x{d} Box at ({d},{d})", .{ bounding_box.width, bounding_box.height, bounding_box.x, bounding_box.y });
        cr.setSourceRgb(1, 1, 1);
        cr.roundRect(
            bounding_box.x + margin,
            bounding_box.y + margin,
            bounding_box.width - margin * 2,
            bounding_box.height - margin * 2,
            4,
        );

        // draw children
        const box = self.inner.box;
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
        try self.inner.box.children.append(child);
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
        .addChild = addChild,
    };
    pub fn widget(allocator: std.mem.Allocator, direction: Direction) !*Widget {
        const wid = try allocator.create(Widget);
        errdefer allocator.destroy(wid);
        const wid_data = try allocator.create(Box);
        errdefer allocator.destroy(wid_data);
        wid_data.* = Box{
            .direction = direction,
            .children = WidgetList.init(allocator),
        };
        wid.* = Widget{
            .inner = .{ .box = wid_data },
            .vtable = &@This().vtable,
        };
        return wid;
    }
};
// pub const Style = struct {};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,
};

pub const IdGenerator = struct {
    loc: ?SourceLocation = null,
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
            const component_location = if (self.loc) |loc| self.idFromSourceLocation(loc) else 0;
            const component_extra = if (self.extra) |extra| hash_u32(extra) else 0;
            const id = component_location ^ component_extra;
            // assert(id != 0);
            return id;
        }
    }
};
