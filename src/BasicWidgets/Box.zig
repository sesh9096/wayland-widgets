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
    // const cr = surface.getCairoContext();
    var rect = widget.drawDecorationAdjustSize(surface);
    // cr.setLineWidth(border_width);
    // cr.setSourceColor(.{ .r = 0xff, .g = 0xff, .b = 0xff });
    // cr.roundRect(
    //     rect.subtractSpacing(margin, margin),
    //     4,
    // );

    // draw children
    const box = widget.getInner(@This());
    const hexpand = box.expand.horizontal();
    const vexpand = box.expand.vertical();
    switch (box.direction) {
        .left => {},
        .right => {
            var min_width: f32 = 0;
            var total_weight: f32 = 0;
            for (box.children.items) |child| {
                if (child.rect.w == 0) {
                    total_weight += 1;
                } else {
                    min_width += child.rect.w;
                }
            }
            const remaining_space = rect.w - min_width;
            rect.w = 0;
            const scale = remaining_space / total_weight;
            // expand items
            for (box.children.items) |child| {
                const weight = 1;
                rect.x = rect.x + rect.w;
                rect.w = if (hexpand or child.rect.w == 0) scale * weight else child.rect.w;
                try child.draw(surface, rect);
            }
        },
        .up => {},
        .down => {
            var min_width: f32 = 0;
            var total_weight: f32 = 0;
            for (box.children.items) |child| {
                if (child.rect.h == 0) {
                    total_weight += 1;
                } else {
                    min_width += child.rect.h;
                }
            }
            const remaining_space = rect.h - min_width;
            rect.h = 0;
            const scale = remaining_space / total_weight;
            for (box.children.items) |child| {
                const weight = 1;
                rect.y = rect.y + rect.h;
                rect.h = if (vexpand or child.rect.h == 0) scale * weight else child.rect.h;
                try child.draw(surface, rect);
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
