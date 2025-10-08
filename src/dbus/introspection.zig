const std = @import("std");
const log = std.log;
const assert = std.debug.assert;
const dbus = @import("dbus.zig");
pub const isInterface = dbus.isInterface;
pub const getSignature = dbus.getSignature;
const ComptimeWriter = struct {
    comptime text: [:0]const u8 = "",
    pub fn write(self: *ComptimeWriter, bytes: []const u8) !void {
        self.text = self.text ++ bytes;
    }
    pub const writeAll = write;
    pub fn print(self: *ComptimeWriter, comptime format: []const u8, args: anytype) !void {
        self.text = self.text ++ std.fmt.comptimePrint(format, args);
    }
    pub fn getText(self: *ComptimeWriter) [:0]const u8 {
        // @compileLog(self.text);
        return self.text;
    }
};

pub const Node = struct {
    name: [:0]const u8,
    interfaces: []const Interface,
    children: []const Node = &.{},
    pub fn xml(self: Node, writer: anytype, options: Options) !void {
        if (options.is_root) {
            try writer.writeAll(introspection_header_xml);
            try writer.writeAll("<node>\n");
        } else {
            try writer.print("<node name=\"{s}\">\n", .{self.name});
        }

        if (options.include_default_interfaces) {
            try writer.writeAll(default_interfaces_xml);
        }
        for (self.interfaces) |interface| try interface.xml(writer);

        if (options.include_children) {
            for (self.children) |child| try child.xml(writer, .{ .is_root = false });
        } else {
            for (self.children) |child| try writer.print("<node name=\"{s}\"/>\n", .{child.name});
        }
        return writer.writeAll("</node>\n");
    }
    pub const Options = struct {
        /// whether to include name xor header
        is_root: bool = true,
        /// whether to include org.freedesktop.DBus.{Instropsectable,Peer,Properties}
        include_default_interfaces: bool = true,
        /// whether or not to include children fully or just include an empty child for introspection
        include_children: bool = true,
    };
};
pub const Interface = struct {
    name: [:0]const u8,
    methods: []const Method,
    signals: []const Signal,
    properties: []const Property,
    pub fn xml(self: Interface, writer: anytype) !void {
        try writer.print("  <interface name=\"{s}\">\n", .{self.name});
        for (self.methods) |arg| try arg.xml(writer);
        for (self.signals) |arg| try arg.xml(writer);
        for (self.properties) |arg| try arg.xml(writer);
        try writer.writeAll("  </interface>\n");
    }
};
pub const Method = struct {
    name: [:0]const u8,
    args: []const Arg,
    pub fn xml(self: Method, writer: anytype) !void {
        try writer.print("    <method name=\"{s}\">\n", .{self.name});
        for (self.args) |arg| try arg.xml(writer);
        return writer.writeAll("    </method>\n");
    }
};
pub const Property = struct {
    name: [:0]const u8,
    type: [:0]const u8,
    access: Access,
    pub const Access = enum { read, write, readwrite };
    pub fn xml(self: Property, writer: anytype) !void {
        try writer.print("    <property name=\"{s}\" type=\"{s}\" access=\"{s}\">\n", .{ self.name, self.type, @tagName(self.access) });
    }
};
pub const Signal = struct {
    name: [:0]const u8,
    args: []const Arg,
    pub fn xml(self: Signal, writer: anytype) !void {
        try writer.print("    <signal name=\"{s}\">\n", .{self.name});
        for (self.args) |arg| try arg.xml(writer);
        try writer.writeAll("    </signal>\n");
    }
};
pub const Arg = struct {
    name: ?[:0]const u8 = null,
    type: [:0]const u8,
    direction: ?Direction = null,
    pub const Direction = enum { in, out };
    pub fn xml(self: Arg, writer: anytype) !void {
        try writer.print("      <arg type=\"{s}\"", .{self.type});
        if (self.name) |name| try writer.print(" name=\"{s}\"", .{name});
        if (self.direction) |direction| try writer.print(" direction=\"{s}\"", .{@tagName(direction)});
        try writer.writeAll("/>\n");
    }
};
pub const introspection_header_xml =
    \\<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
    \\                      "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
    \\
;

pub const default_interfaces_xml =
    \\  <interface name="org.freedesktop.DBus.Properties">
    \\    <method name="Get">
    \\      <arg type="s" name="interface_name" direction="in"/>
    \\      <arg type="s" name="property_name" direction="in"/>
    \\      <arg type="v" name="value" direction="out"/>
    \\    </method>
    \\    <method name="GetAll">
    \\      <arg type="s" name="interface_name" direction="in"/>
    \\      <arg type="a{sv}" name="properties" direction="out"/>
    \\    </method>
    \\    <method name="Set">
    \\      <arg type="s" name="interface_name" direction="in"/>
    \\      <arg type="s" name="property_name" direction="in"/>
    \\      <arg type="v" name="value" direction="in"/>
    \\    </method>
    \\    <signal name="PropertiesChanged">
    \\      <arg type="s" name="interface_name"/>
    \\      <arg type="a{sv}" name="changed_properties"/>
    \\      <arg type="as" name="invalidated_properties"/>
    \\    </signal>
    \\  </interface>
    \\  <interface name="org.freedesktop.DBus.Introspectable">
    \\    <method name="Introspect">
    \\      <arg type="s" name="xml_data" direction="out"/>
    \\    </method>
    \\  </interface>
    \\  <interface name="org.freedesktop.DBus.Peer">
    \\    <method name="Ping"/>
    \\    <method name="GetMachineId">
    \\      <arg type="s" name="machine_uuid" direction="out"/>
    \\    </method>
    \\  </interface>
    \\
