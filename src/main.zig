const std = @import("std");
const log = std.log;
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;
const style = @import("./style.zig");
const cairo = @import("./cairo.zig");
const Window = @import("./LayerSurfaceWindow.zig");
const Scheduler = @import("./Scheduler.zig");
const Task = Scheduler.Task;
const Surface = @import("./Surface.zig");
pub const Context = @import("./Context.zig");
pub const BasicWidgets = @import("./BasicWidgets.zig");
pub const Seat = Context.Seat;
pub const Windows = std.ArrayList(Window);
const c = @cImport({
    @cInclude("time.h");
});

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
    var windows = Windows.init(allocator);
    // _ = image;
    try windows.append(.{
        // Background
        .layer = .background,
        .anchor = .{ .top = true, .bottom = true, .left = true, .right = true },
        .exclusiveZone = -1,
        .namespace = "background",
    });

    const output = context.outputs.items[0];
    const window = &windows.items[0];
    var surface = try output.initLayerSurface(&context, window);
    try surface.setListeners();
    if (context.display.dispatch() != .SUCCESS) return error.DispatchFailed;

    var text_buf: [1024]u8 = undefined;
    text_buf[0] = 0;
    var frame_data = FrameData{
        .buf = &text_buf,
        .surface = &surface,
        .seat = &context.seat,
    };
    const scheduler = &context.scheduler;
    try scheduler.addRepeatTask(Task.create(*Surface, markDirty, &surface), 1000);
    var pollfds = [_]std.posix.pollfd{
        .{
            .events = std.posix.POLL.IN,
            .fd = context.displayFd(),
            .revents = 0,
        },
    };
    log.debug("Starting event loop", .{});
    while (true) {
        // log.debug("starting poll", .{});
        const timeout = context.scheduler.runPendingGetTimeInterval();
        if (surface.redraw) {
            try frame_data.frame();
        }
        if (context.display.flush() != .SUCCESS) return error.DispatchFailed;
        // should we block indefinitely?
        switch (try std.posix.poll(&pollfds, timeout orelse 1)) {
            0 => {
                // timeout
            },
            else => |num_events| {
                // events
                // log.debug("Got input from {} fd's", .{num_events});
                var num_events_remaining = num_events;
                for (pollfds) |pollfd| {
                    if (pollfd.revents != 0) {
                        num_events_remaining -= 1;
                        // something happened!
                        // log.debug("got events 0x{x}", .{pollfd.revents});
                        if (context.display.dispatch() != .SUCCESS) return error.DispatchFailed;
                        if (num_events_remaining == 0) break;
                    }
                }
                assert(num_events_remaining == 0);
            },
        }
    }
}

const FrameData = struct {
    buf: []u8,
    counter: u32 = 0,
    surface: *Surface,
    seat: *Seat,
    pub fn timerTask(self: *FrameData) void {
        self.frame() catch unreachable;
    }

    pub fn frame(self: *FrameData) !void {
        // self.text_widget.text = std.fmt.bufPrintZ(self.buf, "{}", .{self.counter}) catch unreachable;
        const time = std.time.timestamp();
        const time_string = c.ctime((&time));
        const time_string_len = std.mem.len(time_string);
        // log.debug("{s}: drawing frame {}", .{ time_string[0 .. time_string_len - 1], self.counter });
        self.counter += 1;
        const s = self.surface;
        const bw = BasicWidgets{ .surface = s };
        {
            s.beginFrame();
            defer s.endFrame();
            const overlay = try bw.overlay(.{ .src = @src() });
            defer bw.end(overlay);
            try bw.image("/home/ss/pictures/draw/experiment.png", .{ .src = @src() });
            const box = try bw.row(.{ .src = @src() });
            defer bw.end(box);
            const innerbox = try bw.row(.{ .src = @src() });
            bw.end(innerbox);
            const innerbox1 = try bw.row(.{ .src = @src() });
            bw.end(innerbox1);
            const innerbox2 = try bw.column(.{ .src = @src() });
            defer bw.end(innerbox2);
            const innerbox3 = try bw.column(.{ .src = @src() });
            bw.end(innerbox3);
            const innerbox4 = try bw.row(.{ .src = @src() });
            bw.end(innerbox4);
            const timestring = std.fmt.bufPrintZ(self.buf, "{s}", .{time_string[0 .. time_string_len - 1]}) catch unreachable;
            try bw.text(timestring, .{ .src = @src() });
            if (s.getPointer()) |pointer| {
                var buf: [64]u8 = undefined;
                const coords = std.fmt.bufPrintZ(&buf, "({[x]d},{[y]d})", pointer.pos) catch unreachable;
                try bw.text(coords, .{ .src = @src() });
            } else {
                try bw.text("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.", .{ .src = @src() });
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
};

pub fn markDirty(surface: *Surface) void {
    surface.redraw = true;
}
