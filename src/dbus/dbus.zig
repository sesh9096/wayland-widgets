const std = @import("std");
const log = std.log;
const Allocator = std.mem.Allocator;
const common = @import("../common.zig");
pub const introspection = @import("introspection.zig");
const assert = std.debug.assert;
// const c = common.c;
pub const c = @cImport({
    @cInclude("dbus/dbus.h");
});
pub const dbus_bool_t = enum(u32) { false = 0, true = 1 };

pub const BusType = enum(c_int) {
    session = c.DBUS_BUS_SESSION,
    system = c.DBUS_BUS_SYSTEM,
    starter = c.DBUS_BUS_STARTER,
};
pub extern fn dbus_bus_get(@"type": BusType, @"error": ?*Error) ?*Connection;
pub const busGet = dbus_bus_get;
pub const Connection = opaque {
    pub extern fn dbus_connection_get_unix_fd(connection: *Connection, fd: *c_int) dbus_bool_t;

    pub fn getFd(connection: *Connection) i32 {
        var fd: i32 = undefined;
        assert(dbus_connection_get_unix_fd(connection, &fd) == 1);
        return fd;
    }

    pub extern fn dbus_connection_send(connection: *Connection, message: *Message, client_serial: ?*u32) dbus_bool_t;
    pub const send = dbus_connection_send;

    pub extern fn dbus_connection_send_with_reply(connection: *Connection, message: *Message, pending_return: [*c]?*PendingCall, timeout_milliseconds: c_int) dbus_bool_t;
    pub const sendWithReply = dbus_connection_send_with_reply;

    pub extern fn dbus_connection_send_with_reply_and_block(connection: *Connection, message: *Message, timeout_milliseconds: c_int, err: *Error) ?*Message;
    pub const sendWithReplyAndBlock = dbus_connection_send_with_reply_and_block;

    pub extern fn dbus_connection_flush(connection: *Connection) void;
    pub const flush = dbus_connection_flush;

    pub extern fn dbus_connection_register_object_path(connection: *Connection, path: [*:0]const u8, vtable: *const ObjectPathVTable, user_data: *anyopaque) dbus_bool_t;
    pub const registerObjectPath = dbus_connection_register_object_path;

    pub extern fn dbus_connection_try_register_object_path(connection: *Connection, path: [*:0]const u8, vtable: *const ObjectPathVTable, user_data: *anyopaque, err: *Error) dbus_bool_t;
    pub const tryRegisterObjectPath = dbus_connection_try_register_object_path;

    pub extern fn dbus_connection_set_watch_functions(
        connection: *Connection,
        add_function: AddWatchFunction,
        remove_function: RemoveWatchFunction,
        toggled_function: ?WatchToggledFunction,
        data: *anyopaque,
        free_data_function: FreeFunction,
    ) dbus_bool_t;
    pub const setWatchFunctions = dbus_connection_set_watch_functions;

    pub extern fn dbus_connection_set_dispatch_status_function(
        connection: *Connection,
        function: DispatchStatusFunction,
        data: *anyopaque,
        free_data_function: FreeFunction,
    ) void;
    pub const setDispatchStatusFunction = dbus_connection_set_dispatch_status_function;

    pub extern fn dbus_connection_add_filter(connection: *Connection, function: HandleMessageFunction, user_data: ?*anyopaque, free_data_function: ?FreeFunction) dbus_bool_t;
    pub const addFilter = dbus_connection_add_filter;

    pub extern fn dbus_connection_remove_filter(connection: *Connection, function: HandleMessageFunction, user_data: ?*anyopaque) void;
    pub const removeFilter = dbus_connection_remove_filter;

    pub extern fn dbus_bus_request_name(connection: *Connection, name: [*:0]const u8, flags: u32, err: *Error) i32;
    pub const requestName = dbus_bus_request_name;

    pub extern fn dbus_bus_release_name(connection: *Connection, name: [*:0]const u8, err: *Error) i32;
    pub const releaseName = dbus_bus_release_name;

    pub extern fn dbus_bus_add_match(connection: *Connection, rule: [*:0]const u8, err: *Error) void;
    pub const addMatch = dbus_bus_add_match;

    pub extern fn dbus_bus_remove_match(connection: *Connection, rule: [*:0]const u8, err: *Error) void;
    pub const removeMatch = dbus_bus_remove_match;

    pub extern fn dbus_connection_dispatch(connection: *Connection) void;
    pub const dispatch = dbus_connection_dispatch;

    pub extern fn dbus_connection_get_dispatch_status(connection: *Connection) DispatchStatus;
    pub const getDispatchStatus = dbus_connection_get_dispatch_status;

    pub const RegisterObjectError = error{ OutOfMemory, ObjectPathInUse };
    /// TODO: document
    pub fn registerObject(connection: *Connection, object: anytype) RegisterObjectError!void {
        const T = @TypeOf(object);
        assert(@typeInfo(T) == .Pointer);
        const ObjectType = @typeInfo(T).Pointer.child;
        const vtable = &struct {
            pub const _vtable = ObjectPathVTable{
                .message_function = getObjectHandleMessageFunction(@typeInfo(T).Pointer.child),
            };
        }._vtable;
        const path = if (@hasDecl(ObjectType, "path")) ObjectType.path else object.path;
        if (@hasField(ObjectType, "connection") and @TypeOf(@field(object, "connection")) == *Connection) {
            object.connection = connection;
        }
        var err = Error{};
        err.init();
        if (connection.tryRegisterObjectPath(path, vtable, @ptrCast(object), &err) != .true) {
            if (std.mem.orderZ(u8, err.name.?, "org.freedesktop.DBus.Error.NoMemory") == .eq) {
                return error.OutOfMemory;
            } else if (std.mem.orderZ(u8, err.name.?, "org.freedesktop.DBus.Error.ObjectPathInUse") == .eq) {
                return error.ObjectPathInUse;
            } else {
                log.err("{s} {s}", .{ err.name.?, err.message.? });
            }
        } else {
            log.info("Registered object {s}", .{path});
        }
    }
    pub fn doNothing(_: *Connection, _: *anyopaque) callconv(.C) void {}
};

