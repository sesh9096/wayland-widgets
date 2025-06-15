const std = @import("std");
const log = std.log;
const common = @import("./common.zig");
pub const Font = common.pango.Font;

/// argb Color
pub const Color = packed struct(u32) {
    a: u8 = std.math.maxInt(u8),
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    pub fn fromString(str: [:0]const u8) !Color {
        const hex = if (str[0] == '#') str[1..] else if (str[0] == '0' and str[1] == 'x') str[2..] else str;
        const color = try std.fmt.parseInt(u32, hex, 16);
        return @as(Color, @bitCast(color));
    }
    pub fn fromAny(color_any: anytype) !Color {
        return switch (@typeInfo(@TypeOf(color_any))) {
            .Int, .ComptimeInt => @bitCast(@as(u32, color_any)),
            .Struct => color_any,
            .Pointer => |Ptr| if (Ptr.child == Color) color_any.* else try Color.fromString(color_any),
            else => @compileError("Bad Type of color_any: " ++ @typeName(@TypeOf(color_any))),
        };
    }
};

pub const Style = union(enum) {
    bg_color: Color,
    fg_color: Color,
    font: *Font,
    margin: f32,
    padding: f32,
    border: f32,
    border_radius: f32,
};
pub const Styles = []const Style;

test "info" {
    std.debug.print("Style Size: {} bytes\n", .{@sizeOf(Style)});
}

pub const Theme = struct {};
