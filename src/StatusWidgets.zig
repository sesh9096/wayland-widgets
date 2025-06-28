//! Factory for Widgets and wrapper around Surface
//! methods beginning with `get` should only create a Widget object and not attach it to the tree
const std = @import("std");
const posix = std.posix;
const log = std.log;
const assert = std.debug.assert;
const File = std.fs.File;
const Dir = std.fs.Dir;
const common = @import("./common.zig");
const format = common.format;
const Surface = common.Surface;
const Widget = common.Widget;
const cairo = common.cairo;
const pango = common.pango;
const Rect = common.Rect;
const c = common.c;
const Scheduler = common.Scheduler;
const Task = Scheduler.Task;
const FileNotifier = common.FileNotifier;
const IdGenerator = common.IdGenerator;
const BasicWidgets = @import("./BasicWidgets.zig");
const IN = FileNotifier.IN;

surface: *Surface,
bw: BasicWidgets,
scheduler: *Scheduler,
file_notifier: *FileNotifier,

timestamp: i64 = 0,
batteries: BatteryList = undefined,
const BatteryList = std.ArrayList(Battery);

const Self = @This();
pub fn configure(self: *Self, surface: *Surface, scheduler: *Scheduler, file_notifier: *FileNotifier) !void {
    self.surface = surface;
    self.bw = BasicWidgets{ .surface = surface };
    self.scheduler = scheduler;
    self.file_notifier = file_notifier;
    const allocator = surface.allocator;
    try scheduler.addRepeatTask(Task.create(*Self, updateTime, self), Scheduler.second);

    self.batteries = BatteryList.init(allocator);
    if (Battery.power_supply_dir.fd == -1) { // this should not happen unless uninitialized
        const power_supply_path = "/sys/class/power_supply/";
        Battery.power_supply_dir = try std.fs.openDirAbsolute(power_supply_path, .{ .iterate = true });
        // watch directory for batteries
        try self.file_notifier.addWatch(
            power_supply_path,
            IN.CREATE | IN.DELETE | IN.DELETE_SELF,
            FileNotifier.Handler.create(*Self, batteryDeviceMonitor, self),
        );
    }
    var iterator = Battery.power_supply_dir.iterate();
    while (try iterator.next()) |entry| {
        var battery_dir = try Battery.power_supply_dir.openDir(entry.name, .{});
        defer battery_dir.close();
        var type_file = try battery_dir.openFile("type", .{});
        defer type_file.close();
        var buf: [1024]u8 = undefined;
        const len = try type_file.readAll(&buf);
        if (std.mem.eql(u8, buf[0..(len - 1)], "Battery")) {
            const name = try allocator.dupeZ(u8, entry.name);
            try self.batteries.append(try Battery.init(name));
        }
        // default = Self{ .capacity_file = try battery_dir.open("capacity") };
    }
    try scheduler.addRepeatTask(Task.create(*Self, updateBatteries, self), Scheduler.five_seconds);
}
pub fn updateBatteries(self: *Self) void {
    for (self.batteries.items) |*bat| {
        if (Battery.power_supply_dir.access(bat.name, .{})) {
            bat.readPercentage() catch log.err("readPercentage error on {s}", .{bat.name});
            bat.readStatus() catch log.err("readStatus error on {s}", .{bat.name});
        } else |err| {
            bat.status = .Unknown;
            log.warn("Battery {s} not accessible: {}", .{ bat.name, err });
        }
    }
}
fn logEvent(_: *anyopaque, event: *FileNotifier.Event) void {
    log.info("0x{x} {?s}", .{ event.mask, event.getName() });
}
fn batteryDeviceMonitor(self: *Self, event: *FileNotifier.Event) void {
    log.debug("Received event {}", .{event});
    if (event.mask & IN.DELETE != 0) {
        const name = event.getName().?;
        for (self.batteries.items, 0..) |bat, i| {
            if (std.mem.eql(u8, bat.name, name)) {
                self.batteries.orderedRemove(i).deinit();
                break;
            }
        }
    }
}

pub fn deinit(self: *Self) void {
    _ = self;
}
pub fn updateTime(self: *Self) void {
    self.timestamp = std.time.timestamp();
}

pub fn getTime(self: *const Self, fmt: [:0]const u8, buffer: []u8, id_gen: IdGenerator) !*Widget {
    const time_struct = c.localtime(&@intCast(self.timestamp));
    const len = c.strftime(buffer.ptr, buffer.len, fmt, time_struct);
    return self.bw.getLabel(@ptrCast(buffer[0..len]), id_gen);
}

pub fn time(self: *const Self, fmt: [:0]const u8, buffer: []u8, id_gen: IdGenerator) !void {
    const widget = try self.getTime(fmt, buffer, id_gen);
    try self.surface.addWidget(widget);
}

