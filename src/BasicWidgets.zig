//! Factory for Widgets and wrapper around Surface
//! methods beginning with `get` should only create a Widget object and not attach it to the tree
const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const cairo = @import("./cairo.zig");
const pango = @import("./pango.zig");
const Widget = @import("./Widget.zig");
pub const WidgetList = std.ArrayList(Widget);
const Surface = @import("./Surface.zig");
const common = @import("./common.zig");
const Rect = common.Rect;
const Vec2 = common.Vec2;
const Direction = common.Direction;
const Expand = common.Expand;
const IdGenerator = common.IdGenerator;
const typeHash = common.typeHash;
const ImageCache = std.StringHashMap(*cairo.Surface);

pub const Text = @import("./BasicWidgets/Text.zig");
pub const Label = @import("./BasicWidgets/Label.zig");
pub const Button = @import("./BasicWidgets/Button.zig");
pub const Box = @import("./BasicWidgets/Box.zig");

surface: *Surface,
image_cache: ImageCache,

const Self = @This();
pub fn init(surface: *Surface) Self {
    return Self{
        .surface = surface,
        .image_cache = ImageCache.init(surface.allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.image_cache.deinit();
}

// /// Add widget as a child of the current widget.
// /// Use this if the widget will have no children and subsequent widgets should be added to the parent.
// pub fn addWidget(self: *const Self, widget: *Widget) !void {
//     const md = widget.getMetadata();
//     if (md.surface.widget) |parent| {
//         md.parent = parent;
//         try parent.vtable.childAction(parent, .add, widget);
//     } else {
//         widget.parent = null;
//     }
// }
// /// Add widget as a child of the current widget and then make it the current widget.
// /// Use this if you wish to add children to the widget.
// pub fn addWidgetSetCurrent(self: *const Self, widget: *Widget) !void {
//     try self.addWidget(widget);
//     self.setCurrent(widget);
// }

// pub inline fn setCurrent(self: *const Self, widget: *Widget) void {
//     self.surface.widget = widget;
// }

pub fn end(self: *const Self, widget: *Widget) void {
    assert(widget == self.surface.widget);
    if (widget.parent) |parent| {
        self.surface.widget = parent;
    }
}

pub fn getBox(self: *const Self, direction: Direction, expand: Expand, id_gen: IdGenerator) !*Box {
    const widget = try self.surface.getWidget(id_gen.add(.{
        .type_hash = typeHash(Box),
        .parent = self.surface.widget,
    }), Box);
    widget.configure(direction, expand);

    // const widget = try Box.widget(self.allocator, direction);
    return widget;
}
pub fn box(self: *const Self, direction: Direction, expand: Expand, id_gen: IdGenerator) !*Box {
    const widget = try self.getBox(direction, expand, id_gen);
    Widget.from(widget).clearChildren();
    try self.surface.addWidgetSetCurrent(widget);
    return widget;
}
pub fn row(self: *const Self, id_gen: IdGenerator) !*Box {
    return self.box(.right, .none, id_gen);
}
pub fn column(self: *const Self, id_gen: IdGenerator) !*Box {
    return self.box(.down, .none, id_gen);
}

pub fn getOverlay(self: *const Self, id_gen: IdGenerator) !*Overlay {
    const widget = try self.surface.getWidget(id_gen.add(.{
        .type_hash = typeHash(Overlay),
        .parent = self.surface.widget,
    }), Overlay);
    widget.configure();
    return widget;
}
pub fn overlay(self: *const Self, id_gen: IdGenerator) !*Overlay {
    const widget = try self.getOverlay(id_gen);
    try self.surface.addWidgetSetCurrent(widget);
    return widget;
}

pub fn getImage(self: *Self, path: [:0]const u8, option: Image.Option, id_gen: IdGenerator) !*Image {
    const get_or_put_res = try self.image_cache.getOrPut(path);
    const image_surface = if (get_or_put_res.found_existing) get_or_put_res.value_ptr.* else blk: {
        const img = cairo.Surface.createFromPng(path);
        if (img.status() != .SUCCESS) {
            log.err("{}", .{img.status()});
        }
        get_or_put_res.value_ptr.* = img;
        break :blk img;
    };

    const widget = try self.surface.getWidget(id_gen.add(.{
        .type_hash = typeHash(Image),
        .parent = self.surface.widget,
        .str = path,
    }), Image);
    widget.configure(image_surface, option);
    return widget;
}
pub fn image(self: *Self, path: [:0]const u8, option: Image.Option, id_gen: IdGenerator) !void {
    const widget = try self.getImage(path, option, id_gen);
    try self.surface.addWidget(widget);
}

pub fn getText(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !*Text {
    const widget = try self.surface.getWidget(id_gen, Text);
    try widget.configure(txt);
    return widget;
}
pub fn text(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !void {
    const widget = try self.getText(txt, id_gen);
    try self.surface.addWidget(widget);
}

pub fn getLabel(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !*Label {
    const widget = try self.surface.getWidget(id_gen, Label);
    try widget.configure(txt);
    return widget;
}

pub fn getButton(self: *const Self, id_gen: IdGenerator) !*Button {
    const widget = try self.surface.getWidget(id_gen, Button);
    widget.configure();
    return widget;
}

pub fn button(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !*Button {
    const widget = try self.getButton(id_gen);
    const label_widget = try self.getLabel(txt, id_gen.addExtra(0));
    try Widget.from(widget).addChild(Widget.from(label_widget));
    label_widget.md.parent = Widget.from(widget);
    try self.surface.addWidget(widget);
    return widget;
}

pub const Image = struct {
    md: Widget.Metadata,
    surface: *const cairo.Surface,
    option: Option = .stretch,
    size: Vec2,
    pub const Option = enum { stretch, fit, fill, center, tile };
    pub fn configure(self: *@This(), surface: *const cairo.Surface, option: Option) void {
        self.surface = surface;
        self.option = option;
        self.size = .{ .x = @floatFromInt(surface.getWidth()), .y = @floatFromInt(surface.getHeight()) };
    }
    pub fn draw(self: *Image) !void {
        const md = self.md;
        const surface = md.surface;
        const rect = md.rect;
        const cr = surface.currentBuffer().cairo_context;
        const image_surface = self.surface;
        const option = self.option;
        const size = self.size;
        cr.save();
        defer cr.restore();
        // log.debug("Drawing image at {} {}", .{ bounding_box.x, bounding_box.y });
        switch (option) {
            .stretch => {
                cr.scale(rect.w / size.x, rect.h / size.y);
                cr.setSourceSurface(image_surface, rect.x, rect.y);
            },
            .fit => {
                cr.setSourceSurface(image_surface, rect.x, rect.y);
            },
            .fill => {
                cr.setSourceSurface(image_surface, rect.x, rect.y);
            },
            .center => {
                cr.setSourceSurface(image_surface, rect.x, rect.y);
            },
            .tile => {
                cr.setSourceSurface(image_surface, rect.x, rect.y);
            },
        }
        cr.paint();
    }
    pub const vtable = Widget.Vtable.forType(Image);
};

pub fn indexOfWidget(list: WidgetList, widget: Widget) ?usize {
    for (list.items, 0..) |item, i| {
        if (std.meta.eql(item, widget)) {
            return i;
        }
    }
    return null;
}

/// draw multiple widgets on top of each other
pub const Overlay = struct {
    md: Widget.Metadata,
    children: WidgetList,
    pub fn init(self: *Overlay) void {
        self.children = WidgetList.init(self.md.surface.allocator);
    }
    pub fn configure(_: *Overlay) void {}
    fn draw(self: *Overlay) !void {
        const rect = self.md.drawDecorationAdjustSize();
        for (self.children.items) |child| {
            try child.draw(rect);
        }
        // try top.vtable.draw(top, surface, self.inner.overlay.top_rect);
    }
    pub fn childAction(self: *Overlay, action: Widget.Action, child: Widget) !void {
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
    pub fn getChildren(self: *Overlay) []Widget {
        return self.children.items;
    }
    pub fn proposeSize(self: *Overlay, rect: *Rect) void {
        // TODO: iterate
        for (self.children.items) |child| {
            child.vtable.proposeSize(child.ptr, &child.getMetadata().rect);
        }
        _ = rect;
    }
    pub fn end(self: *Overlay) void {
        self.md.surface.end(Widget.from(self));
    }
    pub const vtable = Widget.Vtable.forType(Overlay);
};
