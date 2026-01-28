const std = @import("std");
const log = std.log;
const mem = std.mem;
const assert = std.debug.assert;
const dbus = @import("dbus.zig");
const Parser = @import("xml.zig").Parser;
pub const isInterface = dbus.isInterface;
pub const getSignature = dbus.getSignature;
const ComptimeWriter = struct {
    comptime buf: []const u8 = &.{},
    pub fn write(self: *ComptimeWriter, bytes: []const u8) !void {
        self.buf = self.buf ++ bytes;
    }
    pub const writeAll = write;
    pub fn print(self: *ComptimeWriter, comptime format: []const u8, args: anytype) !void {
        self.buf = self.buf ++ std.fmt.comptimePrint(format, args);
    }
    pub fn getText(self: *ComptimeWriter) [:0]const u8 {
        // @compileLog(self.buf);
        return @ptrCast((self.buf ++ .{0})[0..self.buf.len]);
    }
};

pub const Node = struct {
    name: []const u8,
    interfaces: []const Interface,
    children: []const Node = &.{},
    pub fn format(self: Node, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        // try writer.print("format options: fmt:\"{s}\" options:{}\n", .{ fmt, options });
        try self.xml(writer, .{});
    }
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
        try writer.writeAll("</node>\n");
    }
    pub const Options = struct {
        /// whether to include name xor header
        is_root: bool = true,
        /// whether to include org.freedesktop.DBus.{Instropsectable,Peer,Properties}
        include_default_interfaces: bool = true,
        /// whether or not to include children fully or just include an empty child for introspection
        include_children: bool = false,
    };
};
pub const Interface = struct {
    name: []const u8,
    methods: []const Method,
    signals: []const Signal,
    properties: []const Property,
    annotations: []const Annotation = &.{},
    pub fn xml(self: Interface, writer: anytype) !void {
        try writer.print("  <interface name=\"{s}\">\n", .{self.name});
        for (self.methods) |arg| try arg.xml(writer);
        for (self.signals) |arg| try arg.xml(writer);
        for (self.properties) |arg| try arg.xml(writer);
        for (self.annotations) |arg| try arg.xml(writer);
        try writer.writeAll("  </interface>\n");
    }
};
pub const Method = struct {
    name: []const u8,
    args: []const Arg,
    annotations: []const Annotation = &.{},
    pub fn xml(self: Method, writer: anytype) !void {
        try writer.print("    <method name=\"{s}\">\n", .{self.name});
        for (self.args) |arg| try arg.xml(writer);
        for (self.annotations) |arg| try arg.xml(writer);
        return writer.writeAll("    </method>\n");
    }
};
pub const Property = struct {
    name: []const u8,
    type: []const u8,
    access: Access,
    annotations: []const Annotation = &.{},
    pub const Access = enum { read, write, readwrite };
    pub fn xml(self: Property, writer: anytype) !void {
        if (self.annotations.len == 0) try writer.print("    <property name=\"{s}\" type=\"{s}\" access=\"{s}\"/>\n", .{ self.name, self.type, @tagName(self.access) }) else {
            try writer.print("    <property name=\"{s}\" type=\"{s}\" access=\"{s}\">\n", .{ self.name, self.type, @tagName(self.access) });
            for (self.annotations) |arg| try arg.xml(writer);
            try writer.writeAll("    </property>\n");
        }
    }
};
pub const Signal = struct {
    name: []const u8,
    args: []const Arg,
    annotations: []const Annotation = &.{},
    pub fn xml(self: Signal, writer: anytype) !void {
        try writer.print("    <signal name=\"{s}\">\n", .{self.name});
        for (self.args) |arg| try arg.xml(writer);
        for (self.annotations) |arg| try arg.xml(writer);
        try writer.writeAll("    </signal>\n");
    }
};
pub const Arg = struct {
    name: ?[]const u8 = null,
    type: []const u8,
    direction: ?Direction = null,
    annotations: []const Annotation = &.{},
    pub const Direction = enum { in, out };
    pub fn xml(self: Arg, writer: anytype) !void {
        try writer.print("      <arg type=\"{s}\"", .{self.type});
        if (self.name) |name| try writer.print(" name=\"{s}\"", .{name});
        if (self.direction) |direction| try writer.print(" direction=\"{s}\"", .{@tagName(direction)});
        if (self.annotations.len == 0) try writer.writeAll("/>\n") else {
            try writer.writeAll(">\n");
            for (self.annotations) |arg| try arg.xml(writer);
            try writer.writeAll("      </arg>\n");
        }
    }
};
pub const Annotation = struct {
    name: []const u8,
    value: []const u8,
    pub fn xml(self: Annotation, writer: anytype) !void {
        try writer.print("      <annotation name=\"{s}\" value=\"{s}\" />\n", .{ self.name, self.value });
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
pub inline fn fromType(ObjectType: type) []const u8 {
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

const IntrospectionTags = enum { node, interface, method, signal, property, arg, annotation };

pub fn parse(buffer: []const u8, skip_default_interfaces: bool, allocator: std.mem.Allocator) !Node {
    var parser = Parser.init(buffer);
    while (parser.next()) |event| {
        switch (event) {
            .open_tag => |name| {
                if (std.mem.eql(u8, name, "node")) {
                    // heavy lifting
                    return parseNode(&parser, skip_default_interfaces, allocator);
                } else log.err("unexpected xml tag {s}", .{name});
                return error.InvalidXML;
            },
            .comment => |comment| {
                _ = comment;
                // log.debug("Comment {s}", .{comment});
            },
            .processing_instruction => |pi| {
                _ = pi;
                // log.debug("Processing Instruction {s}", .{pi});
            },
            .type_declaration => |declaration| {
                _ = declaration;
                // log.debug("dtd: {s}", .{declaration});
            },
            else => {
                log.err("unexpected xml token {}", .{event});
                return error.InvalidXML;
            },
        }
    }
    log.err("Unable to parse xml", .{});
    return error.InvalidXML;
}

/// parse a node, should be called just after the start of a node
pub fn parseNode(parser: *Parser, skip_default_interfaces: bool, allocator: std.mem.Allocator) !Node {
    var children = std.ArrayList(Node).init(allocator);
    var interfaces = std.ArrayList(Interface).init(allocator);
    var object_path: []const u8 = "";
    while (parser.next()) |event| switch (event) {
        .attribute => |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                object_path = attr.raw_value;
            } else {
                log.warn("Unknown attribute {s}={s}", .{ attr.name, attr.raw_value });
            }
        },
        .open_tag => |name| {
            if (std.meta.stringToEnum(IntrospectionTags, name)) |tag| switch (tag) {
                .interface => if (try parseInterface(parser, skip_default_interfaces, allocator)) |interface|
                    try interfaces.append(interface),
                .node => try children.append(try parseNode(parser, skip_default_interfaces, allocator)),
                else => {},
            };
        },
        .close_tag => |name| {
            if (!std.mem.eql(u8, name, "node")) return error.InvalidXML;
            return Node{
                .name = object_path,
                .interfaces = try interfaces.toOwnedSlice(),
                .children = try children.toOwnedSlice(),
            };
        },
        else => {
            log.err("unexpected xml token {}", .{event});
            return error.InvalidXML;
        },
    };
    return error.InvalidXML;
}
/// parse and discard xml until closing tag is reached
fn skipTillClosing(parser: *Parser, tag_name: []const u8) !void {
    while (parser.next()) |event| switch (event) {
        .close_tag => |name| {
            if (std.mem.eql(u8, name, tag_name)) return;
        },
        else => {},
    };
    return error.InvalidXML;
}

/// parse an interface, should be called just after the start of a interface
pub fn parseInterface(parser: *Parser, skip_default_interfaces: bool, allocator: std.mem.Allocator) !?Interface {
    var methods = std.ArrayList(Method).init(allocator);
    var signals = std.ArrayList(Signal).init(allocator);
    var properties = std.ArrayList(Property).init(allocator);
    var interface_name: []const u8 = "";
    while (parser.next()) |event| switch (event) {
        .attribute => |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                if (skip_default_interfaces) {
                    if (std.mem.eql(u8, attr.raw_value, "org.freedesktop.DBus.Properties") or
                        std.mem.eql(u8, attr.raw_value, "org.freedesktop.DBus.Introspectable") or
                        std.mem.eql(u8, attr.raw_value, "org.freedesktop.DBus.Peer"))
                    {
                        try skipTillClosing(parser, "interface");
                        return null;
                    }
                }
                interface_name = attr.raw_value;
            } else {
                log.warn("Unknown attribute {s}={s}", .{ attr.name, attr.raw_value });
            }
        },
        .open_tag => |name| {
            if (std.meta.stringToEnum(IntrospectionTags, name)) |tag| switch (tag) {
                .method => try methods.append(try parseMember(parser, Method, allocator)),
                .signal => try signals.append(try parseMember(parser, Signal, allocator)),
                .property => try properties.append(try parseProperty(parser, allocator)),
                else => {
                    log.err("unexpected tag type {s}", .{name});
                    return error.InvalidXML;
                },
            };
        },
        .close_tag => |name| {
            if (!std.mem.eql(u8, name, "interface")) return error.InvalidXML;
            return Interface{
                .name = interface_name,
                .methods = try methods.toOwnedSlice(),
                .signals = try signals.toOwnedSlice(),
                .properties = try properties.toOwnedSlice(),
            };
        },
        .comment => {},
        else => {
            log.err("unexpected xml token {}", .{event});
            return error.InvalidXML;
        },
    };
    return error.InvalidXML;
}
/// parse a member, should be called just after the start of a member(method, signal, property)
pub fn parseMember(parser: *Parser, T: type, allocator: std.mem.Allocator) !T {
    var member_name: []const u8 = "";
    var args = std.ArrayList(Arg).init(allocator);
    while (parser.next()) |event| switch (event) {
        .open_tag => |name| {
            if (std.mem.eql(u8, name, "arg")) {
                try args.append(try parseArg(parser, allocator));
            } else {
                log.err("unexpected tag {s}", .{name});
            }
        },
        .attribute => |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                member_name = attr.raw_value;
            } else {
                log.warn("Unknown attribute {s}={s}", .{ attr.name, attr.raw_value });
            }
        },
        .close_tag => |name| {
            // if (!std.mem.eql(u8, name, "method")) return error.InvalidXML;
            const expected_tag_name = if (T == Method)
                "method"
            else if (T == Signal)
                "signal"
            else if (T == Property)
                "property"
            else
                @compileError("Invalid Member type " ++ @typeName(T));
            if (!mem.eql(u8, name, expected_tag_name)) {
                log.err("unexpected closing tag: {s}", .{name});
                return error.InvalidXML;
            }
            return T{ .name = member_name, .args = try args.toOwnedSlice() };
        },
        .comment => {},
        else => {
            log.err("unexpected tag {}", .{event});
            return error.InvalidXML;
        },
    };
    return error.InvalidXML;
}
/// parse a arg, should be called just after the start of a arg
pub fn parseProperty(parser: *Parser, allocator: std.mem.Allocator) !Property {
    var property_name: []const u8 = "";
    var property_type: []const u8 = "";
    var property_access = Property.Access.read;
    var annotations = std.ArrayList(Annotation).init(allocator);
    while (parser.next()) |event| switch (event) {
        .attribute => |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                property_name = attr.raw_value;
            } else if (std.mem.eql(u8, attr.name, "type")) {
                property_type = attr.raw_value;
            } else if (std.mem.eql(u8, attr.name, "access")) {
                property_access = std.meta.stringToEnum(Property.Access, attr.raw_value) orelse {
                    log.err("unexpected access type {s}", .{attr.raw_value});
                    return error.InvalidXML;
                };
            } else {
                log.warn("Unknown attribute {s}={s}", .{ attr.name, attr.raw_value });
            }
        },
        .close_tag => |name| {
            if (!std.mem.eql(u8, name, "property")) return error.InvalidXML;
            return .{
                .name = property_name,
                .type = property_type,
                .access = property_access,
                .annotations = try annotations.toOwnedSlice(),
            };
        },
        .open_tag => |name| {
            if (std.mem.eql(u8, name, "annotation")) try annotations.append(try parseAnnotation(parser)) else {
                log.err("unexpected tag {s}", .{name});
                return error.InvalidXML;
            }
        },
        .comment => {},
        else => {
            log.err("unexpected tag {}", .{event});
            return error.InvalidXML;
        },
    };
    return error.InvalidXML;
}
/// parse a arg, should be called just after the start of a arg
pub fn parseArg(parser: *Parser, allocator: std.mem.Allocator) !Arg {
    var arg_name: []const u8 = "";
    var arg_type: []const u8 = "";
    var arg_direction = Arg.Direction.in;
    var annotations = std.ArrayList(Annotation).init(allocator);
    while (parser.next()) |event| switch (event) {
        .attribute => |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                arg_name = attr.raw_value;
            } else if (std.mem.eql(u8, attr.name, "type")) {
                arg_type = attr.raw_value;
            } else if (std.mem.eql(u8, attr.name, "direction")) {
                arg_direction = std.meta.stringToEnum(Arg.Direction, attr.raw_value) orelse {
                    log.err("unexpected direction {s}", .{attr.raw_value});
                    return error.InvalidXML;
                };
            } else {
                log.warn("Unknown attribute {s}={s}", .{ attr.name, attr.raw_value });
            }
        },
        .close_tag => |name| {
            if (!std.mem.eql(u8, name, "arg")) return error.InvalidXML;
            return .{
                .name = arg_name,
                .type = arg_type,
                .direction = arg_direction,
                .annotations = try annotations.toOwnedSlice(),
            };
        },
        .comment => {},
        else => {
            log.err("unexpected tag {}", .{event});
            return error.InvalidXML;
        },
    };
    return error.InvalidXML;
}
/// parse a annotation, should be called just after the start of a annotation
pub fn parseAnnotation(parser: *Parser) !Annotation {
    var annotation_name: []const u8 = "";
    var annotation_value: []const u8 = "";
    while (parser.next()) |event| switch (event) {
        .attribute => |attr| {
            if (std.mem.eql(u8, attr.name, "name")) {
                annotation_name = attr.raw_value;
            } else if (std.mem.eql(u8, attr.name, "value")) {
                annotation_value = attr.raw_value;
            } else {
                log.warn("Unknown attribute {s}={s}", .{ attr.name, attr.raw_value });
            }
        },
        .close_tag => |name| {
            if (std.mem.eql(u8, name, "annotation")) return .{
                .name = annotation_name,
                .value = annotation_value,
            };
            log.err("unexpected closing tag {s}", .{name});
            return error.InvalidXML;
        },
        .comment => {},
        else => {
            log.err("unexpected tag {}", .{event});
            return error.InvalidXML;
        },
    };
    return error.InvalidXML;
}
pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena_allocator.allocator();
    defer _ = arena_allocator.reset(.free_all); // potentially make more efficient?
    var args = std.process.args();
    _ = args.next();
    const cwd = std.fs.cwd();
    var bw = std.io.bufferedWriter(std.io.getStdOut().writer());
    defer bw.flush() catch {};
    const stdout = bw.writer();
    while (args.next()) |arg| {
        const file = cwd.openFile(arg, .{}) catch {
            log.err("unable to open: {s}", .{arg});
            continue;
        };
        defer file.close();
        const buf = try file.readToEndAlloc(allocator, 0x1000000);
        const node = try parse(buf, allocator);
        log.debug("{}", .{node});
        try node.xml(stdout, .{ .include_default_interfaces = false });
    }
}
// pub const PullParser = struct {
//     state: State = .normal,
//     text: []const u8,
//     pub const State = enum { normal };
//     pub const Entity = union(enum) {
//     };
//     pub fn parse(self: *PullParser, text: []const u8) void {
//         _ = self;
//         for (text) |char| {
//             switch (char) {
//                 '<' => {},
//                 else => {
//                 },
//             }
//         }
//         // const reader = self.reader;
//         // reader.read;
//     }
//     pub fn next(self: *PullParser)?Node{}
// };
// // pub const Node = struct {
// //     name: []const u8,
// //     attributes: [][]const u8,
// //     children: []const Node = &.{},
// // };

// pub fn main() !void {
//     var args = std.process.args();
//     _ = args.next();
//     const cwd = std.fs.cwd();
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     var parser = PullParser{};
//     while (args.next()) |arg| {
//         const file = try cwd.openFile(arg, .{});
//         defer file.close();
//         const buf = try file.readToEndAlloc(allocator, 0x1000000);
//         parser.parse(buf);
//     }
// }
