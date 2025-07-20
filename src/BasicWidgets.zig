//! Factory for Widgets and wrapper around Surface
//! methods beginning with `get` should only create a Widget object and not attach it to the tree
const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const cairo = @import("./cairo.zig");
const pango = @import("./pango.zig");
const Widget = @import("./Widget.zig");
pub const WidgetList = std.ArrayList(*Widget);
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

/// Add widget as a child of the current widget.
/// Use this if the widget will have no children and subsequent widgets should be added to the parent.
pub fn addWidget(self: *const Self, widget: *Widget) !void {
    if (self.surface.widget) |parent| {
        widget.parent = parent;
        try parent.vtable.childAction(parent, .add, widget);
    } else {
        widget.parent = null;
    }
}
/// Add widget as a child of the current widget and then make it the current widget.
/// Use this if you wish to add children to the widget.
pub fn addWidgetSetCurrent(self: *const Self, widget: *Widget) !void {
    try self.addWidget(widget);
    self.setCurrent(widget);
}

pub inline fn setCurrent(self: *const Self, widget: *Widget) void {
    self.surface.widget = widget;
}

pub fn getWidget(self: *const Self, id_gen: IdGenerator, T: type) !*Widget {
    return self.surface.getWidget(id_gen, T);
}

pub fn end(self: *const Self, widget: *Widget) void {
    assert(widget == self.surface.widget);
    if (widget.parent) |parent| {
        self.surface.widget = parent;
    }
}

pub fn getBox(self: *const Self, direction: Direction, expand: Expand, id_gen: IdGenerator) !*Widget {
    const widget = try self.getWidget(id_gen.add(.{
        .type_hash = typeHash(Box),
        .parent = self.surface.widget,
    }), Box);
    widget.getInner(Box).configure(direction, expand);

    // const widget = try Box.widget(self.allocator, direction);
    return widget;
}
pub fn box(self: *const Self, direction: Direction, expand: Expand, id_gen: IdGenerator) !*Widget {
    const widget = try self.getBox(direction, expand, id_gen);
    widget.clearChildren();
    try self.addWidgetSetCurrent(widget);
    return widget;
}
pub fn row(self: *const Self, id_gen: IdGenerator) !*Widget {
    return self.box(.right, .none, id_gen);
}
pub fn column(self: *const Self, id_gen: IdGenerator) !*Widget {
    return self.box(.down, .none, id_gen);
}

pub fn getOverlay(self: *const Self, id_gen: IdGenerator) !*Widget {
    const widget = try self.getWidget(id_gen.add(.{
        .type_hash = typeHash(Overlay),
        .parent = self.surface.widget,
    }), Overlay);
    widget.getInner(Overlay).configure();
    return widget;
}
pub fn overlay(self: *const Self, id_gen: IdGenerator) !*Widget {
    const widget = try self.getOverlay(id_gen);
    try self.addWidgetSetCurrent(widget);
    return widget;
}

pub fn getImage(self: *Self, path: [:0]const u8, option: Image.Option, id_gen: IdGenerator) !*Widget {
    const get_or_put_res = try self.image_cache.getOrPut(path);
    const image_surface = if (get_or_put_res.found_existing) get_or_put_res.value_ptr.* else blk: {
        const img = cairo.Surface.createFromPng(path);
        if (img.status() != .SUCCESS) {
            log.err("{}", .{img.status()});
        }
        get_or_put_res.value_ptr.* = img;
        break :blk img;
    };

    const widget = try self.getWidget(id_gen.add(.{
        .type_hash = typeHash(Image),
        .parent = self.surface.widget,
        .str = path,
    }), Image);
    widget.getInner(Image).configure(image_surface, option);
    return widget;
}
pub fn image(self: *Self, path: [:0]const u8, option: Image.Option, id_gen: IdGenerator) !void {
    const widget = try self.getImage(path, option, id_gen);
    try self.addWidget(widget);
}

pub fn getText(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !*Widget {
    const widget = try self.getWidget(id_gen, Text);
    try Text.configure(widget, txt);
    return widget;
}
pub fn text(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !void {
    const widget = try self.getText(txt, id_gen);
    try self.addWidget(widget);
}

pub fn getLabel(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !*Widget {
    const widget = try self.getWidget(id_gen, Label);
    try Label.configure(widget, txt);
    return widget;
}

pub fn getButton(self: *const Self, id_gen: IdGenerator) !*Widget {
    const widget = try self.getWidget(id_gen, Button);
    widget.getInner(Button).configure();
    return widget;
}

pub fn button(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !*Button {
    const widget = try self.getButton(id_gen);
    const label_widget = try self.getLabel(txt, id_gen.addExtra(0));
    try widget.addChild(label_widget);
    label_widget.parent = widget;
    try self.addWidget(widget);
    return widget.getInner(Button);
}

pub const Image = struct {
    surface: *const cairo.Surface,
    option: Option = .stretch,
    size: Vec2,
    pub const Option = enum { stretch, fit, fill, center, tile };
    pub fn configure(self: *@This(), surface: *const cairo.Surface, option: Option) void {
        self.surface = surface;
        self.option = option;
        self.size = .{ .x = @floatFromInt(surface.getWidth()), .y = @floatFromInt(surface.getHeight()) };
    }
    pub fn draw(widget: *Widget) !void {
        const surface = widget.surface;
        const rect = widget.rect;
        const cr = surface.currentBuffer().cairo_context;
        const self = widget.getInner(@This());
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
    pub const vtable = Widget.Vtable{
        .draw = draw,
    };
};

pub fn indexOfWidget(list: WidgetList, item: *Widget) ?usize {
    return std.mem.indexOfScalar(*Widget, list.items, item);
}

/// draw multiple widgets on top of each other
pub const Overlay = struct {
    children: WidgetList,
    pub fn init(widget: *Widget) void {
        const self = widget.getInner(@This());
        self.children = WidgetList.init(widget.surface.allocator);
    }
    pub fn configure(_: *Overlay) void {}
    fn draw(widget: *Widget) !void {
        const rect = widget.drawDecorationAdjustSize();
        for (widget.getInner(@This()).children.items) |child| {
            try child.draw(rect);
        }
        // try top.vtable.draw(top, surface, self.inner.overlay.top_rect);
    }
    pub fn childAction(widget: *Widget, action: Widget.Action, child: *Widget) !void {
        // TODO: create an special child type to allow for placing items at specific locations
        const self = widget.getInner(@This());
        switch (action) {
            .add => {
                try self.children.append(child);
            },
            .updated => if (indexOfWidget(self.children, child)) |index| {
                try widget.updated();
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
    pub fn getChildren(self: *Widget) []*Widget {
        return self.getInner(@This()).children.items;
    }
    pub fn proposeSize(widget: *Widget) void {
        // TODO: iterate
        for (widget.getInner(@This()).children.items) |child| {
            child.vtable.proposeSize(child);
        }
    }
    pub const vtable = Widget.Vtable{
        .draw = draw,
        .childAction = childAction,
        .getChildren = getChildren,
        .proposeSize = proposeSize,
    };
};
