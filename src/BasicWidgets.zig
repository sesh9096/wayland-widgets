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
const Expand = common.Expand;
const IdGenerator = common.IdGenerator;
const typeHash = common.typeHash;
const ImageCache = std.StringHashMap(*cairo.Surface);

pub const Text = @import("./BasicWidgets/Text.zig");
pub const Label = @import("./BasicWidgets/Label.zig");
pub const Button = @import("./BasicWidgets/Button.zig");
pub const Box = @import("./BasicWidgets/Box.zig");
pub const Overlay = @import("./BasicWidgets/Overlay.zig");
pub const Image = @import("./BasicWidgets/Image.zig");

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

pub fn end(self: *const Self, widget: *Widget) void {
    assert(widget == self.surface.widget);
    if (widget.parent) |parent| {
        self.surface.widget = parent;
    }
}

pub fn getBox(self: *const Self, orientation: common.Orientation, expand: Expand, id_gen: IdGenerator) !*Box {
    const widget = try self.surface.getWidget(id_gen.add(.{
        .type_hash = typeHash(Box),
        .parent = self.surface.widget,
    }), Box);
    widget.configure(orientation, expand);

    // const widget = try Box.widget(self.allocator, direction);
    return widget;
}
pub fn box(self: *const Self, orientation: common.Orientation, expand: Expand, id_gen: IdGenerator) !*Box {
    const widget = try self.getBox(orientation, expand, id_gen);
    Widget.from(widget).clearChildren();
    try self.surface.addWidgetSetCurrent(widget);
    return widget;
}
pub fn row(self: *const Self, id_gen: IdGenerator) !*Box {
    return self.box(.horizontal, .none, id_gen);
}
pub fn column(self: *const Self, id_gen: IdGenerator) !*Box {
    return self.box(.vertical, .none, id_gen);
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
pub fn label(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !void {
    const widget = try self.getLabel(txt, id_gen);
    try self.surface.addWidget(widget);
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

pub fn indexOfWidget(list: WidgetList, widget: Widget) ?usize {
    for (list.items, 0..) |item, i| {
        if (std.meta.eql(item, widget)) {
            return i;
        }
    }
    return null;
}
