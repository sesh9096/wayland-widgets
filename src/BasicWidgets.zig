//! Factory for Widgets and wrapper around Surface
//! methods beginning with `get` should only create a Widget object and not attach it to the tree
const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const main = @import("./main.zig");
const cairo = @import("./cairo.zig");
const widgets = @import("./widgets.zig");
const Surface = @import("./Surface.zig");
const Widget = widgets.Widget;
const common = @import("./common.zig");
const Rect = common.Rect;
const Point = common.Point;
const IdGenerator = common.IdGenerator;

surface: *Surface,

const Self = @This();
pub fn init(surface: *Surface) Self {
    return Self{ .surface = surface };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

/// Add widget as a child of the current widget.
/// Use this if the widget will have no children and subsequent widgets should be added to the parent.
pub fn addWidget(self: *const Self, widget: *Widget) !void {
    if (self.surface.widget) |parent| {
        widget.parent = parent;
        try parent.vtable.addChild(parent, widget);
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

pub fn getWidget(self: *const Self, id_gen: common.IdGenerator, T: type) !*Widget {
    return self.surface.getWidget(id_gen, T);
}

pub fn end(self: *const Self, widget: *Widget) void {
    assert(widget == self.surface.widget);
    if (widget.parent) |parent| {
        self.surface.widget = parent;
    }
}

pub fn getBox(self: *const Self, direction: widgets.Direction, id_gen: IdGenerator) !*Widget {
    const widget = try self.getWidget(id_gen, widgets.Box);
    widget.getInner(widgets.Box).configure(direction);

    // const widget = try widgets.Box.widget(self.allocator, direction);
    return widget;
}
pub fn box(self: *const Self, direction: widgets.Direction, id_gen: IdGenerator) !*Widget {
    const widget = try self.getBox(direction, id_gen);
    try self.addWidgetSetCurrent(widget);
    return widget;
}

pub fn getOverlay(self: *const Self, id_gen: IdGenerator) !*Widget {
    const widget = try self.getWidget(id_gen, widgets.Overlay);
    widget.getInner(widgets.Overlay).configure();
    return widget;
}
pub fn overlay(self: *const Self, id_gen: IdGenerator) !*Widget {
    const widget = try self.getOverlay(id_gen);
    try self.addWidgetSetCurrent(widget);
    return widget;
}

pub fn getImage(self: *const Self, path: [:0]const u8, id_gen: IdGenerator) !*Widget {
    const image_surface = cairo.Surface.createFromPng(path);
    if (image_surface.status() != .SUCCESS) {
        log.err("{}", .{image_surface.status()});
    }

    const widget = try self.getWidget(id_gen, widgets.Image);
    widget.getInner(widgets.Image).configure(image_surface);
    return widget;
}
pub fn image(self: *const Self, path: [:0]const u8, id_gen: IdGenerator) !void {
    const widget = try self.getImage(path, id_gen);
    try self.addWidget(widget);
}

pub fn getText(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !*Widget {
    const widget = try self.getWidget(id_gen, widgets.Text);
    widget.getInner(widgets.Text).configure(txt);
    return widget;
}
pub fn text(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !void {
    const widget = try self.getText(txt, id_gen);
    try self.addWidget(widget);
}

pub fn getButton(self: *const Self, id_gen: IdGenerator) !*Widget {
    const widget = try self.getWidget(id_gen, widgets.Button);
    widget.getInner(widgets.Button).configure();
    return widget;
}

pub fn button(self: *const Self, txt: [:0]const u8, id_gen: IdGenerator) !*widgets.Button {
    const widget = try self.getButton(id_gen);
    const text_widget = try self.getText(txt, id_gen.addExtra(0));
    try widget.vtable.addChild(widget, text_widget);
    text_widget.parent = widget;
    try self.addWidget(widget);
    return widget.getInner(widgets.Button);
}
