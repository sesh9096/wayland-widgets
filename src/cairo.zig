//! A wrapper around cairo
const std = @import("std");
const pi = std.math.pi;
const style = @import("./style.zig");
const Color = style.Color;

const c = @cImport({
    @cInclude("cairo/cairo.h");
});

pub const Context = opaque {
    extern fn cairo_create(surface: *Surface) *Context;
    pub const create = cairo_create;

    extern fn cairo_scale(self: *const Context, sx: f64, sy: f64) void;
    pub const scale = cairo_scale;

    // pub fn setSource(self: *Context, pattern: *Pattern) void {
    //     c.cairo_set_source(self, pattern);
    // }
    extern fn cairo_set_source_surface(self: *Context, surface: *const Surface, x: f32, y: f32) void;
    pub const setSourceSurface = cairo_set_source_surface;

    extern fn cairo_set_source_rgba(self: *Context, red: f64, green: f64, blue: f64, alpha: f64) void;
    pub const setSourceRgba = cairo_set_source_rgba;

    extern fn cairo_set_source_rgb(self: *Context, red: f64, green: f64, blue: f64) void;
    pub const setSourceRgb = cairo_set_source_rgb;

    extern fn cairo_set_line_width(self: *Context, width: f64) void;
    pub const setLineWidth = cairo_set_line_width;

    extern fn cairo_stroke(self: *Context) void;
    pub const stroke = cairo_stroke;

    extern fn cairo_close_path(self: *Context) void;
    pub const closePath = cairo_close_path;

    extern fn cairo_paint(self: *Context) void;
    pub const paint = cairo_paint;

    extern fn cairo_select_font_face(self: *Context, family: [*:0]const u8, slant: Slant, weight: Weight) void;
    pub const selectFontFace = cairo_select_font_face;

    extern fn cairo_set_font_size(self: *Context, size: f64) void;
    pub const setFontSize = cairo_set_font_size;

    extern fn cairo_show_text(self: *Context, text: [*:0]const u8) void;
    pub const showText = cairo_show_text;

    extern fn cairo_move_to(self: *Context, x: f64, y: f64) void;
    pub const moveTo = cairo_move_to;

    extern fn cairo_destroy(self: *Context) void;
    pub const destroy = cairo_destroy;

    extern fn cairo_arc(self: *Context, xc: f64, yc: f64, radius: f64, angle1: f64, angle2: f64) void;
    pub const arc = cairo_arc;

    pub fn roundRect(self: *Context, x: f64, y: f64, width: f64, height: f64, radius: f64) void {
        const halfPi = pi / 2.0;
        self.moveTo(x, y + radius);
        self.arc(x + radius, y + radius, radius, 2 * halfPi, 3 * halfPi);
        self.arc(x + width - radius, y + radius, radius, 3 * halfPi, 4 * halfPi);
        self.arc(x + width - radius, y + height - radius, radius, 0 * halfPi, 1 * halfPi);
        self.arc(x + radius, y + height - radius, radius, 1 * halfPi, 2 * halfPi);
        self.closePath();
        self.stroke();
    }
    pub fn setSourceColor(self: *Context, color_any: anytype) !void {
        // Note: this does NOT check all cases, just some more common ones
        const color = try Color.fromAny(color_any);
        const max_u8: f32 = @floatFromInt(std.math.maxInt(u8));
        self.setSourceRgba(
            @as(f32, @floatFromInt(color.r)) / max_u8,
            @as(f32, @floatFromInt(color.g)) / max_u8,
            @as(f32, @floatFromInt(color.b)) / max_u8,
            @as(f32, @floatFromInt(color.a)) / max_u8,
        );
    }
};

