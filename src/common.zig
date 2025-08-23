//! common type definitions
const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const SourceLocation = std.builtin.SourceLocation;
pub const cairo = @import("./cairo.zig");
pub const pango = @import("./pango.zig");
pub const Style = @import("./Style.zig");
pub const format = @import("./format.zig");
pub const Surface = @import("./Surface.zig");
pub const Widget = @import("./Widget.zig");
pub const Scheduler = @import("./Scheduler.zig");
pub const FileNotifier = @import("./FileNotifier.zig");
pub const c = @cImport({
    @cInclude("cairo/cairo.h");
    @cInclude("pango/pangocairo.h");
    @cInclude("time.h");
    @cInclude("linux/input-event-codes.h");
});
pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,
    pub fn in(self: *const Vec2, rect: Rect) bool {
        return (self.x >= rect.x and self.y >= rect.y) and (self.x <= (rect.x + rect.w) and self.y <= (rect.y + rect.h));
    }
    pub fn area(self: *const Vec2) f32 {
        return self.x * self.y;
    }
    pub fn format(value: Vec2, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("({d}, {d})", .{ value.x, value.y });
    }
    pub fn toRectSize(v: Vec2) Rect {
        return Rect{ .w = v.x, .h = v.y };
    }
};
pub const UVec2 = struct {
    x: u32 = 0,
    y: u32 = 0,
    pub fn in(self: *const UVec2, rect: Rect) bool {
        return (self.x >= rect.x and self.y >= rect.y) and (self.x <= (rect.x + rect.w) and self.y <= (rect.y + rect.h));
    }
    pub fn area(self: *const UVec2) u32 {
        return self.x * self.y;
    }
    pub fn format(value: UVec2, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("({}, {})", .{ value.x, value.y });
    }
    pub fn toRectSize(v: UVec2) Rect {
        return Rect{ .w = @floatFromInt(v.x), .h = @floatFromInt(v.y) };
    }
};
pub const Rect = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
    pub const inf = Rect{
        .x = -math.inf(f32),
        .y = -math.inf(f32),
        .w = math.inf(f32),
        .h = math.inf(f32),
    };
    pub fn area(self: *const Rect) f32 {
        return self.w * self.h;
    }
    pub fn isEmpty(self: *const Rect) bool {
        return self.w <= 0 or self.h <= 0;
    }
    pub fn overlap(a: Rect, b: Rect) Rect {
        // copied from dvui
        const ax2 = a.x + a.w;
        const ay2 = a.y + a.h;
        const bx2 = b.x + b.w;
        const by2 = b.y + b.h;
        const x = @max(a.x, b.x);
        const y = @max(a.y, b.y);
        const x2 = @min(ax2, bx2);
        const y2 = @min(ay2, by2);
        return Rect{ .x = x, .y = y, .w = @max(0, x2 - x), .h = @max(0, y2 - y) };
    }

    pub fn subtractSpacing(self: Rect, w: f32, h: f32) Rect {
        return Rect{
            .x = self.x + w,
            .y = self.y + h,
            .w = self.w - w * 2,
            .h = self.h - h * 2,
        };
    }
    pub fn div(self: Rect, divisor: f32) Rect {
        return .{
            .x = self.x / divisor,
            .y = self.y / divisor,
            .w = self.w / divisor,
            .h = self.h / divisor,
        };
    }

    pub fn larger(a: Rect, b: Rect) bool {
        return a.h > b.h and a.w > b.w;
    }
    // pub fn size(self: Rect) Vec2 {
    //     return Vec2{ .x = self.w, .y = self.h };
    // }
    pub fn point(self: Rect) Vec2 {
        return Vec2{ .x = self.x, .y = self.y };
    }
    pub fn getSize(self: Rect) Vec2 {
        return Vec2{ .x = self.w, .y = self.h };
    }
    pub fn contains(a: Rect, b: Rect) bool {
        return a.x <= b.x and a.y <= b.y and a.x + a.w >= b.x + b.w and a.y + a.h >= b.y + b.h;
    }
    pub fn setSize(self: *Rect, v: Vec2) void {
        self.w = v.x;
        self.h = v.y;
    }
};
// match with PangoRectangle
pub const IRect = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    w: i32 = 0,
    h: i32 = 0,
    pub fn toRect(self: IRect) Rect {
        return .{
            .x = @floatFromInt(self.x),
            .y = @floatFromInt(self.y),
            .w = @floatFromInt(self.w),
            .h = @floatFromInt(self.h),
        };
    }
};

