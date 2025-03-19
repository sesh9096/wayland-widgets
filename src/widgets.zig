const std = @import("std");
const cairo = @import("./cairo.zig");
pub const Widget = union(enum) {
    image: *const Image,
    text: *const Text,
    box: *const Box,
};
pub const Image = struct {
    surface: *const cairo.Surface,
};
pub const Text = struct {
    text: [:0]const u8,
};
pub const Overlay = struct {
    // Surface on top of another surface
    bottom: *Widget,
    top: *Widget,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    movable: bool = false,
};
pub const Direction = enum {
    left,
    right,
    up,
    down,
};
pub const Box = struct {
    direction: Direction = .right,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    fn draw() void {}
};
// pub const Style = struct {};
