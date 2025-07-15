const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const Direction = common.Direction;
const Rect = common.Rect;
const Vec2 = common.Vec2;
const Expand = common.Expand;
const BasicWidgets = @import("../BasicWidgets.zig");
const WidgetList = BasicWidgets.WidgetList;
const indexOfWidget = BasicWidgets.indexOfWidget;
const Box = @This();

direction: Direction = .right,
expand: Expand,
children: WidgetList,
pub fn init(widget: *Widget) void {
    const self = widget.getInner(@This());
    self.children = WidgetList.init(widget.surface.allocator);
}
pub fn configure(self: *Box, direction: Direction, expand: Expand) void {
    self.expand = expand;
    self.direction = direction;
}

pub fn childAction(widget: *Widget, action: Widget.Action, child: *Widget) !void {
    // log.debug("adding child", .{});
    const box = widget.getInner(@This());
    switch (action) {
        .add => {
            try box.children.append(child);
            try widget.updated();
        },
        .clear => {
            for (box.children.items) |chld| {
                chld.parent = null;
            }
            box.children.items.len = 0;
        },
        .remove => {
            if (indexOfWidget(box.children, child)) |index| {
                _ = box.children.orderedRemove(index);
            } else {
                return error.InvalidChild;
            }
        },
        .updated => {
            if (indexOfWidget(box.children, child)) |index| {
                try widget.updated();
                _ = index;
            } else {
                return error.InvalidChild;
            }
        },
        // .commit => {
        //     try widget.updated();
        // },
    }
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
pub fn draw(widget: *Widget) !void {
    // draw itself
    // const cr = surface.getCairoContext();
    // draw children
    var rect = widget.drawDecorationAdjustSize();
    const box = widget.getInner(@This());
    const hexpand = box.expand.horizontal();
    const vexpand = box.expand.vertical();
    switch (box.direction) {
        .left, .right => {
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
                try child.draw(rect);
            }
        },
        .up, .down => {
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
                try child.draw(rect);
            }
        },
    }
}
pub const vtable = Widget.Vtable{
    .childAction = childAction,
    .getChildren = getChildren,
    .draw = draw,
    .proposeSize = proposeSize,
};
