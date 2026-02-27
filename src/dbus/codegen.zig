//! creates zig code from dbus introspection
const std = @import("std");
const log = std.log;
const mem = std.mem;
const assert = std.debug.assert;
const dbus = @import("dbus.zig");
const introspection = @import("introspection.zig");

// pub var std_options = .{
//     .log_level = .err,
// };
pub const client_header = @embedFile("./client_header.zig");
pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena_allocator.allocator();
    defer _ = arena_allocator.reset(.free_all);
    const options = try Options.parseArgs(allocator);
    const cwd = std.fs.cwd();

    for (options.pairs) |pair| {
        const output_file = if (pair.output_filename) |filename|
            cwd.createFile(filename, .{}) catch {
                log.err("unable to open: {s}", .{filename});
                return error.FileNotFound;
            }
        else
            std.io.getStdOut();
        defer output_file.close();
        var bw = std.io.bufferedWriter(output_file.writer());
        defer bw.flush() catch unreachable;
        const output = bw.writer();

        const input_file = if (pair.input_filename) |filename|
            cwd.openFile(filename, .{}) catch {
                log.err("unable to open: {s}", .{filename});
                return error.FileNotFound;
            }
        else
            std.io.getStdIn();
        defer input_file.close();

        const buf = try input_file.readToEndAlloc(allocator, 0x1000000);
        defer allocator.free(buf);
        const node = try introspection.parse(buf, true, allocator);
        if (options.server) {
            try writeExampleServer(node, output);
        } else {
            try writeProxy(node, output);
        }
    }
    // log.debug("{}", .{node});
    if (options.root) |root_filename| {
        const root_file = cwd.createFile(root_filename, .{}) catch {
            log.err("unable to open: {s}", .{root_filename});
            return error.FileNotFound;
        };
        defer root_file.close();
        var bw = std.io.bufferedWriter(root_file.writer());
        defer bw.flush() catch unreachable;
        const writer = bw.writer();
        for (options.pairs) |pair| {
            const type_name = blk: {
                const start = if (mem.lastIndexOfScalar(u8, pair.output_filename.?, '/')) |i| i + 1 else 0;
                const end = mem.lastIndexOf(u8, pair.output_filename.?, ".zig") orelse pair.output_filename.?.len;
                break :blk pair.output_filename.?[start..end];
            };
            const start = if (mem.lastIndexOfScalar(u8, pair.output_filename.?, '/')) |i| i + 1 else 0;
            try writer.print("pub const @\"{s}\" = @import(\"{s}\");\n", .{ type_name, pair.output_filename.?[start..] });
        }
    }
}