pub const Watch = opaque {
    pub extern fn dbus_watch_get_fd(watch: *Watch) i32;
    pub const getFd = dbus_watch_get_fd;

    pub extern fn dbus_watch_get_unix_fd(watch: *Watch) i32;
    pub const getUnixFd = dbus_watch_get_unix_fd;

    pub extern fn dbus_watch_get_socket(watch: *Watch) i32;
    pub const getSocket = dbus_watch_get_socket;

    pub extern fn dbus_watch_get_flags(watch: *Watch) u32;
    pub const getFlags = dbus_watch_get_flags;

    pub extern fn dbus_watch_get_data(watch: *Watch) ?*anyopaque;
    pub const getData = dbus_watch_get_data;

    pub extern fn dbus_watch_set_data(watch: *Watch, data: ?*anyopaque, free_data_function: FreeFunction) void;
    pub const setData = dbus_watch_set_data;

    pub extern fn dbus_watch_handle(watch: *Watch, flags: u32) dbus_bool_t;
    pub const handle = dbus_watch_handle;

    pub extern fn dbus_watch_get_enabled(watch: *Watch) dbus_bool_t;
    pub const getEnabled = dbus_watch_get_enabled;

    pub const READABLE: c_int = 1;
    pub const WRITABLE: c_int = 2;
    pub const ERROR: c_int = 4;
    pub const HANGUP: c_int = 8;
};

pub const FreeFunction = *const fn (connection: *Connection, user_data: *anyopaque) callconv(.C) void;
pub const AddWatchFunction = *const fn (watch: *Watch, user_data: *anyopaque) callconv(.C) dbus_bool_t;
pub const RemoveWatchFunction = *const fn (watch: *Watch, user_data: *anyopaque) callconv(.C) void;
pub const WatchToggledFunction = *const fn (watch: *Watch, user_data: *anyopaque) callconv(.C) void;
pub const DispatchStatusFunction = *const fn (connection: *Connection, new_status: DispatchStatus, data: *anyopaque) callconv(.C) void;

pub const ObjectPathVTable = struct {
    unregister_function: ObjectPathUnregisterFunction = Connection.doNothing,
    message_function: HandleMessageFunction,
    dbus_internal_pad1: *const fn (*anyopaque) void = undefined,
    dbus_internal_pad2: *const fn (*anyopaque) void = undefined,
    dbus_internal_pad3: *const fn (*anyopaque) void = undefined,
    dbus_internal_pad4: *const fn (*anyopaque) void = undefined,
};

pub const ObjectPathUnregisterFunction = *const fn (connection: *Connection, user_data: *anyopaque) callconv(.C) void;
pub const HandleMessageFunction = *const fn (connection: *Connection, message: *Message, user_data: *anyopaque) callconv(.C) HandlerResult;
pub const HandlerResult = enum(c_int) {
    handled = c.DBUS_HANDLER_RESULT_HANDLED,
    not_yet_handled = c.DBUS_HANDLER_RESULT_NOT_YET_HANDLED,
    need_more_memory = c.DBUS_HANDLER_RESULT_NEED_MEMORY,
};
pub const DispatchStatus = enum(c_int) {
    data_remains = c.DBUS_DISPATCH_DATA_REMAINS,
    complete = c.DBUS_DISPATCH_COMPLETE,
    need_memory = c.DBUS_DISPATCH_NEED_MEMORY,
};

pub const Error = packed struct {
    name: ?[*:0]const u8 = null,
    message: ?[*:0]const u8 = null,
    dummy1: u1 = 1,
    dummy2: u1 = 0,
    dummy3: u1 = 0,
    dummy4: u1 = 0,
    dummy5: u1 = 0,
    padding1: ?*anyopaque = null,

    pub extern fn dbus_error_init(*Error) void;
    pub const init = dbus_error_init;
};

