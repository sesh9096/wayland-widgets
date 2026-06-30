const std = @import("std");
const log = std.log;
const Entry = struct {
    key: []const u8,
    value: []const u8,
    pub fn as(entry: Entry, T: type) std.fmt.ParseIntError!T {
        if (T == []const u8) return entry.value;
        return switch (@typeInfo(T)) {
            .Int => std.fmt.parseInt(T, entry.value, 0),
            .Float => std.fmt.parseFloat(T, entry.value),
            .Bool => if (std.mem.eql(u8, entry.value, "true"))
                true
            else if (std.mem.eql(u8, entry.value, "false"))
                false
            else if (std.mem.eql(u8, entry.value, "1"))
                true
            else if (std.mem.eql(u8, entry.value, "0"))
                false
            else
                error.InvalidCharacter,
            else => @compileError("Invalid type " ++ @typeName(T) ++ ", need integer or float"),
        };
    }
};

const Line = union(enum) {
    group: []const u8,
    entry: Entry,
    comment: []const u8,
    empty_line,
};

pub fn Parser(Reader: type, buffer_len: usize) type {
    return struct {
        reader: Reader,
        include_comments: bool = false,
        buf: [buffer_len]u8 = undefined,
        const Self = @This();
        pub fn next(self: *Self) !?Line {
            while (try self.reader.readUntilDelimiterOrEof(&self.buf, '\n')) |line| {
                if (line.len > 0) {
                    switch (line[0]) {
                        '[' => return .{ .group = line[1 .. line.len - 1] },
                        '#' => if (self.include_comments) return .{ .comment = line[1 .. line.len - 1] },
                        else => {
                            var iter = std.mem.splitScalar(u8, line, '=');
                            return .{ .entry = .{ .key = iter.next().?, .value = iter.next().? } };
                        },
                    }
                } else {
                    if (self.include_comments) return .empty_line;
                }
            }
            return null;
        }
    };
}
pub fn parse(reader: anytype, include_comments: bool) Parser(@TypeOf(reader), 4096) {
    return .{
        .reader = reader,
        .include_comments = include_comments,
    };
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const file = try std.fs.openFileAbsolute(args.next().?, .{});
    defer file.close();
    const reader = file.reader();
    var parser = parse(reader, false);
    while (try parser.next()) |line| {
        switch (line) {
            .group => |name| log.debug("[{s}]", .{name}),
            .entry => |entry| log.debug("{[key]s}={[value]s}", entry),
            else => unreachable,
        }
    }
}