pub fn writeProxy(node: introspection.Node, output: anytype) !void {
    try output.writeAll(client_header);
    // interface fields
    for (node.interfaces) |interface| {
        var field_name_buf: [300]u8 = undefined;
        const interface_field_name = interfaceFieldName(interface.name, &field_name_buf);
        var type_name_buf: [300]u8 = undefined;
        const interface_type_name = interfaceTypeName(interface_field_name, &type_name_buf);
        try output.print("{s}: {s} = .{{}},\n", .{ interface_field_name, interface_type_name });
    }
    // interface field types
    for (node.interfaces) |interface| {
        // var field_name_buf: [300]u8 = undefined;
        var field_name_buf: [300]u8 = undefined;
        const interface_field_name = interfaceFieldName(interface.name, &field_name_buf);
        var type_name_buf: [300]u8 = undefined;
        const interface_type_name = interfaceTypeName(interface_field_name, &type_name_buf);

        try output.print("pub const {s} = struct {{\n", .{interface_type_name});
        try output.print("    pub const interface = \"{s}\";\n", .{interface.name});

        if (interface.signals.len > 0) {
            // handlers
            try output.print(
                \\    signal_handler: ?*const fn (*{0s}, *dbus.Message, *anyopaque) dbus.HandlerResult = null,
                \\    data: *anyopaque = undefined,
                \\
                \\    pub fn setSignalHandler(self: *{0s}, data: anytype, handler: fn (*{0s}, Signal, @TypeOf(data)) void) void {{
                \\        self.signal_handler = generateSignalHander(handler);
                \\        self.data = @ptrCast(data);
                \\    }}
                \\
            , .{interface_type_name});
            try output.writeAll("    pub const Signal = union(enum) {\n");
            for (interface.signals) |signal| {
                try output.print("        {s}: struct{{", .{signal.name});
                // try writeZigTypeFromDbusSig(output, signal.args);
                for (signal.args, 0..) |arg, i| {
                    if (arg.direction == .in) {
                        try printArg(output, arg, i);
                        if (i != signal.args.len - 1) try output.writeAll(", ");
                    }
                }
                try output.writeAll("},\n");
            }
            try output.writeAll("        PropertiesChanged: PropertiesChangedArgs,\n");
            try output.writeAll("    };\n");
        }

        for (interface.methods) |method| {
            try output.print(
                \\    pub fn {s}(self: *{s}, args: {0s}Args) !dbus.MethodPendingCall({0s}ReturnArgs) {{
                \\        return methodCallGeneric(self, "{s}", "{0s}", args, {0s}ReturnArgs);
                \\    }}
                \\
            , .{ method.name, interface_type_name, interface_field_name });
            try output.print("    pub const {s}Args = struct {{\n", .{method.name});
            for (method.args, 0..) |arg, i| {
                if (arg.direction == .in) {
                    try output.writeAll("        ");
                    try printArg(output, arg, i);
                    try output.writeAll(",\n");
                }
            }
            try output.writeAll("    };\n");

            try output.print("    pub const {s}ReturnArgs = struct {{\n", .{method.name});
            for (method.args, 0..) |arg, i| {
                if (arg.direction == .out) {
                    try output.writeAll("        ");
                    try printArg(output, arg, i);
                    try output.writeAll(",\n");
                }
            }
            try output.writeAll("    };\n");
        }

        for (interface.properties) |property| {
            const property_type = ZigTypePrinter{ .s = property.type };
            if (property.access == .read or property.access == .readwrite) {
                try output.print(
                    \\    pub fn get{s}(self: *{s}) !dbus.GetPropertyPendingCall({}) {{
                    \\        return getPropertyGeneric(self, "{s}", "{0s}", {2});
                    \\    }}
                    \\
                , .{ property.name, interface_type_name, property_type, interface_field_name });
            }
            if (property.access == .write or property.access == .readwrite) {
                try output.print(
                    \\    pub fn set{s}(self: *{s}, value: {}) !void {{
                    \\        try setPropertyGeneric(self, "{s}", "{0s}", value);
                    \\    }}
                    \\
                , .{ property.name, interface_type_name, property_type, interface_field_name });
                try writeZigTypeFromDbusSig(output, property.type);
            }
        }

        try output.writeAll("    pub const Properties = struct {\n");
        for (interface.properties) |property| {
            // getall properties
            const property_type = ZigTypePrinter{ .s = property.type };
            if (property.access == .read or property.access == .readwrite) {
                try output.print(
                    \\        {s}: {s},
                    \\
                , .{ property.name, property_type });
            }
        }
        try output.writeAll("    };\n");
        try output.print(
            \\    pub fn getAll(self: *{s}) !dbus.GetAllPendingCall(Properties) {{
            \\        return getAllGeneric(self, "{s}", Properties);
            \\    }}
            \\
        , .{ interface_type_name, interface_field_name });

        try output.writeAll("};\n");
    }
}
pub fn writeExampleServer(node: introspection.Node, output: anytype) !void {
    try output.print(
        \\const dbus = @import("dbus");
        \\const Self = @This();
        \\pub const path = "{s}";
        \\connection: *dbus.Connection = undefined,
        \\
    , .{node.name});

    // interface fields
    for (node.interfaces) |interface| {
        var field_name_buf: [300]u8 = undefined;
        const interface_field_name = interfaceFieldName(interface.name, &field_name_buf);
        var type_name_buf: [300]u8 = undefined;
        const interface_type_name = interfaceTypeName(interface_field_name, &type_name_buf);
        try output.print("{s}: {s} = .{{}},\n", .{ interface_field_name, interface_type_name });
    }
    // interface field types
    for (node.interfaces) |interface| {
        // var field_name_buf: [300]u8 = undefined;
        var field_name_buf: [300]u8 = undefined;
        const interface_field_name = interfaceFieldName(interface.name, &field_name_buf);
        var type_name_buf: [300]u8 = undefined;
        const interface_type_name = interfaceTypeName(interface_field_name, &type_name_buf);

        try output.print("pub const {s} = struct {{\n", .{interface_type_name});
        try output.print("    pub const interface = \"{s}\";\n", .{interface.name});

        for (interface.methods) |method| {
            try output.print(
                \\    pub fn method{s}(self: *{s}, args: {0s}Args) {0s}ReturnArgs {{}}
                \\
            , .{ method.name, interface_type_name });
            try output.print("    pub const {s}Args = struct {{\n", .{method.name});
            for (method.args, 0..) |arg, i| {
                if (arg.direction == .in) {
                    try output.writeAll("        ");
                    try printArg(output, arg, i);
                    try output.writeAll(",\n");
                }
            }
            try output.writeAll("    };\n");
            try output.print("    pub const {s}ReturnArgs = struct {{\n", .{method.name});
            for (method.args, 0..) |arg, i| {
                if (arg.direction == .out) {
                    try output.writeAll("        ");
                    try printArg(output, arg, i);
                    try output.writeAll(",\n");
                }
            }
            try output.writeAll("    };\n");
        }

        for (interface.signals) |signal| {
            try output.print("    pub const signal{s} = dbus.generateSignalFunction(Self, {s}, {0s}, {0s}Args);\n", .{ signal.name, interface_type_name });
            // try writeZigTypeFromDbusSig(output, signal.args);
            try output.print("    pub const {s}Args = struct{{", .{signal.name});
            for (signal.args, 0..) |arg, i| {
                try printArg(output, arg, i);
                if (i != signal.args.len - 1) try output.writeAll(", ");
            }
            try output.writeAll("};\n");
        }

        try output.print("    pub const signalPropertiesChanged = dbus.generatePropertiesChangedFunction(Self, \"{s}\");\n", .{interface_type_name});

        for (interface.properties) |property| {
            const property_type = ZigTypePrinter{ .s = property.type };
            if (property.access == .read or property.access == .readwrite) {
                try output.print(
                    \\    pub fn getProperty{s}(self: *{s}) {} {{}}
                    \\
                , .{ property.name, interface_type_name, property_type });
            }
            if (property.access == .write or property.access == .readwrite) {
                try output.print(
                    \\    pub fn setProperty{s}(self: *{s}, value: {}) void {{}}
                    \\
                , .{ property.name, interface_type_name, property_type });
            }
        }

        try output.writeAll("};\n");
    }
}

