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
pub fn configure(self: *@This(), text: [:0]const u8) void {
    self.text = text;
}
pub fn draw(widget: *Widget, surface: *Surface) !void {
    const bounding_box = widget.rect;
    const cr = surface.currentBuffer().cairo_context;
    const font_description = surface.context.font.describe();
    const layout = pango.PangoCairo.createLayout(cr);
    defer layout.free();
    layout.setFontDescription(font_description);
    layout.setWidth(@intFromFloat(bounding_box.w * pango.SCALE));
    layout.setHeight(@intFromFloat(bounding_box.h * pango.SCALE));
    const text = widget.getInner(@This()).text;
    layout.setText(text, -1);
    cr.setSourceRgb(1, 1, 1);
    cr.moveTo(bounding_box.x, bounding_box.y);
    pango.PangoCairo.showLayout(cr, layout);
    // log.debug("Drawing text {} at {} {}", .{ text, bounding_box.x, bounding_box.y });
}
pub const vtable = Widget.Vtable{
    .draw = draw,
};
