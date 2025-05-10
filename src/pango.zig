//! A wrapper around cairo
const std = @import("std");
const cairo = @import("./cairo.zig");

const c = @cImport({
    @cInclude("pango/pangocairo.h");
});
pub const Layout = opaque {
    extern fn pango_layout_set_font_description(self: *Layout, description: *FontDescription) void;
    pub const setFontDescription = pango_layout_set_font_description;

    extern fn pango_layout_set_text(self: *Layout, text: [*:0]const u8, length: i32) void;
    pub const setText = pango_layout_set_text;
    pub fn setTextSlice(self: *Layout, text: [:0]const u8) void {
        self.setText(text.ptr, text.len);
    }

    extern fn pango_layout_set_width(self: *Layout, length: i32) void;
    pub const setWidth = pango_layout_set_width;

    extern fn pango_layout_get_width(self: *Layout) i32;
    pub const getWidth = pango_layout_set_width;

    extern fn pango_layout_set_height(self: *Layout, length: i32) void;
    pub const setHeight = pango_layout_set_height;

    extern fn pango_layout_get_height(self: *Layout) i32;
    pub const getHeight = pango_layout_set_height;

    extern fn g_object_unref(self: *Layout) void;
    pub const free = g_object_unref;
};

pub const FontDescription = opaque {
    extern fn pango_font_description_new() *FontDescription;
    pub const new = pango_font_description_new;

    extern fn pango_font_description_from_string(str: [*:0]const u8) *FontDescription;
    pub const fromString = pango_font_description_from_string;

    extern fn pango_font_description_set_family(self: *FontDescription, family: [*:0]const u8) void;
    pub const setFamily = pango_font_description_set_family;

    extern fn pango_font_description_set_absolute_size(self: *FontDescription, size: f64) void;
    pub const setAbsoluteSize = pango_font_description_set_absolute_size;

    extern fn pango_font_description_free(self: *FontDescription) void;
    pub const free = pango_font_description_free;

    extern fn pango_font_description_set_weight(self: *FontDescription, weight: Weight) void;
    pub const setWeight = pango_font_description_set_weight;
};
pub const SCALE = c.PANGO_SCALE;
pub const Weight = enum(c_int) {
    LIGHT = c.PANGO_WEIGHT_LIGHT,
    NORMAL = c.PANGO_WEIGHT_NORMAL,
    BOLD = c.PANGO_WEIGHT_BOLD,
};

pub const PangoCairo = struct {
    extern fn pango_cairo_create_layout(cr: *cairo.Context) *Layout;
    pub const createLayout = pango_cairo_create_layout;

    extern fn pango_cairo_show_layout(cr: *cairo.Context, layout: *Layout) void;
    pub const showLayout = pango_cairo_show_layout;
};
// PangoLayout *layout;
// PangoFontDescription *font_description;

// font_description = pango_font_description_new ();
// pango_font_description_set_family (font_description, "serif");
// pango_font_description_set_weight (font_description, PANGO_WEIGHT_BOLD);
// pango_font_description_set_absolute_size (font_description, 32 * PANGO_SCALE);

// layout = pango_cairo_create_layout (cr);
// pango_layout_set_font_description (layout, font_description);
// pango_layout_set_text (layout, "Hello, world", -1);

// cairo_set_source_rgb (cr, 0.0, 0.0, 1.0);
// cairo_move_to (cr, 10.0, 50.0);
// pango_cairo_show_layout (cr, layout);

// g_object_unref (layout);
// pango_font_description_free (font_description);
