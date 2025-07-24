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
const Self = @This();

md: Widget.Metadata,
direction: Direction = .right,
expand: Expand,
children: WidgetList,
pub fn init(self: *Self) void {
    self.children = WidgetList.init(self.md.surface.allocator);
}
pub fn configure(self: *Self, direction: Direction, expand: Expand) void {
    self.expand = expand;
    self.direction = direction;
}

pub fn childAction(self: *Self, action: Widget.Action, child: Widget) !void {
    // log.debug("adding child", .{});
    switch (action) {
        .add => {
            try self.children.append(child);
            try Widget.updated(self);
        },
        .clear => {
            for (self.children.items) |chld| {
                chld.getMetadata().parent = null;
            }
            self.children.items.len = 0;
        },
        .remove => {
            if (indexOfWidget(self.children, child)) |index| {
                _ = self.children.orderedRemove(index);
            } else {
                return error.InvalidChild;
            }
        },
        .updated => {
            if (indexOfWidget(self.children, child)) |index| {
                try Widget.updated(self);
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
pub fn getChildren(self: *Self) []Widget {
    return self.children.items;
}
pub fn proposeSize(self: *Self, rect: *Rect) void {
    // TODO: iterate
    switch (self.direction) {
        .left, .right => {
            var w: f32 = 0;
            var h: f32 = 0;
            for (self.children.items) |child| {
                const md = child.getMetadata();
                child.vtable.proposeSize(child.ptr, &md.rect);
                w += md.rect.w;
                h = @max(h, md.rect.h);
            }
            rect.h = h;
            rect.w = w;
        },
        .down, .up => {
            var w: f32 = 0;
            var h: f32 = 0;
            for (self.children.items) |child| {
                const md = child.getMetadata();
                child.vtable.proposeSize(child.ptr, &md.rect);
                w = @max(w, md.rect.w);
                h += md.rect.h;
            }
            rect.h = h;
            rect.w = w;
        },
    }
}
pub fn draw(self: *Self) !void {
    // draw itself
    // const cr = surface.getCairoContext();
    // draw children
    const md = self.md;
    var rect = md.drawDecorationAdjustSize();
    const hexpand = self.expand.horizontal();
    const vexpand = self.expand.vertical();
    switch (self.direction) {
        .left, .right => {
            var min_width: f32 = 0;
            var total_weight: f32 = 0;
            for (self.children.items) |child| {
                if (child.getMetadata().rect.w == 0) {
                    total_weight += 1;
                } else {
                    min_width += child.getMetadata().rect.w;
                }
            }
            const remaining_space = rect.w - min_width;
            rect.w = 0;
            const scale = remaining_space / total_weight;
            // expand items
            for (self.children.items) |child| {
                const weight = 1;
                const child_width = child.getMetadata().rect.w;
                rect.x = rect.x + rect.w;
                rect.w = if (hexpand or child_width == 0) scale * weight else child_width;
                try child.draw(rect);
            }
        },
        .up, .down => {
            var min_width: f32 = 0;
            var total_weight: f32 = 0;
            for (self.children.items) |child| {
                if (child.getMetadata().rect.h == 0) {
                    total_weight += 1;
                } else {
                    min_width += child.getMetadata().rect.h;
                }
            }
            const remaining_space = rect.h - min_width;
            rect.h = 0;
            const scale = remaining_space / total_weight;
            for (self.children.items) |child| {
                const weight = 1;
                const child_height = child.getMetadata().rect.h;
                rect.y = rect.y + rect.h;
                rect.h = if (vexpand or child_height == 0) scale * weight else child_height;
                try child.draw(rect);
            }
        },
    }
}
pub fn end(self: *Self) void {
    self.md.surface.end(Widget.from(self));
}
pub const vtable = Widget.Vtable.forType(Self);
