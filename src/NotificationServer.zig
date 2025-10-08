const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const common = @import("common.zig");
const dbus = common.dbus;
const Surface = common.Surface;
const IdGenerator = common.IdGenerator;
pub const BasicWidgets = @import("BasicWidgets.zig");
const Self = @This();

connection: *dbus.Connection = undefined,
notifications: NotificationsInterface,
pub const path = "/org/freedesktop/Notifications";

const NotificationList = std.ArrayList(*Notification);
pub fn init(allocator: Allocator) Self {
    return .{
        .notifications = .{
            .notification_list = NotificationList.init(allocator),
        },
    };
}
/// Internal storage of things from dbus notify method
pub const Notification = struct {
    id: u32,
    summary: [:0]const u8,
    body: [:0]const u8 = "",
    app_name: [:0]const u8 = "",
    // in milliseconds
    expire_time: i64 = 0,
    urgency: Urgency = .normal,
    // app_icon: [:0]u8 = "",
    // actions: [][:0]u8 = &.{},
    pub const Urgency = enum(u8) { low = 0, normal = 1, critical = 2 };
    pub fn destroy(self: *Notification, allocator: Allocator) void {
        allocator.free(self.app_name);
        allocator.free(self.summary);
        allocator.free(self.body);
    }
    // pub fn widget(self: *const Notification, surface: *Surface, id_gen: IdGenerator) !void {
    //     const bw = BasicWidgets.init(surface);
    //     try bw.text(summary, id_gen);
    // }
};
pub const CloseReason = enum(u32) { expired = 1, dismissed = 2, closed = 3, undefined = 4 };
pub fn getOwnedString(allocator: Allocator, string: [*:0]const u8) Allocator.Error![:0]u8 {
    const owned_string = try allocator.allocSentinel(u8, std.mem.len(string), 0);
    @memcpy(owned_string, string);
    return owned_string;
}

pub const NotificationsInterface = struct {
    notification_list: NotificationList,
    onReceive: ?*const fn (*anyopaque, *Notification) void = null,
    on_receive_data: *anyopaque = undefined,
    onClose: ?*const fn (*anyopaque, *Notification, CloseReason) void = null,
    on_close_data: *anyopaque = undefined,

    pub var next_id: u32 = 1;
    pub fn closeExpiredNotifications(self: *NotificationsInterface) void {
        const time = std.time.milliTimestamp();
        outer: while (true) {
            for (self.notification_list.items, 0..) |notification, i| {
                if (notification.expire_time < time) {
                    self.closeNotification(i, .expired);
                    continue :outer;
                }
            }
            break :outer;
        }
    }
    pub fn closeNotification(self: *NotificationsInterface, index: usize, reason: CloseReason) void {
        const allocator = self.notification_list.allocator;
        const notification = self.notification_list.orderedRemove(index);
        if (self.onClose) |onClose| {
            onClose(self.on_close_data, notification, reason);
        }
        self.signalNotificationClosed(.{ .id = notification.id, .reason = reason }) catch unreachable;
        notification.destroy(allocator);
        allocator.destroy(notification);
    }
    pub fn setOnReceive(self: *NotificationsInterface, data: anytype, function: *const fn (@TypeOf(data), *Notification) void) void {
        self.onReceive = @ptrCast(function);
        self.on_receive_data = @ptrCast(data);
    }
    pub fn setOnClose(self: *NotificationsInterface, data: anytype, function: *const fn (@TypeOf(data), *Notification) void) void {
        self.onClose = @ptrCast(function);
        self.on_close_data = @ptrCast(data);
    }

    // dbus stuff
    pub const interface = "org.freedesktop.Notifications";
    pub fn methodGetCapabilites(self: *NotificationsInterface) struct { capabilities: []const [*:0]const u8 } {
        _ = self;
        return .{ .capabilities = &.{
            "body",
        } };
    }
    pub fn methodNotify(self: *NotificationsInterface, args: struct {
        app_name: [*:0]const u8 = "",
        replaces_id: u32 = 0,
        app_icon: [*:0]const u8 = "",
        summary: [*:0]const u8,
        body: [*:0]const u8 = "",
        actions: []const [*:0]const u8 = &.{},
        hints: []const dbus.VardictEntry = &.{},
        expire_timeout: i32 = -1,
    }) struct { id: u32 } {
        log.debug("Got notification {}", .{args});

        const id = if (args.replaces_id == 0) blk: {
            while (contains_id: for (self.notification_list.items) |notification| {
                if (notification.id == next_id) break :contains_id true;
            } else false) next_id += 1;
            const id = next_id;
            next_id += 1;
            break :blk id;
        } else args.replaces_id;
        const notification = self.notification_list.allocator.create(Notification) catch unreachable;
        notification.id = id;

        const summary_owned = self.notification_list.allocator.allocSentinel(u8, std.mem.len(args.summary), 0) catch unreachable;
        @memcpy(summary_owned, args.summary);
        const allocator = self.notification_list.allocator;
        notification.summary = getOwnedString(allocator, args.summary) catch unreachable;
        notification.body = getOwnedString(allocator, args.body) catch unreachable;
        notification.app_name = getOwnedString(allocator, args.app_name) catch unreachable;
        const time = std.time.milliTimestamp();

        const default_timeout = 10 * 1000;
        if (args.expire_timeout == 0) {
            notification.expire_time = std.math.maxInt(i64);
        } else { // TODO: scheduler support
            notification.expire_time =
                time + if (args.expire_timeout == -1) default_timeout else args.expire_timeout;
        }
        // TODO: hook up scheduler
        self.notification_list.append(notification) catch unreachable;
        if (self.onReceive) |onReceive| {
            onReceive(self.on_receive_data, notification);
        }
        return .{ .id = id };
    }
    pub fn methodCloseNotification(self: *NotificationsInterface, args: struct { id: u32 }) void {
        for (self.notification_list.items, 0..) |notification, i| {
            if (notification.id == args.id) {
                self.closeNotification(i, .closed);
                return;
            }
        }
    }
    pub fn methodGetServerInformation(self: *NotificationsInterface) struct {
        name: [*:0]const u8,
        vendor: [*:0]const u8,
        version: [*:0]const u8,
        spec_version: [*:0]const u8,
    } {
        _ = self;
        return .{
            .name = "ss",
            .vendor = "ss",
            .version = "0.0",
            .spec_version = "1.2",
        };
    }
    pub const signalNotificationClosed = dbus.generateSignalFunction(
        Self,
        NotificationsInterface,
        "NotificationClosed",
        struct { id: u32, reason: CloseReason },
    );
    pub const signalActionInvoked = dbus.generateSignalFunction(
        Self,
        NotificationsInterface,
        "ActionInvoked",
        struct { id: u32, action_key: [*:0]const u8 },
    );
    pub const signalActivationToken = dbus.generateSignalFunction(
        Self,
        NotificationsInterface,
        "ActivationToken",
        struct { id: u32, activation_token: [*:0]const u8 },
    );
};
