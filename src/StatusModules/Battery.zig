const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const File = std.fs.File;
const Dir = std.fs.Dir;

battery_name: [:0]const u8 = "BAT0",
capacity_file: File,
pub const Status = enum { Discharging, Charging, Full, @"Not Charging", Unknown };

var power_supply_dir: Dir = .{ .fd = -1 };
fn initPowerSupplyDir() !void {
    if (power_supply_dir.fd == -1) { // this should not happen unless uninitialized
        power_supply_dir = try std.fs.openDirAbsolute("/sys/class/power_supply/", .{});
        // watch directory for batteries
    }
}

const Self = @This();

pub var batteries: std.ArrayList(Self) = .{ .allocator = undefined, .capacity = 0, .items = .{} };
pub fn getDefault() !Self {
    if (batteries.items.len == null) {
        initPowerSupplyDir();
        const iterator = power_supply_dir.iterate();
        while (try iterator.next()) |entry| {
            const battery_dir = try power_supply_dir.openDir(entry.name, .{});
            defer battery_dir.close();
            var buf: [1024]u8 = undefined;
            (try battery_dir.openFile("type")).readAll(&buf);
            default = Self{ .capacity_file = try battery_dir.open("capacity") };
        }
    }
    return default.?;
}