pub const Message = opaque {
    pub extern fn dbus_message_new(message_type: Message.Type) *Message;
    pub const new = dbus_message_new;

    pub const Type = enum(c_int) {
        invalid = c.DBUS_MESSAGE_TYPE_INVALID,
        method_call = c.DBUS_MESSAGE_TYPE_METHOD_CALL,
        method_return = c.DBUS_MESSAGE_TYPE_METHOD_RETURN,
        @"error" = c.DBUS_MESSAGE_TYPE_ERROR,
        signal = c.DBUS_MESSAGE_TYPE_SIGNAL,
    };

    pub extern fn dbus_message_new_method_call(destination: ?[*:0]const u8, path: [*:0]const u8, iface: ?[*:0]const u8, method: [*:0]const u8) ?*Message;
    pub const newMethodCall = dbus_message_new_method_call;

    pub extern fn dbus_message_new_method_return(method_call: *Message) ?*Message;
    pub const newMethodReturn = dbus_message_new_method_return;

    pub extern fn dbus_message_new_signal(path: [*:0]const u8, iface: [*:0]const u8, name: [*:0]const u8) ?*Message;
    pub const newSignal = dbus_message_new_signal;

    pub extern fn dbus_message_new_error(reply_to: *Message, error_name: [*:0]const u8, error_message: ?[*:0]const u8) ?*Message;
    pub const newError = dbus_message_new_error;

    pub extern fn dbus_message_new_error_printf(reply_to: *Message, error_name: [*:0]const u8, error_format: [*:0]const u8, ...) ?*Message;
    pub const newErrorPrintf = dbus_message_new_error_printf;

    pub extern fn dbus_message_ref(*Message) void;
    pub const ref = dbus_message_ref;

    pub extern fn dbus_message_unref(*Message) void;
    pub const unref = dbus_message_unref;

    pub extern fn dbus_message_get_type(message: *Message) Type;
    pub const getType = dbus_message_get_type;

    pub extern fn dbus_message_get_path(message: *Message) ?[*:0]const u8;
    pub const getPath = dbus_message_get_path;

    pub extern fn dbus_message_set_path(message: *Message, object_path: [*:0]const u8) dbus_bool_t;
    pub const setPath = dbus_message_set_path;

    pub extern fn dbus_message_get_interface(message: *Message) ?[*:0]const u8;
    pub const getInterface = dbus_message_get_interface;

    pub extern fn dbus_message_set_interface(message: *Message, iface: [*:0]const u8) dbus_bool_t;
    pub const setInterface = dbus_message_set_interface;

    pub extern fn dbus_message_get_member(message: *Message) ?[*:0]const u8;
    pub const getMember = dbus_message_get_member;

    pub extern fn dbus_message_set_member(message: *Message, member: [*:0]const u8) dbus_bool_t;
    pub const setMember = dbus_message_set_member;

    pub extern fn dbus_message_get_serial(message: *Message) u32;
    pub const getSerial = dbus_message_get_serial;

    pub extern fn dbus_message_set_serial(message: *Message, serial: u32) void;
    pub const setSerial = dbus_message_set_serial;

    pub extern fn dbus_message_get_args(message: *Message, @"error": ?*Error, first_arg_type: ArgType, ...) dbus_bool_t;
    pub const getArgs = dbus_message_get_args;

    pub extern fn dbus_message_get_args_valist(message: *Message, @"error": ?*Error, first_arg_type: ArgType, var_args: [*c]std.builtin.VaList) dbus_bool_t;
    pub const getArgsVaList = dbus_message_get_args_valist;

    pub extern fn dbus_message_iter_init(message: *Message, iter: *MessageIter) dbus_bool_t;
    pub const iterInit = dbus_message_iter_init;

    pub extern fn dbus_message_iter_init_append(message: *Message, iter: *MessageIter) void;
    pub const iterInitAppend = dbus_message_iter_init_append;

    pub extern fn dbus_message_append_args(message: ?*Message, first_arg_type: ArgType, ...) dbus_bool_t;
    pub const appendArgs = dbus_message_append_args;

    pub extern fn dbus_message_append_args_valist(message: ?*Message, first_arg_type: ArgType, var_args: [*c]std.builtin.VaList) dbus_bool_t;
    pub const appendArgsVaList = dbus_message_append_args_valist;

    /// append all fields of struct
    pub fn appendArgsAnytype(message: *Message, args: anytype) Allocator.Error!void {
        var iter: MessageIter = undefined;
        message.iterInitAppend(&iter);

        const T = @TypeOf(args);
        assert(@typeInfo(T) == .Struct or (@typeInfo(T) == .Pointer and @typeInfo(@typeInfo(T).Pointer.child) == .Struct));
        inline for (std.meta.fields(T)) |field| {
            try iter.appendAnytype(@field(args, field.name));
        }
    }
};