;

pub inline fn genInterfaceIntrospection(InterfaceType: type) Interface {
    comptime var methods: []const Method = &.{};
    comptime var signals: []const Signal = &.{};
    comptime var properties: []const Property = &.{};

    inline for (@typeInfo(InterfaceType).Struct.decls) |decl| {
        const split_name = dbus.splitName(decl.name);
        const member_name = split_name[1];
        switch (split_name[0]) {
            .invalid => {},
            .method => {
                const function = @field(InterfaceType, decl.name);
                const fn_info = @typeInfo(@TypeOf(function)).Fn;
                const params = fn_info.params;
                comptime var args: []const Arg = &.{};
                assert(params[0].type == *InterfaceType or params[0].type == *const InterfaceType);
                if (params.len == 2 and
                    params[1].type != null and
                    @typeInfo(params[1].type.?) == .Struct and
                    !@hasDecl(params[1].type.?, "dbus_type"))
                {
                    for (@typeInfo(params[1].type.?).Struct.fields) |field| {
                        args = args ++ [_]Arg{.{ .name = field.name, .type = getSignature(field.type), .direction = .in }};
                    }
                } else {
                    for (params[1..]) |param| {
                        args = args ++ .{.{ .type = getSignature(param.type.?), .direction = .in }};
                    }
                }

                if (fn_info.return_type != null and
                    @typeInfo(fn_info.return_type.?) == .Struct and
                    !@hasDecl(fn_info.return_type.?, "dbus_type"))
                {
                    for (@typeInfo(fn_info.return_type.?).Struct.fields) |field| {
                        args = args ++ .{.{ .name = field.name, .type = getSignature(field.type), .direction = .out }};
                    }
                } else {
                    if (fn_info.return_type) |return_type| {
                        if (return_type != void) args = args ++ [_]Arg{.{ .type = getSignature(return_type), .direction = .out }};
                    }
                }
                methods = methods ++ [_]Method{.{ .name = member_name, .args = args }};
            },
            .signal => {
                const function = @field(InterfaceType, decl.name);
                const fn_info = @typeInfo(@TypeOf(function)).Fn;
                const params = fn_info.params;
                comptime var args: []const Arg = &.{};
                assert(params[0].type == *InterfaceType or params[0].type == *const InterfaceType);
                if (params.len == 2 and
                    params[1].type != null and
                    @typeInfo(params[1].type.?) == .Struct and
                    !@hasDecl(params[1].type.?, "dbus_type"))
                {
                    for (@typeInfo(params[1].type.?).Struct.fields) |field| {
                        args = args ++ [_]Arg{.{ .name = field.name, .type = getSignature(field.type) }};
                    }
                } else {
                    for (params[1..]) |param| {
                        args = args ++ .{.{ .type = getSignature(param.type.?) }};
                    }
                }

                signals = signals ++ [_]Signal{.{ .name = member_name, .args = args }};
            },
            .getProperty => {
                const function = @field(InterfaceType, decl.name);
                const fn_info = @typeInfo(@TypeOf(function)).Fn;
                const params = fn_info.params;
                const write_access = blk: for (properties) |property| if (std.mem.eql(u8, property.name.?, member_name)) break :blk true else false;
                assert(params[0].type == *InterfaceType or params[0].type == *const InterfaceType and params.len == 2);
                properties = properties ++ [_]Property{.{ .name = member_name, .access = if (write_access) .readwrite else .read, .type = getSignature(params[1].type) }};
            },
            .setProperty => {
                const function = @field(InterfaceType, decl.name);
                const fn_info = @typeInfo(@TypeOf(function)).Fn;
                const params = fn_info.params;
                const read_access = blk: for (properties) |property| if (std.mem.eql(u8, property.name.?, member_name)) break :blk true else false;
                assert(params[0].type == *InterfaceType or params[0].type == *const InterfaceType and params.len == 2);
                properties = properties ++ [_]Property{.{ .name = member_name, .access = if (read_access) .readwrite else .write, .type = getSignature(params[1].type) }};
            },
        }
    }

    return Interface{
        .name = @field(InterfaceType, "interface"),
        .methods = methods,
        .properties = properties,
        .signals = signals,
    };
}
/// create a string from Object type
pub inline fn fromType(ObjectType: type) [:0]const u8 {
    comptime {
        var interfaces: []const Interface = &.{};
        for (@typeInfo(ObjectType).Struct.fields) |field| {
            if (isInterface(field.type)) {
                const interface = genInterfaceIntrospection(field.type);
                interfaces = interfaces ++ .{interface};
            }
        }

        const path = ObjectType.path;
        const children = if (@hasDecl(ObjectType, "children")) ObjectType.children else &.{};
        const introspection = Node{ .interfaces = interfaces, .children = children, .name = path };
        var writer = ComptimeWriter{};
        introspection.xml(&writer, .{}) catch unreachable;
        // @compileLog();
        return writer.getText();
    }
}