/// command line option parsing
pub const Options = struct {
    allocator: std.mem.Allocator,
    pairs: []Pair,
    root: ?[:0]const u8 = null,
    server: bool = false,
    pub const Pair = struct {
        input_filename: ?[:0]const u8 = null,
        output_filename: ?[:0]const u8 = null,
        pub fn addInput(self: *Pair, filename: [:0]const u8) ?Pair {
            defer self.input_filename = filename;
            if (self.input_filename != null) {
                defer self.output_filename = null;
                return self.*;
            }
            return null;
        }
        pub fn addOutput(self: *Pair, filename: [:0]const u8) ?Pair {
            defer self.output_filename = filename;
            if (self.output_filename != null) {
                defer self.input_filename = null;
                return self.*;
            }
            return null;
        }
        pub fn isNull(self: Pair) bool {
            return self.input_filename == null and self.output_filename == null;
        }
    };
    pub fn deinit(self: Options) void {
        self.allocator.free(self.pairs);
    }
    pub fn checkValidity(self: Options) !void {
        const Set = std.StringHashMap(void);
        var inputs = Set.init(self.allocator);
        defer inputs.deinit();
        var outputs = Set.init(self.allocator);
        defer outputs.deinit();
        var stdin_used = false;
        var stdout_used = false;
        for (self.pairs) |pair| {
            // log.info("{?s} => {?s}", .{ pair.input_filename, pair.output_filename });
            if (pair.input_filename) |filename| {
                if (inputs.contains(filename)) {
                    log.err("input file {s} specified more than once", .{filename});
                    return error.Invalid;
                }
                try inputs.put(filename, {});
            } else {
                if (stdin_used) {
                    log.err("stdin specified more than once", .{});
                    return error.Invalid;
                }
                stdin_used = true;
            }
            if (pair.output_filename) |filename| {
                if (outputs.contains(filename)) {
                    log.err("output file {s} specified more than once", .{filename});
                    return error.Invalid;
                }
                try outputs.put(filename, {});
            } else {
                if (stdout_used) {
                    log.err("stdout specified more than once", .{});
                    return error.Invalid;
                }
                stdout_used = true;
            }
        }
    }
    pub fn parseArgs(allocator: mem.Allocator) !Options {
        var list = std.ArrayList(Pair).init(allocator);
        var pair = Pair{};
        var opts = Options{
            .allocator = allocator,
            .pairs = undefined,
            .root = null,
        };

        var args = std.process.args();
        const executable = args.next().?;

        const input_long = "--input=";
        const output_long = "--output=";
        const root_long = "--root=";
        while (args.next()) |arg| {
            if (mem.eql(u8, arg, "-i")) {
                if (pair.addInput(args.next().?)) |_pair| try list.append(_pair);
            } else if (argLongMatch(arg, input_long)) {
                if (pair.addInput(arg[input_long.len..])) |_pair| try list.append(_pair);
            } else if (mem.eql(u8, arg, "-o")) {
                if (pair.addOutput(args.next().?)) |_pair| try list.append(_pair);
            } else if (argLongMatch(arg, output_long)) {
                if (pair.addOutput(arg[output_long.len..])) |_pair| try list.append(_pair);
            } else if (mem.eql(u8, arg, "-r")) {
                if (pair.addOutput(args.next().?)) |_pair| try list.append(_pair);
            } else if (argLongMatch(arg, root_long)) {
                opts.root = arg[root_long.len..];
            } else if (mem.eql(u8, arg, "-s") or mem.eql(u8, arg, "--server")) {
                opts.server = true;
            } else if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                exitHelp(executable, 0);
            } else {
                if (pair.addInput(arg)) |_pair| try list.append(_pair);
            }
        }
        if (!pair.isNull()) try list.append(pair);
        const pairs = try list.toOwnedSlice();
        opts.pairs = pairs;

        try opts.checkValidity();
        return opts;
    }
    pub inline fn argLongMatch(arg: [:0]const u8, prefix: [:0]const u8) bool {
        return arg.len >= prefix.len and mem.eql(u8, arg[0..prefix.len], prefix);
    }
};
fn exitHelp(executable: [:0]const u8, exit_status: u8) void {
    std.io.getStdOut().writer().print(
        \\usage:
        \\ {0s} OPTIONS...
        \\
        \\ Generate zig client code from an xml file for a dbus object.
        \\ If specified, the root file will contain declarations to generated proxies
        \\ with names as the base filename without the ".zig" extensions
        \\options:
        \\ -h, --help                 print help
        \\ -i, --input=<filename>     specify input file, default to stdin
        \\ -o, --output=<filename>    specify output file, default to stdout
        \\ -r, --root=<filename>      specify file for root of module
        \\ -s, --server               generate skeleton server files instead of proxies
        \\example:
        \\ {0s} -i notify.xml -o notify.zig ...
        \\ {0s} -r rootfile.zig -i notify.xml -o notify.zig ...
        \\
    , .{executable}) catch unreachable;
    std.process.exit(exit_status);
}