pub const MessageIter = extern struct {
    dummy1: ?*anyopaque = null,
    dummy2: ?*anyopaque = null,
    dummy3: u32 = 0,
    dummy4: c_int = 0,
    dummy5: c_int = 0,
    dummy6: c_int = 0,
    dummy7: c_int = 0,
    dummy8: c_int = 0,
    dummy9: c_int = 0,
    dummy10: c_int = 0,
    dummy11: c_int = 0,
    pad1: c_int = 0,
    pad2: ?*anyopaque = null,
    pad3: ?*anyopaque = null,

    pub extern fn dbus_message_iter_has_next(iter: *MessageIter) dbus_bool_t;
    pub const hasNext = dbus_message_iter_has_next;

    pub extern fn dbus_message_iter_next(iter: *MessageIter) dbus_bool_t;
    pub const next = dbus_message_iter_next;

    pub extern fn dbus_message_iter_get_arg_type(iter: *MessageIter) ArgType;
    pub const getArgType = dbus_message_iter_get_arg_type;

    pub extern fn dbus_message_iter_get_element_type(iter: *MessageIter) ArgType;
    pub const getElementType = dbus_message_iter_get_element_type;

    pub extern fn dbus_message_iter_get_element_count(iter: *MessageIter) c_int;
    pub const getElementCount = dbus_message_iter_get_element_count;

    // pub extern fn dbus_message_iter_get_array_len(iter: *MessageIter) c_int;
    // pub const getArrayLen = dbus_message_iter_get_array_len;

    pub extern fn dbus_message_iter_get_basic(iter: *MessageIter, value: *anyopaque) void;
    pub const getBasic = dbus_message_iter_get_basic;

    pub extern fn dbus_message_iter_recurse(iter: *MessageIter, sub: *MessageIter) void;
    pub const recurse = dbus_message_iter_recurse;

    pub extern fn dbus_message_iter_append_basic(iter: *MessageIter, @"type": ArgType, value: *const anyopaque) dbus_bool_t;
    pub const appendBasic = dbus_message_iter_append_basic;

    pub extern fn dbus_message_iter_append_fixed_array(iter: *MessageIter, element_type: ArgType, value: *const anyopaque, n_elements: c_int) dbus_bool_t;
    pub const appendFixedArray = dbus_message_iter_append_fixed_array;

    pub extern fn dbus_message_iter_open_container(iter: *MessageIter, @"type": ArgType, contained_signature: [*c]const u8, sub: *MessageIter) dbus_bool_t;
    pub const openContainer = dbus_message_iter_open_container;

    pub extern fn dbus_message_iter_close_container(iter: *MessageIter, sub: *MessageIter) dbus_bool_t;
    pub const closeContainer = dbus_message_iter_close_container;

    pub extern fn dbus_message_iter_abandon_container(iter: *MessageIter, sub: *MessageIter) void;
    pub const abandonContainer = dbus_message_iter_abandon_container;

    pub extern fn dbus_message_iter_abandon_container_if_open(iter: *MessageIter, sub: *MessageIter) void;
    pub const abandonContainerIfOpen = dbus_message_iter_abandon_container_if_open;

    pub fn appendAnytype(iter: *MessageIter, arg: anytype) Allocator.Error!void {
        const is_pointer: bool = comptime blk: {
            const arg_type_info = @typeInfo(@TypeOf(arg));
            if (arg_type_info == .Pointer and arg_type_info.Pointer.size != .Slice) {
                if (arg_type_info.Pointer.sentinel) |sentinel| {
                    if (arg_type_info.Pointer.child == u8 and @as(*const u8, @ptrCast(sentinel)).* == 0) {
                        break :blk false;
                    }
                }
                break :blk true;
            }
            break :blk false;
        };
        const T = if (is_pointer) @TypeOf(arg.*) else @TypeOf(arg);

        const ptr: *const anyopaque = @ptrCast(if (is_pointer) arg else &arg);
        switch (@typeInfo(T)) {
            .Bool, .Int => {
                if (iter.appendBasic(ArgType.fromType(T).?, ptr) != .true) return error.OutOfMemory;
            },
            .Float => |float| {
                if (float.bits != 64) @compileError("Expected f64");
                if (iter.appendBasic(.double, ptr) != 1) return error.OutOfMemory;
            },
            .Array => |array| {
                if (array.child == u8 and array.sentinel != null and @as(*u8, array.sentinel.?).* == 0) {
                    if (iter.appendBasic(.string, ptr) != 1) return error.OutOfMemory;
                } else {
                    var sub_iter: MessageIter = undefined;
                    const signature = getSignature(array.child) ++ [_]u8{0};
                    if (iter.openContainer(.array, signature.ptr, &sub_iter) != 1) return error.OutOfMemory;
                    for (if (is_pointer) arg.* else arg) |elem|
                        try sub_iter.appendAnytype(elem);
                    if (iter.closeContainer(&sub_iter) != 1) return error.OutOfMemory;
                }
            },
            .Pointer => |pointer| {
                if (pointer.sentinel) |sentinel| {
                    // Dbus String
                    if (pointer.child == u8 and @as(*const u8, @ptrCast(sentinel)).* == 0)
                        if (iter.appendBasic(.string, ptr) != .true) return error.OutOfMemory;
                }
                switch (pointer.size) {
                    .One => {
                        @compileError("Error: Invalid type " ++ @typeName(pointer.child));
                    },
                    .Many => {},
                    .Slice => {
                        // Assuming Dbus Array
                        var sub_iter: MessageIter = undefined;
                        const signature = getSignature(pointer.child) ++ [_]u8{0};
                        if (iter.openContainer(.array, signature.ptr, &sub_iter) != .true) return error.OutOfMemory;
                        for (if (is_pointer) arg.* else arg) |elem|
                            try sub_iter.appendAnytype(elem);
                        if (iter.closeContainer(&sub_iter) != .true) return error.OutOfMemory;
                    },
                    .C => @compileError("Intent unclear"),
                }
            },
            .Struct => |data| {
                // TODO: Dict Entries, struct
                if (isDictEntry(T)) {
                    var sub_iter: MessageIter = undefined;
                    if (iter.openContainer(.dict_entry, null, &sub_iter) != 1) return error.OutOfMemory;
                    if (iter.closeContainer(&sub_iter) != .true) return error.OutOfMemory;
                } else {
                    // struct
                    var sub_iter: MessageIter = undefined;
                    if (iter.openContainer(.@"struct", null, &sub_iter) != 1) return error.OutOfMemory;
                    for (data.fields) |field| {
                        try sub_iter.appendAnytype(@field(ptr, field.name));
                    }
                    if (iter.closeContainer(&sub_iter) != .true) return error.OutOfMemory;
                }
                @compileError("Not Implemented");
            },
            .Enum => |enum_info| {
                // enum masquerading as a int
                if (enum_info.tag_type != void) {
                    if (iter.appendBasic(ArgType.fromType(enum_info.tag_type).?, ptr) != .true) return error.OutOfMemory;
                } else @compileError("Cannot convert type " ++ @typeName(T) ++ " to dbus type");
            },
            .Union => {
                if (T == Arg) {
                    // variant
                    // TODO: get signature
                    var sig_buf: [4096]u8 = undefined;
                    sig_buf[0] = @intCast(@intFromEnum(ptr));
                    sig_buf[1] = 0;
                    var sub_iter: MessageIter = undefined;
                    if (iter.openContainer(.variant, &sig_buf, &sub_iter) != 1) return error.OutOfMemory;
                    switch (if (is_pointer) arg.* else arg) {
                        .array => {},
                        .@"struct" => {},
                        .variant => {},
                        inline else => |*field_ptr, tag| {
                            if (iter.appendBasic(ArgType.fromType(tag).?, field_ptr) != .true) return error.OutOfMemory;
                        },
                    }
                    if (iter.closeContainer(&sub_iter) != .true) return error.OutOfMemory;
                    // var sub_iter: MessageIter = undefined;
                    // const signature = getSignature(pointer.child) ++ [_]u8{0};
                    // if (iter.openContainer(.variant, signature.ptr, &sub_iter) != .true) return error.OutOfMemory;
                    // switch (if (is_pointer) arg.* else arg) {
                    //     inline else => |val| try sub_iter.appendAnytype(arg, val),
                    // }
                    // if (iter.closeContainer(&sub_iter) != .true) return error.OutOfMemory;
                } else {
                    @compileError("Cannot convert type " ++ @typeName(T) ++ " to dbus type");
                }
            },
            else => {
                @compileError("Cannot convert type " ++ @typeName(T) ++ " to dbus type");
            },
        }
    }

    /// write into a pointer the value from the iterator
    /// Example:
    /// var a: i32;
    /// iter.getAnytype(&a);
    pub fn getAnytype(iter: *MessageIter, allocator: Allocator, dst: anytype) TypeMismatchOrAllocatorError!void {
        assert(@typeInfo(@TypeOf(dst)) == .Pointer and @typeInfo(@TypeOf(dst)).Pointer.is_const == false and @typeInfo(@TypeOf(dst)).Pointer.size == .One);
        const ChildType = @typeInfo(@TypeOf(dst)).Pointer.child;
        const arg_type = iter.getArgType();

        switch (@typeInfo(ChildType)) {
            .Bool, .Int => {
                try testMatchingTypes(ChildType, arg_type);
                if (ArgType.fromType(ChildType) != arg_type) return error.TypeMismatch;
                iter.getBasic(@ptrCast(dst));
            },
            .Float => |float| {
                if (float.bits != 64) @compileError("Expected f64");
                try testMatchingTypes(ChildType, arg_type);
                if (arg_type != .double) return error.TypeMismatch;
                iter.getBasic(@ptrCast(dst));
            },
            .Array => |array| {
                if (array.child == u8 and array.sentinel != null and @as(*u8, array.sentinel.?).* == 0) {
                    // Needed?
                    if (arg_type != .string) return error.TypeMismatch;
                    iter.getBasic(@ptrCast(dst));
                } else {
                    if (arg_type != .array) return error.TypeMismatch;
                    const element_count = iter.getElementCount();
                    const element_type = iter.getElementType();
                    try testMatchingTypes(array.child, element_type);
                    if (element_count != array.len) {
                        log.err("expected a{c} to have length {}, has length {}", .{ @as(u8, element_type), array.len, element_count });
                        return error.TypeMismatch;
                    }

                    var sub_iter: MessageIter = undefined;
                    iter.recurse(&sub_iter);
                    for (dst.*) |*elem|
                        try sub_iter.getAnytype(elem);
                }
            },
            .Pointer => |pointer| {
                if (pointer.sentinel) |sentinel| {
                    // Dbus String
                    if (pointer.child == u8 and @as(*const u8, @ptrCast(sentinel)).* == 0) {
                        iter.getBasic(@ptrCast(dst));
                    }
                }
                switch (pointer.size) {
                    .One => {
                        @compileError("Error: Invalid type " ++ @typeName(pointer.child));
                    },
                    .Many => {},
                    .Slice => {
                        if (arg_type != .array) return error.TypeMismatch;
                        const element_count = iter.getElementCount();
                        const element_type = iter.getElementType();
                        try testMatchingTypes(pointer.child, element_type);
                        const buf = try allocator.alloc(pointer.child, @intCast(element_count));

                        var sub_iter: MessageIter = undefined;
                        iter.recurse(&sub_iter);
                        for (buf) |*elem|
                            try sub_iter.getAnytype(allocator, elem);
                        dst.* = buf;
                    },
                    .C => @compileError("Intent unclear"),
                }
            },
            .Struct => {
                if (ChildType == Arg.ObjectPath) {
                    iter.getBasic(@ptrCast(&dst.path));
                } else if (ChildType == Arg.Signature) {
                    iter.getBasic(@ptrCast(&dst.signature));
                }
            },
            .Union => {
                if (ChildType == Arg) {
                    // variant
                    dst.* = allocator.create(ArgType);
                    var sub_iter: MessageIter = undefined;
                    iter.recurse(&sub_iter);
                    dst.*.* = sub_iter.getType();
                } else {
                    @compileError("Cannot convert type " ++ @typeName(ChildType) ++ " to dbus type");
                }
            },
            else => {
                @compileError("Cannot convert type " ++ @typeName(ChildType) ++ " to dbus type");
            },
        }
        // if (ArgType.fromType(ChildType)) |expected_type| {
        //     if (arg_type != expected_type) {
        //         log.err("Dbus Type Mismatch, expected {}, got {}", .{ expected_type, arg_type });
        //         return error.TypeMismatch;
        //     }
        //     iter.getBasic(dst);
        //     return;
        // }
    }
};
pub fn testMatchingTypes(expected_type: type, actual: ArgType) TypeMismatchError!void {
    if (ArgType.fromType(expected_type)) |expected| {
        if (expected != actual) {
            log.err("Dbus Type Mismatch, expected {}, got {}", .{ expected, actual });
            return error.TypeMismatch;
        }
    } else {
        log.err("Unable to convert type: {s}", .{@typeName(expected_type)});
        return error.TypeMismatch;
    }
}
pub inline fn typeMismatchErrorString(expected_type: type) [:0]const u8 {
    if (ArgType.fromType(expected_type)) |expected| {
        return std.fmt.comptimePrint("Dbus Type Mismatch, expected {}", .{expected});
    }
    return "Nonconvertible type " ++ @typeName(expected_type);
}

