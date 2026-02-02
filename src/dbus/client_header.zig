const std = @import("std");
const dbus = @import("dbus");
const mem = std.mem;
const log = std.log;
const Allocator = std.mem.Allocator;
const Self = @This();

/// register interest in signals and the signal handlers with the connection.
pub fn register(
    self: *Self,
    connection: *dbus.Connection,
    bus_name: [:0]const u8,
    path: [:0]const u8,
) void {
    self.connection = connection;
    self.bus_name = bus_name;
    self.path = path;
    var buf: [1024]u8 = undefined;
    const str = std.fmt.bufPrintZ(&buf, "type=signal,sender={s},path={s}", .{ bus_name, path }) catch unreachable;
    var err = dbus.Error{};
    connection.addMatch(str, &err);
    _ = connection.addFilter(signalHandler, self, null);
}
pub fn unRegister(self: *Self) void {
    var err = dbus.Error{};
    self.connection.removeFilter(signalHandler, self);
    var buf: [1024]u8 = undefined;
    const str = std.fmt.bufPrintZ(&buf, "type=signal,sender={s},path={s}", .{ self.bus_name, self.path }) catch unreachable;
    self.connection.removeMatch(str, &err);
}
pub fn signalHandler(connection: *dbus.Connection, message: *dbus.Message, user_data: *anyopaque) callconv(.C) dbus.HandlerResult {
    _ = connection;
    const self: *Self = @alignCast(@ptrCast(user_data));
    if (message.getType() == .signal and
        std.mem.orderZ(u8, message.getPath().?, self.path) == .eq
    // and std.mem.orderZ(u8, message.getSender(), self.bus_name) == .eq
    ) {
        const ifname = message.getInterface().?;
        inline for (@typeInfo(Self).Struct.fields) |field| {
            if (dbus.matchesInterface(field.type, ifname)) {
                const interface: *field.type = &@field(self, field.name);
                if (interface.signal_handler) |handler| {
                    return handler(interface, message, interface.data);
                }
            }
        }
    }
    return .not_yet_handled;
}
fn generateSignalHander(handler: anytype) *const fn (@typeInfo(@TypeOf(handler)).Fn.params[0].type.?, *dbus.Message, *anyopaque) dbus.HandlerResult {
    return struct {
        pub fn _function(interface: @typeInfo(@TypeOf(handler)).Fn.params[0].type.?, message: *dbus.Message, user_data: *anyopaque) dbus.HandlerResult {
            const signal_name = message.getMember().?;
            const Signal = @typeInfo(@TypeOf(handler)).Fn.params[1].type.?;
            inline for (@typeInfo(Signal).Union.fields) |field| {
                if (std.mem.orderZ(u8, field.name, signal_name) == .eq) {
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer _ = arena.reset(.free_all);
                    const args = message.getArgsAnytype(field.type, arena.allocator()) catch unreachable;
                    handler(interface, @unionInit(Signal, field.name, args), user_data);
                    return .handled;
                }
            } else {
                log.err("unexpected signal: {s}, interface: {s}", .{ signal_name, message.getInterface().? });
                return .not_yet_handled;
            }
        }
    }._function;
}
fn methodCallGeneric(
    interface: anytype,
    comptime interface_field_name: [:0]const u8,
    method_name: [:0]const u8,
    args: anytype,
    ReplyArgsType: type,
) Allocator.Error!dbus.MethodPendingCall(ReplyArgsType) {
    const self: *Self = @fieldParentPtr(interface_field_name, interface);
    const connection = self.connection;
    const message = dbus.Message.newMethodCall(
        self.bus_name,
        self.path,
        @typeInfo(@TypeOf(interface)).Pointer.child.interface,
        method_name,
    ) orelse return error.OutOfMemory;
    errdefer message.unref();
    try message.appendArgsAnytype(args);

    var pending_return: dbus.MethodPendingCall(ReplyArgsType) = undefined;
    if (!connection.sendWithReply(message, &pending_return.p, -1)) return error.OutOfMemory;
    return pending_return;
}
fn getPropertyGeneric(
    interface: anytype,
    comptime interface_field_name: [:0]const u8,
    property_name: [*:0]const u8,
    PropertyType: type,
) Allocator.Error!dbus.GetPropertyPendingCall(PropertyType) {
    const self: *Self = @fieldParentPtr(interface_field_name, interface);
    const connection = self.connection;
    const message = dbus.Message.newMethodCall(
        self.bus_name,
        self.path,
        "org.freedesktop.DBus.Properties",
        "Get",
    ) orelse return error.OutOfMemory;
    errdefer message.unref();
    const interface_name: [*:0]const u8 = @typeInfo(@TypeOf(interface)).Pointer.child.interface;
    try message.appendArgsAnytype(.{ interface_name, property_name });

    var pending_return: dbus.GetPropertyPendingCall(PropertyType) = undefined;
    if (!connection.sendWithReply(message, &pending_return.p, -1)) return error.OutOfMemory;
    return pending_return;
}
fn setPropertyGeneric(
    interface: anytype,
    comptime interface_field_name: [:0]const u8,
    property_name: [*:0]const u8,
    value: anytype,
) Allocator.Error!void {
    const self: *Self = @fieldParentPtr(interface_field_name, interface);
    const connection = self.connection;
    const message = connection.newMethodCall(
        self.bus_name,
        self.path,
        "org.freedesktop.DBus.Properties",
        "Set",
    ) orelse return error.OutOfMemory;
    errdefer message.unref();
    const interface_name: [*:0]const u8 = @typeInfo(@TypeOf(interface)).Pointer.child.interface;
    if (!message.appendArgs(.{
        interface_name,
        property_name,
        @unionInit(dbus.Arg, @tagName(dbus.Arg.fromType(@TypeOf(value))), value),
    })) return error.OutOfMemory;
    message.setNoReply(true);
    if (!connection.send(message, null)) return error.OutOfMemory;
}

connection: *dbus.Connection = undefined,
bus_name: [:0]const u8 = "",
path: [:0]const u8 = "",
