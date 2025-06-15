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
// glyphs: *pango.GlyphString,
layout: ?*pango.Layout,
// pub fn init(self: *@This(), _: std.mem.Allocator) void {
//     // self.glyphs = pango.GlyphString.new();
// }
pub fn configure(self: *@This(), text: [:0]const u8) void {
    self.text = text;
}
pub fn draw(widget: *Widget, surface: *Surface) !void {
    const bounding_box = widget.rect;
    const cr = surface.currentBuffer().cairo_context;
    const label = widget.getInner(@This());
    defer label.layout = null;
    defer label.layout.?.free();

    cr.setSourceRgb(1, 1, 1);
    cr.moveTo(bounding_box.x, bounding_box.y);
    cr.setLineWidth(1);
    pango.PangoCairo.showLayout(cr, label.layout.?);

    // pango.PangoCairo.showGlyphString(cr, font, label.glyphs);
    // log.debug("{}", .{widget.rect});
    // log.debug("Drawing text {} at {} {}", .{ text, bounding_box.x, bounding_box.y });
}

pub fn proposeSize(widget: *Widget, surface: *Surface) void {
    const label = widget.getInner(@This());
    const cr = surface.currentBuffer().cairo_context;
    const font_description = surface.context.font.describe();
    const layout = pango.PangoCairo.createLayout(cr);
    layout.setFontDescription(font_description);
    const text = label.text;
    layout.setText(text, @intCast(text.len));
    label.layout = layout;
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