pub const TypeMismatchError = error{TypeMismatch};
pub const TypeMismatchOrAllocatorError = (Allocator.Error || TypeMismatchError);

/// invoke the function after parsing message args and return resulting function return
pub fn handleMethodCall(interface: anytype, message: *Message, function: anytype) Allocator.Error!*Message {
    assert(@typeInfo(@TypeOf(interface)) == .Pointer);
    const fn_type_info = @typeInfo(@TypeOf(function));
    const fn_info = if (fn_type_info == .Pointer) @typeInfo(fn_type_info.Pointer.child).Fn else fn_type_info.Fn;
    assert(fn_info.params[0].type == @TypeOf(interface));
    var iter: MessageIter = undefined;
    _ = message.iterInit(&iter);

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena_allocator.allocator();
    defer _ = arena_allocator.reset(.free_all); // potentially make more efficient?

    const params = fn_info.params;
    const ret = if (fn_info.params.len == 2 and
        params[1].type != null and
        @typeInfo(params[1].type.?) == .Struct and !@hasDecl(params[1].type.?, "dbus_type"))
    blk: {
        var args: params[1].type.? = undefined;
        inline for (@typeInfo(@TypeOf(args)).Struct.fields) |field| {
            iter.getAnytype(allocator, &@field(args, field.name)) catch |err| switch (err) {
                error.TypeMismatch => return message.newError(c.DBUS_ERROR_INVALID_ARGS, typeMismatchErrorString(field.type)) orelse return error.OutOfMemory,
                error.OutOfMemory => return error.OutOfMemory,
            };
            _ = iter.next();
        }
        break :blk function(interface, args);
    } else blk: {
        const ArgsTuple = std.meta.ArgsTuple(@TypeOf(function));
        var args: ArgsTuple = undefined;
        inline for (&args, 0..) |*arg, i| {
            if (i == 0) {
                arg.* = interface;
            } else {
                // iter.getArgType()
                iter.getAnytype(allocator, arg) catch |err| switch (err) {
                    error.TypeMismatch => return message.newError(c.DBUS_ERROR_INVALID_ARGS, typeMismatchErrorString(@typeInfo(@TypeOf(arg)).Pointer.child)) orelse return error.OutOfMemory,
                    error.OutOfMemory => return error.OutOfMemory,
                };
                _ = iter.next();
            }
        }
        assert(iter.hasNext() == .false);
        break :blk @call(.auto, function, args);
    };

    const reply = message.newMethodReturn() orelse return error.OutOfMemory;
    // log.debug("return type: {s}", .{@typeName(@TypeOf(ret))});
    if (@typeInfo(@TypeOf(ret)) == .Struct and !@hasDecl(@TypeOf(ret), "dbus_type")) {
        try reply.appendArgsAnytype(ret);
    } else {
        if (@TypeOf(ret) != void) try reply.appendArgsAnytype(.{ret});
    }
    return reply;
}
inline fn matchesInterface(T: type, interface_name: [*:0]const u8) bool {
    return isInterface(T) and std.mem.orderZ(u8, T.interface, interface_name) == .eq;
}

