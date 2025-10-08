//! Wrapper around inotify system
const std = @import("std");
const mem = std.mem;
const log = std.log;
const posix = std.posix;

fd: i32,
handlers: Handlers,

pub const IN = std.os.linux.IN;
pub const Event = std.os.linux.inotify_event;
pub const Handler = struct {
    handler: *const fn (ptr: *anyopaque, event: *Event) void,
    ptr: *anyopaque,
    pub fn create(T: type, call: *const fn (T, event: *Event) void, data: T) Handler {
        switch (@typeInfo(T)) {
            .Pointer => |pointer| {
                if (pointer.size != .One) @compileError("Single item Pointer Required, got " ++ @typeName(T));
            },
            else => @compileError("Single item Pointer Required, got " ++ @typeName(T)),
        }
        return .{
            .handler = @ptrCast(call),
            .ptr = @ptrCast(data),
        };
    }
};
const Handlers = std.ArrayList(Handler);

const Self = @This();

pub fn init(allocator: mem.Allocator) posix.INotifyInitError!Self {
    return Self{
        .fd = try posix.inotify_init1(0),
        .handlers = Handlers.init(allocator),
    };
}

pub fn close(self: *Self) void {
    self.handlers.deinit();
    posix.close(self.fd);
}

/// Add a file to inotify watch list, mask values in `IN`.
pub fn addWatch(self: *Self, pathname: []const u8, mask: u32, handler: Handler) (std.mem.Allocator.Error || posix.INotifyAddWatchError)!void {
    const wd = try posix.inotify_add_watch(self.fd, pathname, mask);
    log.info("Watching {s} (wd: {})", .{ pathname, wd });
    try self.handlers.ensureTotalCapacity(@intCast(wd + 1));
    self.handlers.expandToCapacity();
    self.handlers.items[@intCast(wd)] = handler;
}

pub fn readEvents(self: Self) !void {
    // TODO: FIXME
    var buf: [@sizeOf(Event) + std.posix.NAME_MAX + 1]u8 = undefined;
    // while (true) {
    const len = try posix.read(self.fd, std.mem.asBytes(&buf));
    // if (len == 0)
    // }
    var start_index: u32 = 0;
    while (start_index < len) {
        const event: *Event = @alignCast(@ptrCast((&buf).ptr + start_index));
        const handler = self.handlers.items[@intCast(event.wd)];
        handler.handler(handler.ptr, event);
        start_index += event.len;
    }
}

pub fn getFd(self: Self) i32 {
    return self.fd;
}
