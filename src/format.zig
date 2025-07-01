const std = @import("std");
const log = std.log;
// pub fn Formatter(T: type) type {
//     return struct {};
// }
// const Chunk = union(enum){}
// var list: std.ArrayList(Chunk);

pub const State = enum { str, field };
pub fn format(s: anytype, fmt: []const u8, writer: anytype) !void {
    const type_info_s = @typeInfo(@TypeOf(s));
    const T = if (type_info_s == .Struct) @TypeOf(s) else if (type_info_s == .Pointer) blk: {
        const U = type_info_s.Pointer.child;
        if (@typeInfo(U) == .Struct) {
            break :blk U;
        } else {
            @compileError("Expected struct or pointer to struct, got " ++ @typeName(@TypeOf(s)));
        }
    } else {
        @compileError("Expected struct or pointer to struct, got " ++ @typeName(@TypeOf(s)));
    };
    const type_info = @typeInfo(T);
    const fields = type_info.Struct.fields;
    const decls = type_info.Struct.decls;

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
                    inline for (decls) |decl| {
                        if (std.mem.eql(u8, decl.name, specifier)) {
                            // try writer.print("{}", .{@field(s, field.name)});
                            const field = @field(T, decl.name);
                            switch (@typeInfo(@TypeOf(field))) {
                                .Fn => |data| {
                                    const params = data.params;
                                    if (params.len == 2 and params[0].type == T and params[1].is_generic) {
                                        try field(s, writer);
                                    }
                                },
                                else => return error.BadFormat,
                            }
                            break;
                        }
                    } else {
                        return error.BadFormat;
                    }
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
pub fn formatToArrayList(s: anytype, fmt: []const u8, array_list: *std.ArrayList(u8)) ![]u8 {
    const writer = array_list.writer();
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
