const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const Orientation = common.Orientation;
const Rect = common.Rect;
const Vec2 = common.Vec2;
const Expand = common.Expand;
const BasicWidgets = @import("../BasicWidgets.zig");
const WidgetList = BasicWidgets.WidgetList;
const indexOfWidget = BasicWidgets.indexOfWidget;
const Self = @This();

md: Widget.Metadata,
orientation: Orientation = .horizontal,
expand: Expand,
children: WidgetList,
hash: u32,
pub fn init(self: *Self) void {
    self.children = WidgetList.init(self.md.surface.allocator);
}
pub fn configure(self: *Self, orientation: Orientation, expand: Expand) void {
    self.expand = expand;
    self.orientation = orientation;
}

pub fn childAction(self: *Self, action: Widget.Action, child: Widget) !void {
    // log.debug("adding child", .{});
    const children = &self.children;
    switch (action) {
        .add => {
            try children.append(child);
        },
        .clear => {
            // for (children.items) |chld| {
            //     chld.getMetadata().parent = null;
            // }
            children.items.len = 0;
        },
        .remove => {
            if (indexOfWidget(children.*, child)) |index| {
                _ = children.orderedRemove(index);
            } else {
                return error.InvalidChild;
            }
        },
        .updated => {
            if (indexOfWidget(children.*, child)) |index| {
                try Widget.updated(self);
                _ = index;
            } else {
                if (children.items.len < children.capacity and std.meta.eql(children.items.ptr[children.items.len], child)) {
                    try Widget.updated(self);
                } else return error.InvalidChild;
            }
        },
    }
}
pub fn getChildren(self: *Self) []Widget {
    return self.children.items;
}
pub fn proposeSize(self: *Self, rect: *Rect) void {
    // TODO: iterate
    switch (self.orientation) {
        .horizontal => {
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
        .vertical => {
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
    switch (self.orientation) {
        .horizontal => {
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
                rect.w = if (hexpand or child_width == 0) scale * weight else child_width;
                try child.draw(rect);
                rect.x = rect.x + rect.w;
            }
        },
        .vertical => {
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
                rect.h = if (vexpand or child_height == 0) scale * weight else child_height;
                try child.draw(rect);
                rect.y = rect.y + rect.h;
            }
        },
    }
}
pub fn end(self: *Self) void {
    self.md.surface.end(Widget.from(self));
    const hash = common.hash_any(self.children.items);
    if (self.hash != hash) {
        Widget.updated(self) catch unreachable;
        self.hash = hash;
    }
}
pub const vtable = Widget.Vtable.forType(Self);