pub fn getObjectHandleMessageFunction(DbusObjectType: type) HandleMessageFunction {
    // *const fn (connection: *Connection, message: *Message, user_data: *DbusObjectType)
    assert(@typeInfo(DbusObjectType) == .Struct);
    return struct {
        pub fn handleMessage(
            connection: *Connection,
            message: *Message,
            user_data: *anyopaque,
        ) callconv(.C) HandlerResult {
            // log.debug("got message", .{});
            const interface_name = message.getInterface().?;
            const method_name = message.getMember().?;

            const data: *DbusObjectType = @alignCast(@ptrCast(user_data));
            inline for (@typeInfo(DbusObjectType).Struct.fields) |field| {
                if (matchesInterface(field.type, interface_name)) {
                    const interface_pointer = if (@typeInfo(@TypeOf(@field(data, field.name))) == .Pointer) @field(data, field.name) else &@field(data, field.name);
                    const InterfaceType = @typeInfo(@TypeOf(interface_pointer)).Pointer.child;
                    inline for (@typeInfo(InterfaceType).Struct.decls) |decl| {
                        const split_name = comptime splitName(decl.name);
                        if (split_name[0] == .method and std.mem.orderZ(u8, method_name, split_name[1]) == .eq) {
                            const function = @field(InterfaceType, decl.name);
                            const return_message = handleMethodCall(interface_pointer, message, function) catch unreachable;
                            _ = connection.send(return_message, null);
                            break;
                        }
                    } else {
                        _ = connection.send(message.newError(c.DBUS_ERROR_UNKNOWN_METHOD, "Method name you invoked isn't known by the object you invoked it on.").?, null);
                    }
                    return .handled;
                }
            } else if (std.mem.orderZ(u8, interface_name, "org.freedesktop.DBus.Properties") == .eq) {
                if (std.mem.orderZ(u8, method_name, "Get") == .eq) {
                    // TODO
                } else if (std.mem.orderZ(u8, method_name, "Set") == .eq) {
                    // TODO
                } else if (std.mem.orderZ(u8, method_name, "GetAll") == .eq) {
                    // TODO
                } else {
                    _ = connection.send(message.newError(c.DBUS_ERROR_UNKNOWN_METHOD, "Method name you invoked isn't known by the object you invoked it on.").?, null);
                }
            } else if (std.mem.orderZ(u8, interface_name, "org.freedesktop.DBus.Introspectable") == .eq) {
                if (std.mem.orderZ(u8, method_name, "Introspect") == .eq) {
                    _ = connection.send(methodIntrospect(message, DbusObjectType), null);
                } else {
                    _ = connection.send(message.newError(c.DBUS_ERROR_UNKNOWN_METHOD, "Method name you invoked isn't known by the object you invoked it on.").?, null);
                }
            } else if (std.mem.orderZ(u8, interface_name, "org.freedesktop.DBus.Peer") == .eq) {
                if (std.mem.orderZ(u8, method_name, "GetMachineId") == .eq) {
                    _ = connection.send(methodGetMachineId(message), null);
                } else {
                    _ = connection.send(message.newError(c.DBUS_ERROR_UNKNOWN_METHOD, "Method name you invoked isn't known by the object you invoked it on.").?, null);
                }
            } else {
                _ = connection.send(message.newError(c.DBUS_ERROR_UNKNOWN_INTERFACE, "Interface you invoked a method on isn't known by the object.").?, null);
            }
            // inline for (@typeInfo(DbusObjectType).Struct.decls) |decl| {
            //     const obj = @field(DbusObjectType, decl.name);
            //     const ObjType = @TypeOf(obj);
            //     if (matchesInterface(ObjType, interface_name)) {
            //         const interface = @field(DbusObjectType, decl);
            //         _ = interface;
            //         return .handled;
            //     }
            // }
            return .handled;
        }
    }.handleMessage;
}
pub fn methodGetMachineId(message: *Message) *Message {
    const machine_uuid: [*:0]const u8 = blk: {
        const static = struct {
            pub var buf: [32 + 1]u8 = undefined;
            pub var len: u8 = 0;
        };
        if (static.len != 0) {
            break :blk @ptrCast(&static.buf);
        } else {
            const file = std.fs.openFileAbsolute("/var/lib/dbus/machine-id", .{}) catch std.fs.openFileAbsolute("/etc/machine-id", .{}) catch unreachable;
            defer file.close();
            static.len = @intCast(file.read(&static.buf) catch unreachable);
            assert(static.len == static.buf.len);
            static.buf[static.buf.len - 1] = 0;
            break :blk @ptrCast(&static.buf);
        }
    };
    const return_message = message.newMethodReturn().?;
    _ = return_message.appendArgs(.string, machine_uuid);
    return return_message;
}
pub fn methodIntrospect(message: *Message, ObjectType: type) *Message {
    const introspection_string = introspection.fromType(ObjectType);
    const return_message = message.newMethodReturn().?;
    // assert(introspection_string.ptr[introspection_string.len] == 0);
    _ = return_message.appendArgs(.string, &introspection_string.ptr, @intFromEnum(ArgType.invalid));
    return return_message;
}

