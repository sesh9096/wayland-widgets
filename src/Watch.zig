const std = @import("std");
const log = std.log;
const testing = std.testing;
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const common = @import("./common.zig");
const Task = common.Scheduler.Task;
const Self = @This();

pollfds: Pollfds,
handlers: Handlers,

/// handle events
pub const Handler = struct {
    data: *anyopaque,
    handle_event: *const fn (data: *anyopaque, fd: i32, revents: i16) void,
    prewait: ?*const fn (data: *anyopaque, fd: i32) void = null,

    pub fn create(
        data: anytype,
        handle_event: *const fn (data: @TypeOf(data), fd: i32, revents: i16) void,
        prewait: ?*const fn (data: @TypeOf(data), fd: i32) void,
    ) Handler {
        return .{
            .data = @ptrCast(data),
            .handle_event = @ptrCast(handle_event),
            .prewait = @ptrCast(prewait),
        };
    }
};
pub const Item = struct {
    fd: i32,
    events: Events,
    pub fn toPollfd(item: Item) std.posix.pollfd {
        return .{
            .fd = item.fd,
            .events = item.events.toInt(),
            .revents = 0,
        };
    }
};
pub const Events = packed struct(i16) {
    in: bool = false,
    pri: bool = false,
    out: bool = false,
    err: bool = false,
    hup: bool = false,
    nval: bool = false,
    rdnorm: bool = false,
    rdband: bool = false,
    _padding: u8 = 0,
    pub fn toInt(events: Events) i16 {
        return @bitCast(events);
    }
};
const Pollfds = std.ArrayList(std.posix.pollfd);
const Handlers = std.ArrayList(Handler);

pub fn init(allocator: Allocator) Self {
    return .{
        .pollfds = Pollfds.init(allocator),
        .handlers = Handlers.init(allocator),
    };
}

pub fn wait(self: *Self, timeout: i32) std.posix.PollError!void {
    if (self.pollfds.items.len == 0) return;
    for (self.pollfds.items, self.handlers.items) |pollfd, handler| {
        if (handler.prewait) |prewait| prewait(handler.data, pollfd.fd);
    }
    var remaining_events = try std.posix.poll(self.pollfds.items, timeout);
    if (remaining_events == 0) return;
    for (self.pollfds.items, self.handlers.items) |*pollfd, handler| {
        if (pollfd.revents != 0) {
            handler.handle_event(handler.data, pollfd.fd, pollfd.revents);
            pollfd.revents = 0;
            remaining_events -= 1;
            if (remaining_events == 0) return;
        }
    }
    assert(remaining_events == 0);
}

/// append file descriptor to watch without checking if it is already in set, prefer add instead
pub fn append(self: *Self, item: Item, handler: Handler) Allocator.Error!void {
    try self.pollfds.append(item.toPollfd());
    try self.handlers.append(handler);
}

/// add file descriptor to watch
pub fn add(self: *Self, item: Item, handler: Handler) (Error || Allocator.Error)!void {
    if (self.hasFd(item.fd)) return error.FileDescriptorAlreadyPresentInSet;
    try self.append(item, handler);
    assert(self.pollfds.items.len == self.handlers.items.len);
}

/// add file descriptor to watch or modify events/handlers
pub fn addOrModify(self: *Self, item: Item, handler: Handler) (Error || Allocator.Error)!void {
    for (self.pollfds.items, self.handlers.items) |*pollfd, *existing_handler| {
        if (pollfd.fd == item.fd) {
            existing_handler.* = handler;
            pollfd.* = item.toPollfd();
        }
    }
    try self.append(item, handler);
    assert(self.pollfds.items.len == self.handlers.items.len);
}

/// append file descriptors to watch without checking if it is already in set
pub fn appendSlice(self: *Self, pollfds: []const std.posix.pollfd, handlers: []const Handler) Allocator.Error!void {
    try self.pollfds.appendSlice(pollfds);
    try self.handlers.appendSlice(handlers);
    assert(self.pollfds.items.len == self.handlers.items.len);
}
// pub fn toggleFd(self: *Self, fd: i32) void {}
pub fn toggleData(self: *Self, data: *anyopaque) void {
    for (self.handlers.items, 0..) |handler, i| {
        if (handler.data == data) {
            return self.toggleIndex(i);
        }
    }
}
// enable/disable watched item
pub inline fn toggleIndex(self: *Self, index: usize) void {
    self.pollfds[index].fd = ~self.pollfds[index].fd;
}
// pub fn removeFd(self: *Self, fd: i32) void {}
pub fn removeData(self: *Self, data: *anyopaque) void {
    for (self.handlers.items, 0..) |handler, i| {
        if (handler.data == data) {
            return self.removeIndex(i);
        }
    }
}
// remove watched item
pub inline fn removeIndex(self: *Self, index: usize) void {
    _ = self.pollfds.orderedRemove(index);
    _ = self.handlers.orderedRemove(index);
}

pub const Error = error{FileDescriptorAlreadyPresentInSet};

pub fn hasFd(self: *Self, fd: i32) bool {
    for (self.pollfds.items) |pollfd| {
        if (pollfd.fd == fd) return true;
    }
    return false;
}

test "events" {
    try testing.expectEqual(0, @as(u32, @bitCast(Item.Events{})));
    try testing.expectEqual(std.posix.POLL.IN, @as(u32, @bitCast(Item.Events{ .in = true })));
    try testing.expectEqual(std.posix.POLL.PRI, @as(u32, @bitCast(Item.Events{ .pri = true })));
    try testing.expectEqual(std.posix.POLL.OUT, @as(u32, @bitCast(Item.Events{ .out = true })));
    try testing.expectEqual(std.posix.POLL.ERR, @as(u32, @bitCast(Item.Events{ .err = true })));
    try testing.expectEqual(std.posix.POLL.HUP, @as(u32, @bitCast(Item.Events{ .hup = true })));
    try testing.expectEqual(std.posix.POLL.NVAL, @as(u32, @bitCast(Item.Events{ .nval = true })));
    try testing.expectEqual(std.posix.POLL.RDNORM, @as(u32, @bitCast(Item.Events{ .rdnorm = true })));
    try testing.expectEqual(std.posix.POLL.RDBAND, @as(u32, @bitCast(Item.Events{ .rdband = true })));
}
