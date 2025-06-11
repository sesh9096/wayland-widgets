const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const Direction = common.Direction;
const Rect = common.Rect;
const Point = common.Point;
const Expand = common.Expand;
const WidgetList = std.ArrayList(*Widget);
const Box = @This();

direction: Direction = .right,
expand: Expand,
children: WidgetList,
pub fn init(self: *Box, allocator: std.mem.Allocator) void {
    self.children = WidgetList.init(allocator);
}
pub fn configure(self: *Box, direction: Direction, expand: Expand) void {
    self.expand = expand;
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
pub fn proposeSize(widget: *Widget, surface: *Surface) void {
    // TODO: iterate
    const box = widget.getInner(@This());
    switch (box.direction) {
        .left, .right => {
            var w: f32 = 0;
            var h: f32 = 0;
            for (box.children.items) |child| {
                child.vtable.proposeSize(child, surface);
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
                child.vtable.proposeSize(child, surface);
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
    const hexpand = box.expand.horizontal();
    switch (box.direction) {
        .left => {
            var child_box = Rect{
                .x = rect.x + spacing,
                .y = rect.y + spacing,
                .w = 0,
                .h = rect.h - spacing * 2,
            };
            const scale = (rect.w - spacing * 2) / @as(f32, @floatFromInt(box.children.items.len));
            // expand items
            for (box.children.items) |child| {
                const weight = 1;
                child_box.x = child_box.x + child_box.w;
                child_box.w = if (hexpand) scale * weight else child.rect.w;
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