pub const Surface = opaque {
    extern fn cairo_image_surface_create_from_png(path: [*:0]const u8) *Surface;
    pub const createFromPng = cairo_image_surface_create_from_png;

    extern fn cairo_surface_write_to_png(self: *Surface, path: [*:0]const u8) Status;
    pub const writeToPng = cairo_surface_write_to_png;

    extern fn cairo_image_surface_create_for_data(data: [*]u8, format: Format, width: i32, height: i32, stride: i32) *Surface;
    pub const createForData = cairo_image_surface_create_for_data;

    extern fn cairo_surface_destroy(self: *Surface) void;
    pub const destroy = cairo_surface_destroy;

    extern fn cairo_surface_status(self: *Surface) Status;
    pub const status = cairo_surface_status;

    extern fn cairo_image_surface_get_width(self: *Surface) i32;
    pub const getWidth = cairo_image_surface_get_width;

    extern fn cairo_image_surface_get_height(self: *Surface) i32;
    pub const getHeight = cairo_image_surface_get_width;

    // pub fn createFromPngCheck(path: [*:0]const u8) Status!*Surface {
    //     const surface = createFromPng(path);
    //     const status = surface.status();
    //     if (status != .SUCCESS) return statusToError(status);
    //     return surface;
    // }
};
extern fn cairo_format_stride_for_width(format: Format, width: i32) i32;
pub const formatStrideForWidth = cairo_format_stride_for_width;

pub const Format = enum(c_int) {
    INVALID = c.CAIRO_FORMAT_INVALID,
    ARGB32 = c.CAIRO_FORMAT_ARGB32,
    RGB24 = c.CAIRO_FORMAT_RGB24,
    A8 = c.CAIRO_FORMAT_A8,
    A1 = c.CAIRO_FORMAT_A1,
    RGB16_565 = c.CAIRO_FORMAT_RGB16_565,
    RGB30 = c.CAIRO_FORMAT_RGB30,
    RGB96F = c.CAIRO_FORMAT_RGB96F,
    RGBA128F = c.CAIRO_FORMAT_RGBA128F,
};
pub const Slant = enum(c_uint) {
    Normal = c.CAIRO_FONT_SLANT_NORMAL,
    Italic = c.CAIRO_FONT_SLANT_ITALIC,
    Oblique = c.CAIRO_FONT_SLANT_OBLIQUE,
};

pub const Weight = enum(c_uint) {
    Normal = c.CAIRO_FONT_WEIGHT_NORMAL,
    Bold = c.CAIRO_FONT_WEIGHT_BOLD,
};

