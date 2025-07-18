const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const pango = common.pango;
const Rect = common.Rect;

text: [:0]const u8,
hash: u32,
layout: *pango.Layout,
pub fn init(widget: *Widget) void {
    const self = widget.getInner(@This());
    const cr = widget.surface.getCairoContext();
    self.layout = pango.PangoCairo.createLayout(cr);
}
pub fn configure(widget: *Widget, text: [:0]const u8) !void {
    const self = widget.getInner(@This());
    self.text = text;
    const layout = self.layout;
    const hash = common.hash(text);
    if (self.hash != hash) {
        const font_description = widget.style.getAttribute(.default_font).describe();
        layout.setFontDescription(font_description);
        layout.setText(text, @intCast(text.len));
        try widget.updated();
    }
}

pub fn draw(widget: *Widget) !void {
    const surface = widget.surface;
    const cr = surface.getCairoContext();
    const rect = widget.drawDecorationAdjustSize();
    const layout = widget.getInner(@This()).layout;
    const text = widget.getInner(@This()).text;
    // defer label.layout.free();

    const font_description = widget.style.getAttribute(.variable_font).describe();
    layout.setFontDescription(font_description);
    layout.setWidth(@intFromFloat(rect.w * pango.SCALE));
    layout.setHeight(@intFromFloat(rect.h * pango.SCALE));
    layout.setText(text, -1);
    cr.setSourceRgb(1, 1, 1);
    cr.moveTo(rect.x, rect.y);
    cr.setLineWidth(1);
    pango.PangoCairo.showLayout(cr, layout);
    // log.debug("Drawing text {} at {} {}", .{ text, rect.x, rect.y });
}

pub fn proposeSize(widget: *Widget) void {
    // const label = widget.getInner(@This());
    // const layout = label.layout;
    // var rect: common.IRect = undefined;
    // _ = layout.getPixelExtents(null, &rect);
    widget.rect.w = 0;
    widget.rect.h = 0;
    // widget.rect = rect.toRect();
}

pub const vtable = Widget.Vtable{
    .draw = draw,
    .proposeSize = proposeSize,
};
