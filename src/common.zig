//! common type definitions
const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const SourceLocation = std.builtin.SourceLocation;
pub const cairo = @import("./cairo.zig");
pub const pango = @import("./pango.zig");
pub const style = @import("./style.zig");
pub const format = @import("./format.zig");
pub const Surface = @import("./Surface.zig");
pub const Widget = @import("./Widget.zig");
pub const Scheduler = @import("./Scheduler.zig");
pub const FileNotifier = @import("./FileNotifier.zig");
pub const c = @cImport({
    @cInclude("cairo/cairo.h");
    @cInclude("pango/pangocairo.h");
    @cInclude("time.h");
});
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

/// Config for generating Id's, use `.id` for direct control or `.src` and optionally `.extra`
pub const IdGenerator = struct {
    id: ?u32 = null,
    src: ?SourceLocation = null,
    extra: ?u32 = null,

    /// Generally set by a widget creator so avoid using in high level calls.
    type: ?type = null,
    /// Generally set by a widget creator so avoid using in high level calls.
    /// If other fields are set, we will avoid using this as part of seed.
    parent: ?*u32 = null,
    /// Generally set by a widget creator so avoid using in high level calls.
    /// If other fields are set, we will avoid using this as part of seed.
    ptr: ?*anyopaque = null,
    /// Generally set by a widget creator so avoid using in high level calls.
    /// If other fields are set, we will avoid using this as part of seed.
    str: ?[]const u8 = null,

    // note: we are not using std.hash.uint32 because of problems with 0
    const hash = std.hash.CityHash32.hash;
    pub fn hash_any(input: anytype) u32 {
        var ret: []const u8 = undefined;
        ret.ptr = @ptrCast(&input);
        ret.len = @sizeOf(@TypeOf(input));
        return hash(ret);
    }
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
            const component_type = if (self.type) |T| hash(@typeName(T)) else 0;
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

test "different types" {
    const id1 = IdGenerator.toId(.{ .type = IdGenerator });
    const id2 = IdGenerator.toId(.{ .type = i32 });
    if (id1 == id2) return error.DuplicateId;
}
