const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub fn codegen(introspection: IntrospectionFormat, writer: anytype) !void {
    for (introspection.interfaces) |interface| {
        try writer.print("{}: {},\n", .{ interface.name, interface.name });
    }
}