/// print zig type for a signature
pub fn writeZigTypeFromDbusSig(writer: anytype, sig: []const u8) !void {
    const remaining = try writeZigTypeFromDbusSigWithRemaining(writer, sig);
    if (remaining.len != 0) return error.InvalidSignature;
}
fn writeZigTypeFromDbusSigWithRemaining(writer: anytype, sig: []const u8) ![]const u8 {
    if (sig.len == 0) return error.InvalidSignature;
    switch (sig[0]) {
        'y' => try writer.writeAll("u8"),
        'b' => try writer.writeAll("bool"),
        'n' => try writer.writeAll("i16"),
        'q' => try writer.writeAll("u16"),
        'i' => try writer.writeAll("i32"),
        'u' => try writer.writeAll("u32"),
        'x' => try writer.writeAll("i64"),
        't' => try writer.writeAll("u64"),
        'd' => try writer.writeAll("f64"),
        's' => try writer.writeAll("[*:0]const u8"),
        'o' => try writer.writeAll("dbus.Arg.ObjectPath"),
        'g' => try writer.writeAll("dbus.Arg.Signature"),
        'h' => try writer.writeAll("dbus.Arg.Unixfd"),
        'a' => {
            try writer.writeAll("[]const ");
            return writeZigTypeFromDbusSigWithRemaining(writer, sig[1..]);
        },
        'v' => {
            try writer.writeAll("dbus.Arg");
        },
        '{' => {
            try writer.writeAll("dbus.DictEntry(");
            const second_arg_sig = try writeZigTypeFromDbusSigWithRemaining(writer, sig[1..]);
            try writer.writeAll(", ");
            const after_second_arg_sig = try writeZigTypeFromDbusSigWithRemaining(writer, second_arg_sig);
            try writer.writeAll(")");
            if (after_second_arg_sig.len == 0) return error.InvalidSignature;
            if (after_second_arg_sig[0] != '}') return error.InvalidSignature;
            return after_second_arg_sig[1..];
        },
        '(' => {
            try writer.writeAll("struct {");
            var remaining = sig[1..];
            while (remaining[0] != ')') : (try writer.writeAll(", ")) {
                remaining = try writeZigTypeFromDbusSigWithRemaining(writer, remaining);
            }
            try writer.writeAll("}");
            // skip end of struct
            return remaining[1..];
        },
        // dict_entry = 'e',
        else => {
            log.err("unexpected character {c}", .{sig[0]});
            return error.InvalidSignature;
        },
    }
    return sig[1..];
}
pub const ZigTypePrinter = struct {
    s: []const u8,
    pub fn format(self: ZigTypePrinter, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writeZigTypeFromDbusSig(writer, self.s);
    }
};

