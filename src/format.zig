const std = @import("std");
// pub fn Formatter(T: type) type {
//     return struct {};
// }
// const Chunk = union(enum){}
// var list: std.ArrayList(Chunk);

pub const State = enum { str, field };
pub fn format(s: anytype, fmt: []const u8, writer: anytype) !void {
    const T = @TypeOf(s);
    const type_info = @typeInfo(T);
    if (type_info != .Struct) @compileError("Expected struct, got " ++ @typeName(T));
    const fields = type_info.Struct.fields;

    var state = State.str;
    var start: u64 = 0;
    for (0.., fmt) |i, char| {
        switch (char) {
            '{' => {
                if (state != .str) return error.BadFormat;
                state = .field;
                try writer.writeAll(fmt[start..i]);
                start = i + 1;
            },
            '}' => {
                if (state != .field) return error.BadFormat;
                state = .str;
                const specifier = fmt[start..i];
                start = i + 1;
                inline for (fields) |field| {
                    if (std.mem.eql(u8, field.name, specifier)) {
                        // try writer.print("{}", .{@field(s, field.name)});
                        switch (@typeInfo(field.type)) {
                            .Pointer => |data| switch (data.size) {
                                .Slice => try writer.writeAll(@field(s, field.name)),
                                else => return error.BadFormat,
                            },
                            .Enum => {
                                try writer.writeAll(@tagName(@field(s, field.name)));
                            },
                            else => try writer.print("{}", .{@field(s, field.name)}),
                        }
                        break;
                    }
                } else {
                    // possibly check decls?
                    return error.BadFormat;
                }
            },
            else => {},
        }
    }
    if (state != .str) return error.BadFormat;
    try writer.writeAll(fmt[start..]);
}
pub fn formatToBuffer(s: anytype, fmt: []const u8, buffer: []u8) ![]u8 {
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();
    try format(s, fmt, writer);
    return buffer[0..stream.pos];
}

test "basic" {
    const a = struct {};
    var buf: [1024]u8 = undefined;
    const compfmt = "abcd";
    var fmt: [4]u8 = undefined;
    @memcpy(&fmt, compfmt);
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();
    try format(a{}, &fmt, writer);
    try std.testing.expectEqualStrings(&fmt, buf[0..stream.pos]);
}

test "int and bool" {
    const s = struct {
        a: i32,
        b: bool,
        c: u64,
    };
    var buf: [1024]u8 = undefined;
    const compfmt = "{a} {b} {c}d";
    var fmt: [12]u8 = undefined;
    @memcpy(&fmt, compfmt);
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();
    try format(s{ .a = 3, .b = true, .c = 9 }, &fmt, writer);
    try std.testing.expectEqualStrings("3 true 9d", buf[0..stream.pos]);
}
