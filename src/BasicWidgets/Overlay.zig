const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const Rect = common.Rect;
const Vec2 = common.Vec2;
const Style = common.Style;
const BasicWidgets = @import("../BasicWidgets.zig");
const WidgetList = BasicWidgets.WidgetList;
const indexOfWidget = BasicWidgets.indexOfWidget;
const Self = @This();

md: Widget.Metadata,
children: WidgetList,
pub fn init(self: *Self) void {
    self.children = WidgetList.init(self.md.surface.allocator);
}
pub fn configure(_: *Self) void {}
pub fn draw(self: *Self) !void {
    const rect = self.md.drawDecorationAdjustSize();
    for (self.children.items) |child| {
        try child.draw(rect);
    }
    // try top.vtable.draw(top, surface, self.inner.overlay.top_rect);
}
pub fn childAction(self: *Self, action: Widget.Action, child: Widget) !void {
    // TODO: create an special child type to allow for placing items at specific locations
    switch (action) {
        .add => {
            try self.children.append(child);
        },
        .updated => if (indexOfWidget(self.children, child)) |index| {
            try Widget.updated(self);
            _ = index;
        } else {
            log.err("children: {}", .{self.children.items.len});
            return error.InvalidChild;
        },
        .remove => if (indexOfWidget(self.children, child)) |index| {
            _ = self.children.orderedRemove(index);
        } else {
            return error.InvalidChild;
        },
        .clear => self.children.clearRetainingCapacity(),
    }
}
pub fn getChildren(self: *Self) []Widget {
    return self.children.items;
}
pub fn proposeSize(self: *Self) void {
    // TODO: iterate
    var size = Vec2{};
    for (self.children.items) |child| {
        child.vtable.proposeSize(child.ptr);
        size = size.max(child.getMetadata().size);
    }
    self.md.size = size;
}
pub fn end(self: *Self) void {
    self.md.surface.end(Widget.from(self));
}
pub const vtable = Widget.Vtable.forType(Self);
