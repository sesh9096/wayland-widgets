const std = @import("std");
const dbus_clients = @import("dbus-clients");
const Notifications = dbus_clients.Notifications;
const DBusMenu = dbus_clients.DBusMenu;
const StatusNotifierWatcher = dbus_clients.StatusNotifierWatcher;
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const common = @import("./common.zig");
const Style = common.Style;
const LayerSurface = @import("./LayerSurface.zig");
const Scheduler = @import("./Scheduler.zig");
const Task = Scheduler.Task;
const Surface = @import("./Surface.zig");
pub const Context = @import("./Context.zig");
pub const NotificationHandler = @import("./NotificationServer.zig");
pub const BasicWidgets = @import("./BasicWidgets.zig");
pub const StatusWidgets = @import("./StatusWidgets.zig");
pub const Seat = Context.Seat;
// pub const Windows = std.ArrayList(Window);
const c = common.c;
const dbus = common.dbus;
const FileNotifier = common.FileNotifier;

const Options = struct {
    filename: ?[:0]const u8 = null,
    fn parseArgs() Options {
        var o: Options = .{};
        var args = std.process.args();
        _ = args.next();
        while (args.next()) |arg| {
            o.filename = arg;
        }
        return o;
    }
};

pub fn main() !void {
    var GPA = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = GPA.allocator();
    // var buf: [4096]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&buf);
    // const allocator = fba.allocator();
    var context: Context = undefined;
    try context.configure(allocator);
    // try context.getGlobals();
    defer context.destroy();
    const dbus_connection = dbus.busGet(.session, null).?;
    var err: dbus.Error = .{};

    var notifications = Notifications{};
    notifications.register(dbus_connection, "org.freedesktop.Notifications", "/org/freedesktop/Notifications");
    defer notifications.unRegister();
    // notifications
    // notifications.Notifications.registerSignalHandler();
    var notification_id: u32 = 0;
    const pending = try notifications.notifications.Notify(.{
        .summary = "started serve",
        .app_name = "app",
        .replaces_id = 0,
        .app_icon = "",
        .body = "",
        .actions = &.{},
        .hints = &.{},
        .expire_timeout = -1,
    });
    try pending.setNotify(&notification_id, handleNotifyReturn, null);

    var _status_notifier_watcher = StatusNotifierWatcher{};
    _status_notifier_watcher.register(dbus_connection, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher");
    defer _status_notifier_watcher.unRegister();
    const status_notifier_watcher = &_status_notifier_watcher.statusNotifierWatcher;
    status_notifier_watcher.setSignalHandler(@as(*anyopaque, undefined), handleStatusNotifierWatcherSignal);
    const pending_registered_items = try status_notifier_watcher.getRegisteredStatusNotifierItems();
    try pending_registered_items.setNotify(@as(*anyopaque, undefined), handleGetStatusNotifierWatcherItems, null);

    const pending_version = try status_notifier_watcher.getProtocolVersion();
    try pending_version.setNotify(@as(*anyopaque, undefined), handleGetProtocolVersion, null);

    // var menu = DBusMenu{};
    // menu.register(dbus_connection, "bus_name", "object_path");
    // defer menu.unRegister();
    const ret = dbus_connection.requestName("org.testing.tester", 0, &err);
    _ = ret;
    var notification_handler = NotificationHandler.init(allocator);
    try notification_handler.notifications.registerTasks(&context.scheduler);
    try dbus_connection.registerObject(&notification_handler);
    // _ = dbus_connection.registerObjectPath("/", &.{ .message_function = dbus.printFilter }, undefined);
    // log.debug("{s}", .{dbus.introspection.fromType(NotificationHandler)});

    const options = Options.parseArgs();
    _ = options;
    // var windows = Windows.init(allocator);
    // _ = image;
    // try windows.append(.{
    // Background
    var bg_layer: LayerSurface = undefined;
    try bg_layer.init(
        &context,
        .background,
        null,
        "background",
        .{},
        .{ .top = true, .bottom = true, .left = true, .right = true },
        .ignore,
    );
    const surface = bg_layer.getSurface();
    var bar_layer: LayerSurface = undefined;
    try bar_layer.init(
        &context,
        .bottom,
        null,
        "bar",
        .{ .y = 16 },
        .{ .top = true, .left = true, .right = true },
        .exclude,
    );
    const bar = bar_layer.getSurface();

    var notification_layer: LayerSurface = undefined;
    try notification_layer.init(
        &context,
        .top,
        null,
        "notifications",
        .{ .x = 100, .y = 100 },
        .{ .top = true, .right = true },
        .ignore,
    );
    const notification_surface = notification_layer.getSurface();
    notification_handler.notifications.setOnReceive(notification_surface, @ptrFromInt(@intFromPtr(&markDirty)));
    notification_handler.notifications.setOnClose(notification_surface, @ptrFromInt(@intFromPtr(&markDirty)));

    // .layer = .background,
    // .anchor = .{ .top = true, .bottom = true, .left = true, .right = true },
    // .exclusive = .ignore,
    // .namespace = "background",
    // });

    // const window = &windows.items[0];
    if (context.display.dispatch() != .SUCCESS) return error.DispatchFailed;

    const scheduler = &context.scheduler;
    var file_notifier = try FileNotifier.init(allocator);
    defer file_notifier.close();

    // try scheduler.addRepeatTask(Task.create(&surface, markDirty), 1000);
    // try scheduler.addRepeatTask(Task.create(&bar, markDirty), 1000);
    var sw: StatusWidgets = undefined;
    try sw.configure(bar, scheduler, &file_notifier);
    var bw = BasicWidgets.init(surface);
    var nbw = BasicWidgets.init(notification_surface);
    try frame(&bw);
    try drawBar(&sw);
    try drawNotifications(&nbw, &notification_handler);
    // var dbus_connection = dbus.busGet(.session, &err.?);

    log.info("Starting event loop", .{});
    while (true) {
        // log.debug("starting poll", .{});
        const timeout = context.scheduler.runPendingGetTimeInterval();
        if (surface.updated) {
            try frame(&bw);
        }
        if (bar.updated) {
            try drawBar(&sw);
        }
        if (notification_surface.updated) {
            try drawNotifications(&nbw, &notification_handler);
        }
        if (context.display.flush() != .SUCCESS) return error.DispatchFailed;
        try context.watch.wait(timeout orelse 10000);
    }
}
pub fn frame(bw: *BasicWidgets) !void {
    var buf: [64]u8 = undefined;
    const s = bw.surface;
    s.beginFrame();
    defer s.endFrame();
    log.debug("background", .{});
    {
        const overlay = try bw.overlay(.{ .src = @src() });
        defer overlay.end();
        try bw.image("/home/ss/pictures/draw/logo.png", .stretch, .{ .src = @src() });
        const main_layout = try bw.column(.{ .src = @src() });
        defer main_layout.end();
        const innerbox = try bw.row(.{ .src = @src() });
        innerbox.end();
        const innerbox1 = try bw.row(.{ .src = @src() });
        innerbox1.end();
        try bw.text("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.", .{ .src = @src() });
        if (s.getPointer()) |pointer| {
            const coords = std.fmt.bufPrintZ(&buf, "({[x]d:.2},{[y]d:.2})", pointer.pos) catch unreachable;
            try bw.text(coords, .{ .src = @src() });
        } else {
            try bw.text("Pointer not in Surface", .{ .src = @src() });
        }
        const button = try bw.button("button", .{ .src = @src() });
        if (button.clicked) log.debug("Button Clicked", .{});
    }
    // const buf8 = s.currentBuffer().shared_memory;
    // var buf32: []u32 = undefined;
    // buf32.ptr = @alignCast(@ptrCast(buf8.ptr));
    // buf32.len = buf8.len / 4;
    // @memset(buf32, @bitCast(try style.Color.fromString("#00ff0000")));
}

fn drawBar(sw: *StatusWidgets) !void {
    log.debug("drawing bar", .{});
    const bw = sw.bw;
    const s = bw.surface;
    s.beginFrame();
    s.clear(.{});
    defer s.endFrame();
    {
        const box = try bw.row(.{ .src = @src() });
        defer box.end();
        try sw.time("%I:%M %p %a %b %d,%Y", .{ .src = @src() });
        try sw.battery(" {percentage}% {status}", .{ .src = @src() });
        try sw.disk("/home/ss", "{used} {free} {total}", .{ .src = @src() });
        try sw.mem("{used} 󰒋  {swapUsed} ", .{ .src = @src() });
    }
}

const notification_styles = std.EnumArray(NotificationHandler.Notification.Urgency, Style).init(.{
    .low = Style{ .items = &.{.{ .bg_color = Style.color("#008800") }} },
    .normal = Style{ .items = &.{
        .{ .border_radius = 4 },
        .{ .border_width = 2 },
        .{ .border_color = Style.color("#ffffffff") },
        .{ .bg_color = Style.color("#80000080") },
        .{ .padding = 4 },
        .{ .margin = 4 },
    } },
    .critical = Style{ .items = &.{.{ .bg_color = Style.color("#880000") }} },
});
fn drawNotifications(bw: *BasicWidgets, notification_handler: *NotificationHandler) !void {
    const notifications = notification_handler.notifications.notification_list.items;
    log.debug("drawing {} notifications", .{notifications.len});
    const s = bw.surface;
    if (notifications.len == 0) {
        s.unmap();
        return;
    }
    s.beginFrame();
    s.clear(.{ .a = 0 });
    defer s.endFrame();
    {
        const box = try bw.column(.{ .src = @src() });
        box.md.style = &Style{ .items = &.{.{ .bg_color = Style.color("#80808080") }} };
        defer box.end();
        for (notifications) |notification| {
            const column = try bw.column(.{ .src = @src(), .extra = notification.id });
            column.md.style = &notification_styles.get(notification.urgency);
            defer column.end();
            try bw.label(notification.summary, .{ .ptr = @ptrCast(notification.summary) });
            try bw.label(notification.body, .{ .ptr = @ptrCast(notification.body) });
        }
    }
}

pub fn markDirty(surface: *Surface) void {
    surface.updated = true;
}
fn handleNotifyReturn(args: Notifications.NotificationsInterface.NotifyReturnArgs, ptr: *u32) void {
    ptr.* = args.id;
    log.info("notification id: {}", .{args.id});
}
fn handleStatusNotifierWatcherSignal(_: *StatusNotifierWatcher.StatusNotifierWatcherInterface, signal: StatusNotifierWatcher.StatusNotifierWatcherInterface.Signal, _: *anyopaque) void {
    switch (signal) {
        inline else => |payload, tag| log.debug("{s}({})", .{ @tagName(tag), dbus.argStructPrinter(payload) }),
    }
}
fn handleGetStatusNotifierWatcherItems(args: []const [*:0]const u8, _: *anyopaque) void {
    log.debug("status notifier items: {}", .{dbus.argStructPrinter(.{args})});
}
fn handleGetProtocolVersion(arg: i32, _: *anyopaque) void {
    log.debug("protocol version: {}", .{arg});
}

test {
    _ = common;
    _ = common.dbus;
}
