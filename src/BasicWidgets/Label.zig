//! a 1-line basically inert text object
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
// glyphs: *pango.GlyphString,
layout: *pango.Layout,
// pub fn init(self: *@This(), _: std.mem.Allocator) void {
//     // self.glyphs = pango.GlyphString.new();
// }
pub fn init(widget: *Widget) void {
    const self = widget.getInner(@This());
    const cr = widget.surface.getCairoContext();
    self.layout = pango.PangoCairo.createLayout(cr);
}
pub fn configure(widget: *Widget, text: [:0]const u8) !void {
    const surface = widget.surface;
    const self = widget.getInner(@This());
    self.text = text;
    const layout = self.layout;
    const hash = common.hash(text);
    if (self.hash != hash) {
        const style = if (widget.styles) |style| style else surface.styles;
        const fallback = if (widget.styles) |_| surface.styles else null;
        const font_description = style.getAttribute(.default_font, fallback).describe();
        layout.setFontDescription(font_description);
        layout.setText(text, @intCast(text.len));
        try widget.updated();
    }
}
pub fn draw(widget: *Widget) !void {
    const surface = widget.surface;
    const cr = surface.getCairoContext();
    const rect = widget.drawDecorationAdjustSize();
    const label = widget.getInner(@This());
    // defer label.layout.free();

    cr.setSourceRgb(1, 1, 1);
    cr.moveTo(rect.x, rect.y);
    cr.setLineWidth(1);
    pango.PangoCairo.showLayout(cr, label.layout);

    // pango.PangoCairo.showGlyphString(cr, font, label.glyphs);
    // log.debug("{}", .{widget.rect});
    // log.debug("Drawing text {s} at {} {}", .{ label.text, rect.x, rect.y });
}

pub fn proposeSize(widget: *Widget) void {
    const label = widget.getInner(@This());
    const layout = label.layout;
    var rect: common.IRect = undefined;
    _ = layout.getPixelExtents(null, &rect);
    rect.w += 10; // why????
    widget.rect = rect.toRect();

    // const attr_list = pango.AttrList.new();
    // defer attr_list.unref();
    // const context = surface.context;
    // const label = widget.getInner(@This());
    // const text = label.text;
    // const list = pango.itemize(context.pango_context, text, attr_list, null);
    // const item: *pango.Item = @alignCast(@ptrCast(list.data.?));
    // pango.shape(text, &item.analysis, label.glyphs);
    // var rect: common.IRect = undefined;
    // label.glyphs.extents(font, null, &rect);
}

pub const vtable = Widget.Vtable{
    .draw = draw,
    .proposeSize = proposeSize,
};
