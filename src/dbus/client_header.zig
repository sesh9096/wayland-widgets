const std = @import("std");
const dbus = @import("dbus");
const mem = std.mem;
const log = std.log;
const assert = std.debug.assert;
const SendingOptions = dbus.SendingOptions;
const SendingError = dbus.SendingError;
const Allocator = std.mem.Allocator;
const Self = @This();

/// register interest in signals and the signal handlers with the connection.
pub fn register(
    self: *Self,
    connection: *dbus.Connection,
    bus_name: [:0]const u8,
    path: [:0]const u8,
) void {
    self.* = .{
        .connection = connection,
        .bus_name = bus_name,
        .path = path,
    };
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
        var ifname = message.getInterface().?;
        if (std.mem.orderZ(u8, ifname, "org.freedesktop.DBus.Properties") == .eq) {
            if (std.mem.orderZ(u8, message.getMember().?, "PropertiesChanged") == .eq) {
                if (message.getArgsAnytype(struct { [*:0]const u8 }, std.testing.failing_allocator)) |args| {
                    ifname = args[0];
                } else |err| {
                    log.warn("Got error when parsing PropertiesChanged args: {}", .{err});
                    return .not_yet_handled;
                }
            } else {
                log.warn("Ignoring unknown signal org.freedesktop.DBus.Properties.{?s}", .{message.getMember()});
                return .not_yet_handled;
            }
        }
        inline for (@typeInfo(Self).Struct.fields) |field| {
            if (dbus.matchesInterface(field.type, ifname)) {
                const interface: *field.type = &@field(self, field.name);
                if (interface.signal_handler) |handler| {
                    return handler(interface, message, interface.data);
                }
            }
        }
        log.info("Ignoring unknown signal {s}.{?s}", .{ ifname, message.getMember() });
    }
    return .not_yet_handled;
}
fn generateSignalHander(handler: anytype) *const fn (@typeInfo(@TypeOf(handler)).Fn.params[0].type.?, *dbus.Message, *anyopaque) dbus.HandlerResult {
    return struct {
        pub fn _function(interface: @typeInfo(@TypeOf(handler)).Fn.params[0].type.?, message: *dbus.Message, user_data: *anyopaque) dbus.HandlerResult {
            const signal_name = message.getMember().?;
            const Signal = @typeInfo(@TypeOf(handler)).Fn.params[1].type.?;
            const data: @typeInfo(@TypeOf(handler)).Fn.params[2].type.? = @alignCast(@ptrCast(user_data));
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer _ = arena.reset(.free_all);
            if (std.mem.orderZ(u8, message.getInterface().?, "org.freedesktop.DBus.Properties") == .eq) {
                // PropertiesChanged
                const args = message.getArgsAnytype(PropertiesChangedArgs, arena.allocator()) catch unreachable;
                handler(interface, Signal{ .PropertiesChanged = args }, data);
                return .handled;
            }
            inline for (@typeInfo(Signal).Union.fields) |field| {
                if (std.mem.orderZ(u8, field.name, signal_name) == .eq) {
                    const args = message.getArgsAnytype(field.type, arena.allocator()) catch unreachable;
                    handler(interface, @unionInit(Signal, field.name, args), data);
                    return .handled;
                }
            } else {
                log.err("unexpected signal: {s}, interface: {s}", .{ signal_name, message.getInterface().? });
                return .not_yet_handled;
            }
        }
    }._function;
}
const PropertiesChangedArgs = struct {
    changed_properties: dbus.Vardict,
    invalidated_properties: []const [*:0]const u8,
};
fn methodCallGeneric(
    interface: anytype,
    comptime interface_field_name: [:0]const u8,
    method_name: [:0]const u8,
    args: anytype,
    sending_options: dbus.SendingOptions,
    ReplyArgsType: type,
) dbus.SendingError!?dbus.MethodPendingCall(ReplyArgsType) {
    const self: *Self = @fieldParentPtr(interface_field_name, interface);
    const connection = self.connection;
    return connection.methodCallWithOptionsAndReply(
        self.bus_name,
        self.path,
        @typeInfo(@TypeOf(interface)).Pointer.child.interface,
        method_name,
        args,
        sending_options,
        dbus.MethodPendingCall(ReplyArgsType),
    );
}
fn getPropertyGeneric(
    interface: anytype,
    comptime interface_field_name: [:0]const u8,
    property_name: [*:0]const u8,
    _sending_options: dbus.SendingOptions,
    PropertyType: type,
) dbus.SendingError!dbus.GetPropertyPendingCall(PropertyType) {
    const self: *Self = @fieldParentPtr(interface_field_name, interface);
    const connection = self.connection;
    const interface_name: [*:0]const u8 = @typeInfo(@TypeOf(interface)).Pointer.child.interface;
    var sending_options = _sending_options;
    if (sending_options.no_reply) {
        // we always want a reply
        sending_options.no_reply = false;
        log.warn("no_reply set on org.freedesktop.DBus.Properties.Get call", .{});
    }
    return (try connection.methodCallWithOptionsAndReply(
        self.bus_name,
        self.path,
        "org.freedesktop.DBus.Properties",
        "Get",
        .{ interface_name, property_name },
        sending_options,
        dbus.GetPropertyPendingCall(PropertyType),
    )).?;
}
fn setPropertyGeneric(
    interface: anytype,
    comptime interface_field_name: [:0]const u8,
    property_name: [*:0]const u8,
    value: anytype,
) SendingError!void {
    const self: *Self = @fieldParentPtr(interface_field_name, interface);
    const connection = self.connection;
    const interface_name: [*:0]const u8 = @typeInfo(@TypeOf(interface)).Pointer.child.interface;
    assert(try connection.methodCallWithOptionsAndReply(
        self.bus_name,
        self.path,
        "org.freedesktop.DBus.Properties",
        "Set",
        .{
            interface_name,
            property_name,
            @unionInit(dbus.Arg, @tagName(dbus.Arg.fromType(@TypeOf(value))), value),
        },
        .{ .no_reply = true },
        struct { p: *dbus.PendingCall },
    ) == null);
}
fn getAllGeneric(
    interface: anytype,
    comptime interface_field_name: [:0]const u8,
    _sending_options: SendingOptions,
    PropertiesType: type,
) SendingError!dbus.GetAllPendingCall(PropertiesType) {
    const self: *Self = @fieldParentPtr(interface_field_name, interface);
    const connection = self.connection;
    const interface_name: [*:0]const u8 = @typeInfo(@TypeOf(interface)).Pointer.child.interface;
    var sending_options = _sending_options;
    if (sending_options.no_reply) {
        // we always want a reply
        sending_options.no_reply = false;
        log.warn("no_reply set on org.freedesktop.DBus.Properties.GetAll call", .{});
    }
    return (try connection.methodCallWithOptionsAndReply(
        self.bus_name,
        self.path,
        "org.freedesktop.DBus.Properties",
        "GetAll",
        .{interface_name},
        sending_options,
        dbus.GetAllPendingCall(PropertiesType),
    )).?;
}

connection: *dbus.Connection = undefined,
bus_name: [:0]const u8 = "",
path: [:0]const u8 = "",