pub const Battery = struct {
    name: [:0]const u8 = "BAT0", // owned memory allocated on init
    capacity_file: File,
    percentage: u8 = 0, // max 100
    status_file: File,
    status: Status = undefined,

    pub var power_supply_dir: Dir = .{ .fd = -1 };
    pub const Status = enum { Discharging, Charging, Full, @"Not Charging", Unknown };
    pub fn init(name: [:0]const u8) !Battery {
        var dir = try power_supply_dir.openDir(name, .{});
        defer dir.close();
        return Battery{
            .name = name,
            .capacity_file = try dir.openFile("capacity", .{}),
            .status_file = try dir.openFile("status", .{}),
        };
    }
    pub fn deinit(self: *const Battery) void {
        self.capacity_file.close();
        self.status_file.close();
    }
    fn readPercentage(self: *Battery) !void {
        var buf: [4]u8 = undefined;
        try self.capacity_file.seekTo(0);
        const len = try self.capacity_file.readAll(&buf);
        self.percentage = try std.fmt.parseInt(u8, buf[0..(len - 1)], 10);
    }
    fn readStatus(self: *Battery) !void {
        var buf: [64]u8 = undefined;
        try self.status_file.seekTo(0);
        const len = try self.status_file.readAll(&buf);
        // buf[len - 1] = 0;
        self.status = std.meta.stringToEnum(Status, buf[0..(len - 1)]) orelse .Unknown;
    }
};

pub fn getBattery(self: *Self, fmt: [:0]const u8, buffer: []u8, id_gen: IdGenerator) !*Widget {
    // const capacity_file = try std.fs.openFileAbsolute("/sys/class/power_supply/BAT0/capacity", .{});
    const batteries = self.batteries.items;
    const bat = if (batteries.len > 0) batteries[0] else return error.BatteryNotFound;

    if (bat.status == .Unknown) {
        return error.BatteryNotFound;
    }
    const battery_text = try format.formatToBuffer(bat, fmt, buffer);
    buffer[battery_text.len] = 0;
    return self.bw.getLabel(@ptrCast(battery_text), id_gen);
}

pub fn battery(self: *Self, fmt: [:0]const u8, buffer: []u8, id_gen: IdGenerator) !void {
    const widget = try self.getBattery(fmt, buffer, id_gen);
    try self.surface.addWidget(widget);
}

// /proc/meminfo /proc/swaps

pub fn getDisk(self: *Self, path: [*:0]const u8, fmt: [:0]const u8, buffer: []u8, id_gen: IdGenerator) !*Widget {
    var stats: Statvfs = undefined;
    try statvfsWithError(path, &stats);
    const avail_size = stats.f_bsize * stats.f_bavail;
    const total_size = stats.f_frsize * stats.f_blocks;
    // this is because some blocks are reserved for privileged users
    const used_size = total_size - stats.f_bsize * stats.f_bfree;
    const d = Disk{
        .total_bytes = total_size,
        .used_bytes = used_size,
        .free_bytes = avail_size,
    };
    const text = try format.formatToBuffer(d, fmt, buffer);
    buffer[text.len] = 0;
    return self.bw.getLabel(@ptrCast(text), id_gen);
}
pub fn disk(self: *Self, path: [*:0]const u8, fmt: [:0]const u8, buffer: []u8, id_gen: IdGenerator) !void {
    const widget = try self.getDisk(path, fmt, buffer, id_gen);
    try self.surface.addWidget(widget);
}

pub const Disk = struct {
    total_bytes: u64,
    used_bytes: u64,
    free_bytes: u64,
};

pub fn statvfsWithError(noalias pathname: [*:0]const u8, noalias buf: *Statvfs) !void {
    while (true) {
        return switch (posix.errno(statvfs(pathname, buf))) {
            .SUCCESS => {},
            .ACCES => error.AccessDenied,
            .BADF => unreachable, // not for statvfs, maybe for fstatvfs
            .FAULT => unreachable,
            .INTR => continue,
            .IO => error.FileSystem,
            .LOOP => error.SymLinkLoop,
            .NAMETOOLONG => error.NameTooLong,
            .NOENT => error.FileNotFound,
            .NOMEM => error.SystemResouces,
            .NOSYS => error.SystemOutdated,
            .NOTDIR => error.FileNotFound,
            .OVERFLOW => unreachable,
            else => |err| return posix.unexpectedErrno(err),
        };
    }
}
/// Not wrapped by zig as of version 0.14
pub extern "c" fn statvfs(noalias pathname: [*:0]const u8, noalias buf: *Statvfs) c_int;

pub const Statvfs = extern struct {
    const fsblkcnt_t = c_ulong;
    const fsfilcnt_t = c_ulong;
    f_bsize: c_ulong, // Filesystem block size
    f_frsize: c_ulong, // Fragment size
    f_blocks: fsblkcnt_t, // Size of fs in f_frsize units
    f_bfree: fsblkcnt_t, // Number of free blocks
    f_bavail: fsblkcnt_t, // Number of free blocks for unprivileged users
    f_files: fsfilcnt_t, // Number of inodes
    f_ffree: fsfilcnt_t, // Number of free inodes
    f_favail: fsfilcnt_t, // Number of free inodes for unprivileged users
    f_fsid: c_ulong, // Filesystem ID
    f_flag: c_ulong, // Mount flags
    f_namemax: c_ulong, // Maximum filename length
};
