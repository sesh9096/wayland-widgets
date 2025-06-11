//! A wrapper around cairo
const std = @import("std");
const cairo = @import("./cairo.zig");
const common = @import("./common.zig");
pub const IRect = common.IRect;

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
    pub const getWidth = pango_layout_get_width;

    extern fn pango_layout_set_height(self: *Layout, length: i32) void;
    pub const setHeight = pango_layout_set_height;

    extern fn pango_layout_get_height(self: *Layout) i32;
    pub const getHeight = pango_layout_get_height;

    extern fn pango_layout_get_extents(self: *Layout, ink_rect: ?*IRect, logical_rect: ?*IRect) i32;
    pub const getExtents = pango_layout_get_extents;

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

pub const Font = opaque {
    extern fn pango_font_describe(self: *Font) *FontDescription;
    pub const describe = pango_font_describe;
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

    extern fn pango_cairo_show_glyph_string(cr: *cairo.Context, font: *Font, glyphs: *GlyphString) void;
    pub const showGlyphString = pango_cairo_show_glyph_string;

    extern fn pango_cairo_font_map_get_default() *FontMap;
    pub const fontMapGetDefault = pango_cairo_font_map_get_default;

    extern fn pango_cairo_create_context(cr: *cairo.Context) *Context;
    pub const createContext = pango_cairo_create_context;
};

pub const FontMap = opaque {
    extern fn pango_font_map_create_context(font_map: *FontMap) *Context;
    pub const createContext = pango_font_map_create_context;

    extern fn pango_font_map_load_font(fontmap: *FontMap, context: *Context, desc: *const FontDescription) *Font;
    pub const loadFont = pango_font_map_load_font;
};

pub const Context = opaque {
    extern fn pango_context_get_font_map(context: *Context) *FontMap;
    pub const getFontMap = pango_context_get_font_map;

    extern fn pango_context_set_round_glyph_positions(context: *Context, round_positions: bool) void;
    pub const setRoundGlyphPositions = pango_context_set_round_glyph_positions;
};

pub const GlyphString = opaque {
    extern fn pango_glyph_string_new() *GlyphString;
    pub const new = pango_glyph_string_new;

    extern fn pango_glyph_string_free(string: *GlyphString) void;
    pub const free = pango_glyph_string_free;

    extern fn pango_glyph_string_extents(glyphs: *GlyphString, font: *Font, ink_rect: ?*IRect, logical_rect: ?*IRect) void;
    pub const extents = pango_glyph_string_extents;
};

pub const AttrList = opaque {
    extern fn pango_attr_list_new() *AttrList;
    pub const new = pango_attr_list_new;

    extern fn pango_attr_list_unref(list: *AttrList) void;
    pub const unref = pango_attr_list_unref;
};
pub const AttrIterator = opaque {};

pub extern fn pango_itemize(
    context: *Context,
    text: [*:0]const u8,
    start_index: c_int,
    length: c_int,
    attrs: *AttrList,
    cached_iter: ?*AttrIterator,
) *GList;
pub fn itemize(context: *Context, text: [:0]const u8, attrs: *AttrList, cached_iter: ?*AttrIterator) *GList {
    return pango_itemize(context, text.ptr, 0, @intCast(text.len), attrs, cached_iter);
}

pub extern fn pango_shape(
    text: [*:0]const u8,
    len: i32,
    analysis: *Analysis,
    glyphs: *GlyphString,
) void;
pub fn shape(text: [:0]const u8, analysis: *Analysis, glyphs: *GlyphString) void {
    pango_shape(text.ptr, @intCast(text.len), analysis, glyphs);
}

pub extern fn pango_shape_full(
    item_text: *const u8,
    item_len: i32,
    paragraph_text: *const u8,
    paragraph_length: i32,
    analysis: *Analysis,
    glyphs: *GlyphString,
) void;

pub const GFunc = *const fn (*anyopaque, ?*anyopaque) void;
pub const GList = extern struct {
    data: ?*anyopaque,
    next: ?*GList,
    prev: ?*GList,
    extern fn g_list_free_full(list: *GList, free_func: *const fn (*anyopaque) void) void;
    pub const freeFull = g_list_free_full;

    extern fn g_list_foreach(list: *GList, func: GFunc) void;
    pub const foreach = g_list_free_full;
};
pub const Item = extern struct {
    offset: i32,
    length: i32,
    num_chars: i32,
    analysis: Analysis,
    extern fn pango_item_free(item: *Item) void;
    pub const free = pango_item_free;
};
pub const Analysis = extern struct {
    shape_engine: ?*EngineShape,
    lang_engine: ?*EngineLang,
    font: *Font,
    level: u8,
    gravity: u8,
    flags: u8,
    script: u8,
    language: ?*Language,
    extra_attrs: ?*GSList,
};

pub const EngineShape = opaque {};
pub const EngineLang = opaque {};
pub const Language = opaque {};
pub const GSList = opaque {};
