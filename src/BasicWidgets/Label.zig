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
const Self = @This();

md: Widget.Metadata,
text: [:0]const u8,
hash: u32,
// glyphs: *pango.GlyphString,
layout: *pango.Layout,
// pub fn init(self: *@This(), _: std.mem.Allocator) void {
//     // self.glyphs = pango.GlyphString.new();
// }
pub fn init(self: *Self) void {
    const cr = self.md.surface.getCairoContext();
    self.layout = pango.PangoCairo.createLayout(cr);
}
pub fn configure(self: *Self, text: [:0]const u8) !void {
    self.text = text;
    const layout = self.layout;
    const hash = common.hash(text);
    if (self.hash != hash) {
        self.hash = hash;
        const font_description = self.md.style.getAttribute(.default_font).describe();
        layout.setFontDescription(font_description);
        layout.setText(text, @intCast(text.len));
        try Widget.updated(self);
        // log.debug("updated text {s}", .{text});
    }
}
pub fn draw(self: *Self) !void {
    const surface = self.md.surface;
    const cr = surface.getCairoContext();
    const rect = self.md.drawDecorationAdjustSize();
    const style = self.md.style;
    // defer label.layout.free();

    cr.setSourceColor(style.getAttribute(.fg_color));
    cr.setLineWidth(style.getAttribute(.font_width));
    cr.moveTo(rect.x, rect.y);
    pango.PangoCairo.showLayout(cr, self.layout);

    // pango.PangoCairo.showGlyphString(cr, font, label.glyphs);
    // log.debug("{s} {}", .{ self.text, rect });
    // log.debug("Drawing text {s} at {} {}", .{ label.text, rect.x, rect.y });
}

pub fn proposeSize(self: *Self, rect: *Rect) void {
    const layout = self.layout;
    var irect: common.IRect = undefined;
    _ = layout.getPixelExtents(null, &irect);
    // irect.w += 10; // why????
    rect.* = irect.toRect();

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

pub const vtable = Widget.Vtable.forType(Self);