pub const KeyState = enum {
    up,
    pressed,
    down,
    released,
    pub fn reset(self: *KeyState) void {
        self = .up;
    }
    pub fn transition(self: *KeyState, event: KeyState) void {
        self.* = switch (self.*) {
            .up, .released => if (event == .pressed) .pressed else .up,
            .pressed, .down => if (event == .released) .released else .down,
        };
    }
};

pub const Orientation = enum { horizontal, vertical };

pub const Alignment = enum {
    normal,
    opposite,
    center,
    sparse,
    stretch,
};

pub const Expand = enum {
    horizontal,
    vertical,
    both,
    none,
    pub fn horizontal(self: Expand) bool {
        return switch (self) {
            .horizontal, .both => true,
            else => false,
        };
    }
    pub fn vertical(self: Expand) bool {
        return switch (self) {
            .vertical, .both => true,
            else => false,
        };
    }
};

pub const hash = std.hash.CityHash32.hash;
pub fn hash_any(input: anytype) u32 {
    var ret: []const u8 = undefined;
    ret.ptr = @ptrCast(&input);
    ret.len = @sizeOf(@TypeOf(input));
    return hash(ret);
}
/// Config for generating Id's, use `.id` for direct control or `.src` and optionally `.extra`
pub const IdGenerator = struct {
    id: ?u32 = null,
    src: ?SourceLocation = null,
    extra: ?u32 = null,

    /// Generally set by a widget creator so avoid using in high level calls.
    type_hash: ?u32 = null,
    /// Generally set by a widget creator so avoid using in high level calls.
    /// If other fields are set, we will avoid using this as part of seed.
    parent: ?Widget = null,
    /// Generally set by a widget creator so avoid using in high level calls.
    /// If other fields are set, we will avoid using this as part of seed.
    ptr: ?*anyopaque = null,
    /// Generally set by a widget creator so avoid using in high level calls.
    /// If other fields are set, we will avoid using this as part of seed.
    str: ?[]const u8 = null,

    // note: we are not using std.hash.uint32 because of problems with 0
    fn idFromSourceLocation(location: SourceLocation) u32 {
        return hash_any(location.line) ^ hash_any(location.column);
    }
    pub fn toId(self: @This()) u32 {
        if (self.id) |id| {
            return id;
        } else {
            const component_location = if (self.src) |loc| idFromSourceLocation(loc) else 0;
            const component_extra = if (self.extra) |extra| hash_any(extra) else 0;
            var id: u32 = component_location ^ component_extra;
            // assert(id != 0);
            if (id == 0) {
                const component_parent = if (self.parent) |parent| hash_any(parent) else 0;
                const component_ptr = if (self.ptr) |ptr| hash_any(ptr) else 0;
                const component_str = if (self.str) |str| hash(str) else 0;
                id = component_parent ^ component_ptr ^ component_str;
            }
            const component_type = self.type_hash orelse 0;
            return id ^ component_type;
        }
    }

    pub fn addExtra(self: @This(), input: u32) @This() {
        const input_hash = hash_any(input);
        return @This(){
            .src = self.src,
            .extra = if (self.extra) |prev| hash_any(prev) ^ input_hash else hash_any(input_hash),
            .id = self.id,
        };
    }

    pub fn add(self: @This(), defaults: @This()) @This() {
        return .{
            .id = self.id orelse defaults.id,
            .extra = self.extra orelse defaults.extra,
            .src = self.src orelse defaults.src,
            .type_hash = self.type_hash orelse defaults.type_hash,
            .parent = self.parent orelse defaults.parent,
            .ptr = self.ptr orelse defaults.ptr,
            .str = self.str orelse defaults.str,
        };
    }
};
pub fn typeHash(T: type) u32 {
    return hash(@typeName(T));
}

test "different sources" {
    const id1 = IdGenerator.toId(.{ .src = @src() });
    const id2 = IdGenerator.toId(.{ .src = @src() });
    if (id1 == id2) return error.DuplicateId;
}

test "different extra" {
    const src = @src();
    const id1 = IdGenerator.toId(.{ .src = src });
    const id2 = IdGenerator.toId(.{ .src = src });
    if (id1 != id2) return error.DifferentId;
    const id3 = IdGenerator.toId(.{ .src = src, .extra = 0 });
    const id4 = IdGenerator.toId(.{ .src = src, .extra = 1 });
    if (id3 == id4) return error.DuplicateId;
}

test "identical id" {
    const id1 = IdGenerator.toId(.{ .id = 3 });
    const id2 = IdGenerator.toId(.{ .id = 3 });
    if (id1 != id2) return error.DifferentId;
}

test "different types" {
    const id1 = IdGenerator.toId(.{ .type_hash = typeHash(IdGenerator) });
    const id2 = IdGenerator.toId(.{ .type_hash = typeHash(i32) });
    if (id1 == id2) return error.DuplicateId;
}
