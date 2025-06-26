const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("./common.zig");
const Rect = common.Rect;
const cairo = common.cairo;
pub const Font = common.pango.Font;
pub const Surface = common.Surface;

pub var default_styles: Styles = Styles{
    .parent = null,
    .items = &.{.{ .theme = &default_theme }},
};
pub var default_theme = Theme{
    .default_font = undefined,
};

/// argb Color
pub const Color = packed struct(u32) {
    a: u8 = std.math.maxInt(u8),
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    pub const ParseIntError = std.fmt.ParseIntError;
    pub fn fromString(str: [:0]const u8) ParseIntError!Color {
        const hex = if (str[0] == '#') str[1..] else if (str[0] == '0' and str[1] == 'x') str[2..] else str;
        if (hex.len == 3) {
            return fromStringShort(hex);
        }
        const bits = try std.fmt.parseInt(u32, hex, 16);
        return @as(Color, @bitCast(bits));
    }
    fn fromStringShort(str: [:0]const u8) ParseIntError!Color {
        assert(str.len == 3);
        return .{
            .r = try hexToNum(str[0]) << 4,
            .g = try hexToNum(str[1]) << 4,
            .b = try hexToNum(str[2]) << 4,
        };
    }
    fn hexToNum(hex: u8) ParseIntError!u8 {
        return switch (hex) {
            '0'...'9' => hex - '0',
            'a'...'f' => hex - 'a' + 10,
            'A'...'F' => hex - 'A' + 10,
            else => ParseIntError.InvalidCharacter,
        };
    }
    pub fn fromAny(color_any: anytype) !Color {
        return switch (@typeInfo(@TypeOf(color_any))) {
            .Int, .ComptimeInt => @bitCast(@as(u32, color_any)),
            .Struct => color_any,
            .Pointer => |Ptr| if (Ptr.child == Color) color_any.* else try Color.fromString(color_any),
            else => @compileError("Bad Type of color_any: " ++ @typeName(@TypeOf(color_any))),
        };
    }
    pub fn fromAnyNoError(color_any: anytype) Color {
        return fromAny(color_any) catch unreachable;
    }
};
pub const color = Color.fromAnyNoError;

/// Override defaults for widget or widgets
pub const StyleItem = union(enum) {
    margin: f32,
    padding: f32,
    border_width: f32,
    border_radius: f32,

    bg_color: Color,
    fg_color: Color,
    border_color: Color,
    accent_color: Color,

    default_font: *const Font,
    variable_font: *const Font,

    theme: *const Theme,
    pub const Tag = std.meta.Tag(StyleItem);
};

/// Setting all styles at once, can be the base of a Style chain
pub const Theme = struct {
    margin: f32 = 0,
    padding: f32 = 0,
    border_width: f32 = 0,
    border_radius: f32 = 0,

    bg_color: Color = color("#10101010"),
    fg_color: Color = color("#ccc"),
    border_color: Color = color("#ccc"),
    accent_color: Color = color("#a50"),

    default_font: *const Font,
    variable_font: ?*const Font = null,

    pub fn getAttribute(self: Theme, comptime attribute: StyleItem.Tag) std.meta.TagPayload(StyleItem, attribute) {
        const tag: std.meta.Tag(StyleItem) = attribute;
        return switch (tag) {
            .variable_font => if (self.variable_font) |font| font else self.default_font,
            else => @field(self, @tagName(tag)),
        };
    }
};

/// a tree style list of style overrides
/// note: searching can become slow if there are too many layers
pub const Styles = struct {
    parent: ?*Styles,
    items: []const StyleItem,
    /// draw border and background and return the new size of the rect
    pub fn getAttribute(self: *const Styles, comptime attribute: StyleItem.Tag, fallback: ?*const Styles) std.meta.TagPayload(StyleItem, attribute) {
        if (self.getAttributeNullable(attribute)) |attr| {
            return attr;
        } else if (self != fallback and fallback != null) {
            if (fallback.?.getAttributeNullable(attribute)) |attr| {
                return attr;
            }
        }
        log.warn("Fallback is null or has no attribute " ++ @tagName(attribute) ++ ", looking in default theme", .{});
        return default_theme.getAttribute(attribute);
    }
    pub fn getAttributeNullable(self: *const Styles, comptime attribute: StyleItem.Tag) ?std.meta.TagPayload(StyleItem, attribute) {
        for (self.items) |style| {
            if (style == attribute) {
                return @field(style, @tagName(attribute));
            } else if (style == .theme) {
                return style.theme.getAttribute(attribute);
            }
        }
        return if (self.parent) |parent| parent.getAttributeNullable(attribute) else null;
    }
};

test "info" {
    std.debug.print("Style Size: {} bytes\n", .{@sizeOf(StyleItem)});
}
