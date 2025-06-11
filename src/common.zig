//! common type definitions
const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const SourceLocation = std.builtin.SourceLocation;
pub const cairo = @import("./cairo.zig");
pub const pango = @import("./pango.zig");
pub const Surface = @import("./Surface.zig");
pub const Widget = @import("./Widget.zig");
pub const Point = struct {
    x: f32 = 0,
    y: f32 = 0,
    pub fn in(self: *const Point, rect: Rect) bool {
        return (self.x >= rect.x and self.y >= rect.y) and (self.x <= (rect.x + rect.w) and self.y <= (rect.y + rect.h));
    }
};
pub const Rect = struct {
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

/// Config for generating Id's, use `.id` for direct control or `.src` and optionally `.extra`
pub const IdGenerator = struct {
    src: ?SourceLocation = null,
    extra: ?u32 = null,
    id: ?u32 = null,
    // note: we are not using std.hash.uint32 because of problems with 0
    pub fn hash_u32(input: u32) u32 {
        var ret: []const u8 = undefined;
        ret.ptr = @ptrCast(&input);
        ret.len = 4;
        return std.hash.CityHash32.hash(ret);
    }
    fn idFromSourceLocation(location: SourceLocation) u32 {
        return hash_u32(location.line) ^ hash_u32(location.column);
    }
    pub fn addExtra(self: @This(), input: u32) @This() {
        const input_hash = hash_u32(input);
        return @This(){
            .src = self.src,
            .extra = if (self.extra) |prev| hash_u32(prev) ^ input_hash else hash_u32(input_hash),
            .id = self.id,
        };
    }
    pub fn toId(self: @This()) u32 {
        if (self.id) |id| {
            return id;
        } else {
            const component_location = if (self.src) |loc| idFromSourceLocation(loc) else 0;
            const component_extra = if (self.extra) |extra| hash_u32(extra) else 0;
            const id = component_location ^ component_extra;
            // assert(id != 0);
            return id;
        }
    }
};

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

pub const Direction = enum {
    left,
    right,
    up,
    down,
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