pub export fn printFilter(connection: *Connection, message: *Message, user_data: *anyopaque) HandlerResult {
    _ = user_data;
    _ = connection;
    log.debug("dbus {s}: {?s}.{?s}", .{ @tagName(message.getType()), message.getInterface(), message.getMember() });
    return .not_yet_handled;
}

pub inline fn getSignature(T: type) [:0]const u8 {
    const error_msg = "Cannot convert type " ++ @typeName(T) ++ " to dbus type";
    return switch (@typeInfo(T)) {
        .Bool => "b",
        .Int => |int| switch (int.bits) {
            8 => "y",
            16 => switch (int.signedness) {
                .signed => "n",
                .unsigned => "q",
            },
            32 => switch (int.signedness) {
                .signed => "i",
                .unsigned => "u",
            },
            64 => switch (int.signedness) {
                .signed => "x",
                .unsigned => "t",
            },
            else => @compileError(error_msg),
        },
        .Float => "d",
        .Array => |array| if (array.sentinel) "s" else "a" ++ getSignature(array.child),
        .Pointer => |pointer| if (pointer.sentinel) |sentinel| {
            // Dbus String
            if (pointer.child == u8 and @as(*const u8, @ptrCast(sentinel)).* == 0) {
                return "s";
            } else {
                @compileError(error_msg);
            }
        } else switch (pointer.size) {
            .One => getSignature(pointer.child),
            .Slice => "a" ++ getSignature(pointer.child),
            else => @compileError(error_msg),
        },
        .Struct => {
            if (T == Arg.ObjectPath) {
                return "o";
            } else if (T == Arg.Signature) {
                return "g";
            }
            const fields = std.meta.fields(T);
            if (@hasField(T, "key") and @hasField(T, "value") and fields.len == 2) {
                return "{" ++ getSignature(fields[0].type) ++ getSignature(fields[1].type) ++ "}";
            } else {
                var sig = "(";
                for (fields) |field| {
                    sig = sig ++ getSignature(field);
                }
                sig = sig ++ ")";
                return sig;
            }
        },
        .Union => {
            if (T == Arg) {
                return "v";
            } else {
                @compileError("Cannot convert type " ++ @typeName(T) ++ " to dbus type");
            }
        },
        .Enum => |enum_info| {
            if (enum_info.tag_type != void) {
                return getSignature(enum_info.tag_type);
            }
        },
        else => {
            @compileError("Cannot convert type " ++ @typeName(T) ++ " to dbus type");
        },
    };
}

pub const ArgType = enum(c_int) {
    invalid = '\x00',
    byte = 'y',
    boolean = 'b',
    int16 = 'n',
    uint16 = 'q',
    int32 = 'i',
    uint32 = 'u',
    int64 = 'x',
    uint64 = 't',
    double = 'd',
    string = 's',
    object_path = 'o',
    signature = 'g',
    unix_fd = 'h',
    array = 'a',
    variant = 'v',
    @"struct" = 'r',
    dict_entry = 'e',

    /// return the appropriate dbus arg type corresponding to a type
    pub inline fn fromType(T: type) ?ArgType {
        // comptime for (std.meta.fields(Arg)) |union_field| {
        //     if (T == union_field.type) {
        //         return std.meta.stringToEnum(ArgType, union_field.name);
        //     }
        // } else if (@hasField(T, "key") and @hasField(T, "value")) {
        //     return .dict_entry;
        // } else if (@typeInfo(T) == .Pointer and @typeInfo(T).Pointer.size == .Slice) return .array;
        // return null;

        return switch (@typeInfo(T)) {
            .Bool => .boolean,
            .Int => |int| switch (int.bits) {
                8 => .byte,
                16 => switch (int.signedness) {
                    .signed => .int16,
                    .unsigned => .uint16,
                },
                32 => switch (int.signedness) {
                    .signed => .int32,
                    .unsigned => .uint32,
                },
                64 => switch (int.signedness) {
                    .signed => .int64,
                    .unsigned => .uint64,
                },
                else => null,
            },
            .Float => |float| if (float.bits == 64) .double else null,
            .Array => |array| if (array.sentinel) "s" else "a" ++ getSignature(array.child),
            .Pointer => |pointer| if (pointer.sentinel) |sentinel|
                if (pointer.child == u8 and @as(*const u8, @ptrCast(sentinel)).* == 0)
                    .string
                else
                    null
            else switch (pointer.size) {
                .One => getSignature(pointer.child),
                .Slice => .array,
                else => null,
            },
            .Struct => if (T == Arg.ObjectPath)
                .object_path
            else if (T == Arg.Signature)
                .signature
            else {
                // TODO: other dictionary types?
                const fields = std.meta.fields(T);
                if (@hasField(T, "key") and @hasField(T, "value") and fields.len == 2) {
                    return .dict_entry;
                } else {
                    return .@"struct";
                }
            },
            .Union => if (T == Arg) .variant else null,
            .Enum => |enum_info| {
                if (enum_info.tag_type != void) {
                    return fromType(enum_info.tag_type);
                }
            },
            else => null,
        };
    }
};