pub const Status = enum(c_int) {
    SUCCESS = c.CAIRO_STATUS_SUCCESS,
    NO_MEMORY = c.CAIRO_STATUS_NO_MEMORY,
    INVALID_RESTORE = c.CAIRO_STATUS_INVALID_RESTORE,
    INVALID_POP_GROUP = c.CAIRO_STATUS_INVALID_POP_GROUP,
    NO_CURRENT_POINT = c.CAIRO_STATUS_NO_CURRENT_POINT,
    INVALID_MATRIX = c.CAIRO_STATUS_INVALID_MATRIX,
    INVALID_STATUS = c.CAIRO_STATUS_INVALID_STATUS,
    NULL_POINTER = c.CAIRO_STATUS_NULL_POINTER,
    INVALID_STRING = c.CAIRO_STATUS_INVALID_STRING,
    INVALID_PATH_DATA = c.CAIRO_STATUS_INVALID_PATH_DATA,
    READ_ERROR = c.CAIRO_STATUS_READ_ERROR,
    WRITE_ERROR = c.CAIRO_STATUS_WRITE_ERROR,
    SURFACE_FINISHED = c.CAIRO_STATUS_SURFACE_FINISHED,
    SURFACE_TYPE_MISMATCH = c.CAIRO_STATUS_SURFACE_TYPE_MISMATCH,
    PATTERN_TYPE_MISMATCH = c.CAIRO_STATUS_PATTERN_TYPE_MISMATCH,
    INVALID_CONTENT = c.CAIRO_STATUS_INVALID_CONTENT,
    INVALID_FORMAT = c.CAIRO_STATUS_INVALID_FORMAT,
    INVALID_VISUAL = c.CAIRO_STATUS_INVALID_VISUAL,
    FILE_NOT_FOUND = c.CAIRO_STATUS_FILE_NOT_FOUND,
    INVALID_DASH = c.CAIRO_STATUS_INVALID_DASH,
    INVALID_DSC_COMMENT = c.CAIRO_STATUS_INVALID_DSC_COMMENT,
    INVALID_INDEX = c.CAIRO_STATUS_INVALID_INDEX,
    CLIP_NOT_REPRESENTABLE = c.CAIRO_STATUS_CLIP_NOT_REPRESENTABLE,
    TEMP_FILE_ERROR = c.CAIRO_STATUS_TEMP_FILE_ERROR,
    INVALID_STRIDE = c.CAIRO_STATUS_INVALID_STRIDE,
    FONT_TYPE_MISMATCH = c.CAIRO_STATUS_FONT_TYPE_MISMATCH,
    USER_FONT_IMMUTABLE = c.CAIRO_STATUS_USER_FONT_IMMUTABLE,
    USER_FONT_ERROR = c.CAIRO_STATUS_USER_FONT_ERROR,
    NEGATIVE_COUNT = c.CAIRO_STATUS_NEGATIVE_COUNT,
    INVALID_CLUSTERS = c.CAIRO_STATUS_INVALID_CLUSTERS,
    INVALID_SLANT = c.CAIRO_STATUS_INVALID_SLANT,
    INVALID_WEIGHT = c.CAIRO_STATUS_INVALID_WEIGHT,
    INVALID_SIZE = c.CAIRO_STATUS_INVALID_SIZE,
    USER_FONT_NOT_IMPLEMENTED = c.CAIRO_STATUS_USER_FONT_NOT_IMPLEMENTED,
    DEVICE_TYPE_MISMATCH = c.CAIRO_STATUS_DEVICE_TYPE_MISMATCH,
    DEVICE_ERROR = c.CAIRO_STATUS_DEVICE_ERROR,
    INVALID_MESH_CONSTRUCTION = c.CAIRO_STATUS_INVALID_MESH_CONSTRUCTION,
    DEVICE_FINISHED = c.CAIRO_STATUS_DEVICE_FINISHED,
    JBIG2_GLOBAL_MISSING = c.CAIRO_STATUS_JBIG2_GLOBAL_MISSING,
    PNG_ERROR = c.CAIRO_STATUS_PNG_ERROR,
    FREETYPE_ERROR = c.CAIRO_STATUS_FREETYPE_ERROR,
    WIN32_GDI_ERROR = c.CAIRO_STATUS_WIN32_GDI_ERROR,
    TAG_ERROR = c.CAIRO_STATUS_TAG_ERROR,
    DWRITE_ERROR = c.CAIRO_STATUS_DWRITE_ERROR,
    SVG_FONT_ERROR = c.CAIRO_STATUS_SVG_FONT_ERROR,
    LAST_STATUS = c.CAIRO_STATUS_LAST_STATUS,
};

pub const StatusError = error{
    NO_MEMORY,
    INVALID_RESTORE,
    INVALID_POP_GROUP,
    NO_CURRENT_POINT,
    INVALID_MATRIX,
    INVALID_STATUS,
    NULL_POINTER,
    INVALID_STRING,
    INVALID_PATH_DATA,
    READ_ERROR,
    WRITE_ERROR,
    SURFACE_FINISHED,
    SURFACE_TYPE_MISMATCH,
    PATTERN_TYPE_MISMATCH,
    INVALID_CONTENT,
    INVALID_FORMAT,
    INVALID_VISUAL,
    FILE_NOT_FOUND,
    INVALID_DASH,
    INVALID_DSC_COMMENT,
    INVALID_INDEX,
    CLIP_NOT_REPRESENTABLE,
    TEMP_FILE_ERROR,
    INVALID_STRIDE,
    FONT_TYPE_MISMATCH,
    USER_FONT_IMMUTABLE,
    USER_FONT_ERROR,
    NEGATIVE_COUNT,
    INVALID_CLUSTERS,
    INVALID_SLANT,
    INVALID_WEIGHT,
    INVALID_SIZE,
    USER_FONT_NOT_IMPLEMENTED,
    DEVICE_TYPE_MISMATCH,
    DEVICE_ERROR,
    INVALID_MESH_CONSTRUCTION,
    DEVICE_FINISHED,
    JBIG2_GLOBAL_MISSING,
    PNG_ERROR,
    FREETYPE_ERROR,
    WIN32_GDI_ERROR,
    TAG_ERROR,
    DWRITE_ERROR,
    SVG_FONT_ERROR,
    LAST_STATUS,
};
