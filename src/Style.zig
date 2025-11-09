//! a tree style list of style overrides
//! note: searching can become slow if there are too many layers

const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const common = @import("./common.zig");
const Rect = common.Rect;
const cairo = common.cairo;
pub const Font = common.pango.Font;
pub const Surface = common.Surface;
pub const Self = @This();

parent: ?*Self = null,
items: []const Item = &.{},

/// get attribute from style, fallback to default theme
pub fn getAttribute(self: *const Self, comptime attribute: Item.Tag) std.meta.TagPayload(Item, attribute) {
    if (self.getAttributeNullable(attribute)) |attr| {
        return attr;
    }
    return default_theme.getAttribute(attribute);
}
pub fn getAttributeNullable(self: *const Self, comptime attribute: Item.Tag) ?std.meta.TagPayload(Item, attribute) {
    for (self.items) |style| {
        if (style == attribute) {
            return @field(style, @tagName(attribute));
        } else if (style == .theme) {
            return style.theme.getAttribute(attribute);
        }
    }
    return if (self.parent) |parent| parent.getAttributeNullable(attribute) else null;
}

pub var default_style: Self = Self{
    .parent = null,
    .items = &.{.{ .theme = &default_theme }},
};
pub var default_theme = Theme{
    .default_font = undefined,
};

/// argb Color
pub const Color = packed struct(u32) {
    b: u8 = 0,
    g: u8 = 0,
    r: u8 = 0,
    a: u8 = std.math.maxInt(u8),
    pub const ParseIntError = std.fmt.ParseIntError;
    pub fn fromString(str: [:0]const u8) ParseIntError!Color {
        const hex = if (str[0] == '#') str[1..] else if (str[0] == '0' and str[1] == 'x') str[2..] else str;
        return switch (hex.len) {
            3 => fromStringShort(hex),
            6, 8 => |len| {
                const rgb = if (len == 6) hex else hex[2..];
                return .{
                    .r = try hex2ToNum(rgb[0..2]),
                    .g = try hex2ToNum(rgb[2..4]),
                    .b = try hex2ToNum(rgb[4..6]),
                    .a = if (len == 6) std.math.maxInt(u8) else try hex2ToNum(hex[0..2]),
                };
            },
            else => return error.Overflow,
        };
    }
    fn fromStringShort(str: [:0]const u8) ParseIntError!Color {
        if (str.len != 3) return error.Overflow;
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
    fn hex2ToNum(hex: *const [2]u8) ParseIntError!u8 {
        return (try hexToNum(hex[0]) << 4) | (try hexToNum(hex[1]));
    }
    pub fn fromAny(color_any: anytype) !Color {
        return switch (@typeInfo(@TypeOf(color_any))) {
            .Int, .ComptimeInt => @bitCast(@as(u32, color_any)),
            .Struct => color_any,
            .Pointer => |Ptr| if (Ptr.child == Color) color_any.* else try Color.fromString(color_any),
            else => @compileError("Bad Type of color_any: " ++ @typeName(@TypeOf(color_any))),
        };
    }
    pub inline fn fromAnyComptime(comptime color_any: anytype) Color {
        comptime {
            return fromAny(color_any) catch |err| @compileError("Failed to parse " ++ color_any ++ " due to " ++ err);
        }
    }
    pub fn format(self: Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.a == std.math.maxInt(u8)) {
            try writer.print("#{x}{x}{x}", .{ self.r, self.g, self.b });
        } else {
            try writer.print("#{[a]x}{[r]x}{[g]x}{[b]x}", self);
        }
    }
};
pub const color = Color.fromAnyComptime;
test "color parsing" {
    try std.testing.expectEqual(try Color.fromAny("#123"), Color{ .r = 0x10, .g = 0x20, .b = 0x30 });
    try std.testing.expectEqual(try Color.fromAny("#123456"), Color{ .r = 0x12, .g = 0x34, .b = 0x56 });
    try std.testing.expectEqual(try Color.fromAny("#ab102030"), Color{ .a = 0xab, .r = 0x10, .g = 0x20, .b = 0x30 });
    try std.testing.expectEqual(try Color.fromAny("0xab102030"), Color{ .a = 0xab, .r = 0x10, .g = 0x20, .b = 0x30 });
    try std.testing.expectEqual(try Color.fromAny("ab102030"), Color{ .a = 0xab, .r = 0x10, .g = 0x20, .b = 0x30 });
}

/// Override defaults for widget or widgets
pub const Item = union(enum) {
    margin: f32,
    padding: f32,
    border_width: f32,
    border_radius: f32,

    bg_color: Color,
    fg_color: Color,
    border_color: Color,
    accent_color: Color,
    clear_color: Color,

    default_font: *const Font,
    variable_font: *const Font,
    font_width: f32,

    theme: *const Theme,
    pub const Tag = std.meta.Tag(Item);
};

/// Setting all styles at once, can be the base of a Style chain
pub const Theme = struct {
    margin: f32 = 0,
    padding: f32 = 0,
    border_width: f32 = 0,
    border_radius: f32 = 0,

    bg_color: Color = color("#10101010"),
    clear_color: Color = color("#10101010"),
    fg_color: Color = color("#ccc"),
    border_color: Color = color("#ccc"),
    accent_color: Color = color("#a50"),

    default_font: *const Font,
    variable_font: ?*const Font = null,

    font_width: f32 = 1,

    pub fn getAttribute(self: Theme, comptime attribute: Item.Tag) std.meta.TagPayload(Item, attribute) {
        const tag: std.meta.Tag(Item) = attribute;
        return switch (tag) {
            .variable_font => if (self.variable_font) |font| font else self.default_font,
            else => @field(self, @tagName(tag)),
        };
    }
};

// test "info" {
//     std.debug.print("Style Size: {} bytes\n", .{@sizeOf(Item)});
// }
