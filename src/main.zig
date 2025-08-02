const std = @import("std");
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
pub const BasicWidgets = @import("./BasicWidgets.zig");
pub const StatusWidgets = @import("./StatusWidgets.zig");
pub const Seat = Context.Seat;
// pub const Windows = std.ArrayList(Window);
const c = common.c;
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
    var context = try Context.init(allocator);
    defer context.destroy();
    try context.getGlobals();

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
    try frame(&bw);
    try drawBar(&sw);

    var pollfds = [_]std.posix.pollfd{
        .{
            .events = std.posix.POLL.IN,
            .fd = context.displayFd(),
            .revents = 0,
        },
        .{
            .events = std.posix.POLL.IN,
            .fd = file_notifier.fd,
            .revents = 0,
        },
    };
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
        if (context.display.flush() != .SUCCESS) return error.DispatchFailed;
        // wait for events
        switch (try std.posix.poll(&pollfds, timeout orelse 1)) {
            0 => {
                // timeout
            },
            else => |num_events| {
                var num_events_remaining = num_events;
                if (pollfds[0].revents != 0) {
                    num_events_remaining -= 1;
                    if (context.display.dispatch() != .SUCCESS) return error.DispatchFailed;
                }
                if (pollfds[1].revents != 0) {
                    num_events_remaining -= 1;
                    log.debug("got inotify events 0x{x}", .{pollfds[1].revents});
                    try file_notifier.readEvents();
                }
                assert(num_events_remaining == 0);
            },
        }
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
        try bw.image("/home/ss/pictures/draw/experiment.png", .stretch, .{ .src = @src() });
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
    s.clear();
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

pub fn markDirty(surface: *Surface) void {
    surface.redraw = true;
}

test {
    _ = common;
}
