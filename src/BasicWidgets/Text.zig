const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("../common.zig");
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const pango = common.pango;
const Rect = common.Rect;
const Vec2 = common.Vec2;
const Self = @This();

md: Widget.Metadata,
text: [:0]const u8,
hash: u32,
layout: *pango.Layout,
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
    }
}

pub fn draw(self: *Self) !void {
    const surface = self.md.surface;
    const cr = surface.getCairoContext();
    const rect = self.md.drawDecorationAdjustSize();
    const style = self.md.style;
    const layout = self.layout;
    const text = self.text;
    // defer label.layout.free();

    const font_description = style.getAttribute(.variable_font).describe();
    layout.setFontDescription(font_description);
    layout.setWidth(@intFromFloat(rect.w * pango.SCALE));
    layout.setHeight(@intFromFloat(rect.h * pango.SCALE));
    layout.setText(text, -1);

    cr.setSourceColor(style.getAttribute(.fg_color));
    cr.setLineWidth(style.getAttribute(.font_width));
    cr.moveTo(rect.x, rect.y);
    pango.PangoCairo.showLayout(cr, layout);
    // log.debug("Drawing text {s} at {} {}, {}", .{ text, rect.x, rect.y, rect.size() });
}

pub fn proposeSize(self: *Self) void {
    var irect: common.IRect = undefined;
    const x = if (self.md.rect.w == 0) 300 else self.md.rect.w;
    self.layout.setWidth(@intFromFloat(x * pango.SCALE));
    _ = self.layout.getPixelExtents(null, &irect);
    self.md.setSize(.{ .x = x, .y = @floatFromInt(irect.h) });
}

pub const vtable = Widget.Vtable.forType(Self);
