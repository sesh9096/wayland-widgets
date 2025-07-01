//! A dumb scheduler designed to run repeated jobs in a single thread
//! Tasks are function pointers taking in one argument of type *anyopaque and returning void and its associated data.
//! See test cases for example usage
const std = @import("std");
const assert = std.debug.assert;
const timestamp = std.time.milliTimestamp;

const Self = @This();
/// Delayed execution task
pub const Task = struct {
    /// function to execute
    call: *const fn (data: *anyopaque) void,
    /// parameter to job
    data: *anyopaque,

    pub fn create(data: anytype, call: *const fn (data: @TypeOf(data)) void) Task {
        // type check
        const T = @TypeOf(data);
        _ = switch (@typeInfo(T)) {
            .Pointer => |pointer| {
                if (pointer.size != .One) @compileError("Single item Pointer Required, got " ++ @typeName(T));
            },
            else => @compileError("Single item Pointer Required, got " ++ @typeName(T)),
        };
        return Task{
            .call = @ptrCast(call),
            .data = @ptrCast(data),
        };
    }
};
pub const Job = struct {
    /// timestamp in milliseconds
    time: i64,
    /// repeat interval in seconds, set to 0 if no repeat, u32 should be more than enough for this
    repeat_interval: u32 = 0,
    /// whether to reschedule repeating task based on time it was supposed to execute or when it is actually executing
    reschedule_approximate: bool = true,
    task: Task,
};

fn compareFn(context: void, a: Job, b: Job) std.math.Order {
    _ = context;
    return std.math.order(a.time, b.time);
}
const PQ = std.PriorityQueue(Job, void, compareFn);

jobs: PQ,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{ .jobs = PQ.init(allocator, {}) };
}
pub fn deinit(self: *Self) void {
    self.jobs.deinit();
}

pub fn runPendingGetTimeInterval(self: *Self) ?i32 {
    return if (self.runPendingGetNextTime()) |next_time| @intCast(next_time - timestamp()) else null;
}

/// Run jobs whose time is behind the current time and return time of next job in milliseconds
/// IMPORTANT: If there are no pending jobs, return null
pub fn runPendingGetNextTime(self: *Self) ?i64 {
    return self.runPendingGetNextTimeAtTime(timestamp());
}

/// Not that useful externally, separated out mostly for testing purposes
pub fn runPendingGetNextTimeAtTime(self: *Self, time: i64) ?i64 {
    while (self.jobs.peek()) |job| {
        if (job.time <= time) {
            _ = self.jobs.remove(); // we already know what this is, but we need to remove it
            job.task.call(job.task.data); // run task
            if (job.repeat_interval != 0) {
                // reschedule job
                self.addJob(Job{
                    .time = job.repeat_interval + if (job.reschedule_approximate) time else job.time,
                    .repeat_interval = job.repeat_interval,
                    .task = job.task,
                }) catch unreachable; // we should never have allocation errors here
            }
        } else {
            return job.time;
        }
    }
    assert(self.jobs.count() == 0);
    return null;
    // return std.math.maxInt(i64);
}

/// Add a job
pub fn addJob(self: *Self, job: Job) !void {
    try self.jobs.add(job);
}

/// Add a function which will run the next time scheduler is run
pub fn addImmediateTask(self: *Self, task: Task) !void {
    const job = Job{
        .task = task,
        .time = timestamp(),
    };
    try self.addJob(job);
}

/// Add a function which will run repeatedly after interval starting at some time
pub fn addRepeatTaskStartingAt(self: *Self, task: Task, interval: u32, start: i64) !void {
    if (interval == 0) {
        return error.NoInterval;
    }
    const job = Job{
        .task = task,
        .time = start,
        .repeat_interval = interval,
    };
    try self.addJob(job);
}

/// Add a function which will run repeatedly after interval
pub fn addRepeatTask(self: *Self, task: Task, interval: u32) !void {
    return self.addRepeatTaskStartingAt(task, interval, timestamp());
}

pub const second = 1000;
pub const five_seconds = 5 * second;
pub const minute = 60 * second;
pub const five_minutes = 5 * minute;
pub const hour = 60 * minute;
pub const day = 24 * hour;

// Testing

fn exampleTask(data: *i32) void {
    const c: *i32 = @alignCast(@ptrCast(data));
    c.* += 1;
}

test "debug info" {
    std.debug.print("Job Size: {}\n", .{@sizeOf(Job)});
}

test "empty scheduler" {
    const allocator = std.testing.allocator;
    var scheduler = Self.init(allocator);
    if (scheduler.runPendingGetNextTime()) |_| {
        return error.ShouldBeNull;
    }
}

test "scheduler immediate" {
    const allocator = std.testing.allocator;
    var scheduler = Self.init(allocator);
    defer scheduler.deinit();
    var tracker: i32 = 0;
    const next_time = timestamp() + 5;
    try scheduler.addImmediateTask(.{ .call = @ptrCast(&exampleTask), .data = @ptrCast(&tracker) });
    try scheduler.addJob(Job{
        .time = next_time,
        .task = Task.create(&tracker, exampleTask),
    });
    if (scheduler.runPendingGetNextTime()) |next_time_returned| {
        if (next_time != next_time_returned) {
            return error.IncorrectNextTime;
        }
    } else {
        return error.NoTasksLeft;
    }
    if (tracker != 1) {
        std.debug.print("Tracker: {}\n", .{tracker});
        return error.TaskNotPerformed;
    }
}

test "scheduler repeat" {
    const allocator = std.testing.allocator;
    var scheduler = Self.init(allocator);
    defer scheduler.deinit();
    var tracker: i32 = 0;
    const initial_time = 0;
    try scheduler.addRepeatTaskStartingAt(.{ .call = @ptrCast(&exampleTask), .data = @ptrCast(&tracker) }, 5, 0);
    if (scheduler.jobs.items.len != 1) {
        return error.IncorrectNumberOfTasks;
    }
    if (scheduler.runPendingGetNextTimeAtTime(initial_time)) |next_time_returned| {
        if (initial_time + 5 != next_time_returned) {
            return error.IncorrectNextTime;
        }
    } else {
        return error.NoTasksLeft;
    }
    if (tracker != 1) {
        std.debug.print("Tracker: {}\n", .{tracker});
        return error.TaskNotPerformed;
    }
}