pub const Arg = union(ArgType) {
    invalid: void,
    byte: u8,
    boolean: bool,
    int16: i16,
    uint16: u16,
    int32: i32,
    uint32: u32,
    int64: i64,
    uint64: u64,
    double: f64,
    string: [*:0]const u8,
    object_path: ObjectPath,
    signature: Signature,
    unix_fd: UnixFd,
    array: []Arg,
    variant: *Arg,
    @"struct": []Arg,
    dict_entry: *[2]Arg,
    pub const ObjectPath = struct { path: [*:0]const u8 };
    pub const Signature = struct { signature: [*:0]const u8 };
    pub const UnixFd = struct { fd: i32 };

    pub fn payload(self: *const Arg) *const anyopaque {
        return switch (self.*) {
            inline .invalid, .byte, .boolean, .int16, .uint16, .int32, .uint32, .int64, .uint64, .double, .string, .object_path, .signature, .unix_fd, .array, .variant, .@"struct", .dict_entry => |*contents| @ptrCast(contents),
        };
    }
};
pub fn DictEntry(K: type, V: type) type {
    return struct { key: K, value: V };
}
pub inline fn isDictEntry(T: type) bool {
    return switch (@typeInfo(T)) {
        .Struct => |data| std.mem.eql(u8, data.fields[0].name, "key") and std.mem.eql(u8, data.fields[1].name, "value"),
        else => false,
    };
}

pub const PendingCall = opaque {
    pub extern fn dbus_pending_call_ref(pending: *PendingCall) *PendingCall;
    pub const ref = dbus_pending_call_ref;

    pub extern fn dbus_pending_call_unref(pending: *PendingCall) void;
    pub const unref = dbus_pending_call_unref;

    pub const NotifyFunction = *const fn (pending: *PendingCall, user_data: *anyopaque) callconv(.C) void;
    ///Sets a notification function to be called when the reply is received or the pending call times out.
    pub extern fn dbus_pending_call_set_notify(pending: *PendingCall, function: NotifyFunction, user_data: *void, free_user_data: ?FreeFunction) dbus_bool_t;
    pub const setNotify = dbus_pending_call_set_notify;

    /// Cancels the pending call, such that any reply or error received will just be ignored.
    pub extern fn dbus_pending_call_cancel(pending: *PendingCall) void;
    pub const cancel = dbus_pending_call_cancel;

    /// Checks whether the pending call has received a reply yet, or not.
    pub extern fn dbus_pending_call_get_completed(pending: *PendingCall) dbus_bool_t;
    pub const getCompleted = dbus_pending_call_get_completed;

    /// Gets the reply, or returns NULL if none has been received yet.
    pub extern fn dbus_pending_call_steal_reply(pending: *PendingCall) ?*Message;
    pub const stealReply = dbus_pending_call_steal_reply;

    // void 	dbus_pending_call_block (DBusPendingCall *pending)
    //  	Block until the pending call is completed.

    // dbus_bool_t 	dbus_pending_call_allocate_data_slot (dbus_int32_t *slot_p)
    //  	Allocates an integer ID to be used for storing application-specific data on any DBusPendingCall.

    // void 	dbus_pending_call_free_data_slot (dbus_int32_t *slot_p)
    //  	Deallocates a global ID for DBusPendingCall data slots.

    // dbus_bool_t 	dbus_pending_call_set_data (DBusPendingCall *pending, dbus_int32_t slot, void *data, DBusFreeFunction free_data_func)
    //  	Stores a pointer on a DBusPendingCall, along with an optional function to be used for freeing the data when the data is set again, or when the pending call is finalized.

    // void * 	dbus_pending_call_get_data (DBusPendingCall *pending, dbus_int32_t slot)
    //  	Retrieves data previously set with dbus_pending_call_set_data().

};

/// Not actually in spec but commonly used
pub const VardictEntry = DictEntry([*:0]const u8, Arg);
pub const Vardict = []VardictEntry;

/// create a function which when called sends a dbus signal.
/// - ObjectType must have a field `connection` of type `Connection` to send the signal.
/// - InterfaceType must be an interface of ObjectType, see `Connection.registerObject` for details.
pub fn generateSignalFunction(ObjectType: type, InterfaceType: type, signal_name: [:0]const u8, ArgsType: type) fn (self: *const InterfaceType, args: ArgsType) Allocator.Error!void {
    const interface_field_name = comptime blk: for (@typeInfo(ObjectType).Struct.fields) |field| {
        if (field.type == InterfaceType) {
            break :blk field.name;
        }
    } else @compileError(@typeName(InterfaceType) ++ " is not an a recognized member of " ++ @typeName(ObjectType));
    return struct {
        pub fn _signal(self: *const InterfaceType, args: ArgsType) !void {
            const object: *const ObjectType = @fieldParentPtr(interface_field_name, self);
            const message = Message.newSignal(ObjectType.path, InterfaceType.interface, signal_name) orelse return error.OutOfMemory;
            try message.appendArgsAnytype(args);
            const connection = object.connection;
            // a signal's id is irrelevant
            _ = connection.send(message, null);
        }
    }._signal;
}

pub const Element = enum { invalid, method, signal, getProperty, setProperty };
pub fn splitName(name: [:0]const u8) struct { Element, [:0]const u8 } {
    inline for (@typeInfo(Element).Enum.fields) |field| {
        if (name.len > field.name.len and std.mem.eql(u8, field.name, name[0..field.name.len])) {
            return .{ @field(Element, field.name), name[field.name.len..] };
        }
    }
    return .{ .invalid, name };
}

pub inline fn isInterface(T: type) bool {
    return @typeInfo(T) == .Struct and @hasDecl(T, "interface");
}

// test "introspection" {
//     std.debug.print("{s}", .{genIntrospection(struct {})});
// }

pub const Header = extern struct {
    endianness: Endianness,
    message_type: u8,
    flags: u8 = 0,
    version: u8 = 1,
    length: u32,
    serial: u32,

    pub const Endianness = enum(u8) { little = 'l', big = 'B' };
    pub const MessageType = enum(u8) {
        INVALID = 0,
        METHOD_CALL = 1,
        METHOD_RETURN = 2,
        ERROR = 3,
        SIGNAL = 4,
    };
    pub const flags = struct {
        pub const NO_REPLY_EXPECTED = 0x1;
        pub const NO_AUTO_START = 0x2;
        pub const ALLOW_INTERACTIVE_AUTHORIZATION = 0x4;
    };
};