pub fn printArg(writer: anytype, arg: introspection.Arg, arg_num: anytype) !void {
    const type_printer = ZigTypePrinter{ .s = arg.type };
    if (arg.name) |arg_name| {
        try writer.print("{s}: {}", .{ arg_name, type_printer });
    } else try writer.print("arg{}: {}", .{ arg_num, type_printer });
}

pub fn interfaceFieldName(interface_name: []const u8, buf: []u8) [:0]const u8 {
    const interface_last_field = interface_name[(mem.lastIndexOfScalar(u8, interface_name, '.') orelse std.math.maxInt(usize)) +% 1 ..];
    std.mem.copyForwards(u8, buf, interface_last_field);
    buf[0] = std.ascii.toLower(buf[0]);
    return @ptrCast(buf[0..interface_last_field.len]);
}
pub fn interfaceTypeName(interface_field_name: []const u8, buf: []u8) [:0]const u8 {
    const trailer = "Interface";
    std.mem.copyForwards(u8, buf, interface_field_name);
    buf[0] = std.ascii.toUpper(buf[0]);
    std.mem.copyForwards(u8, buf[interface_field_name.len..], trailer);
    buf[interface_field_name.len + trailer.len] = 0;
    return @ptrCast(buf[0 .. interface_field_name.len + trailer.len]);
}
