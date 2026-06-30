const std = @import("std");
const log = std.log;
const testing = std.testing;
const Parser = @import("desktop_entry_parser.zig").Parser;
pub const CachedIconFinder = struct {
    finder: IconFinder,
    cache: std.StringHashMapUnmanaged(?[:0]const u8) = .{},
    pub fn init(allocator: std.mem.Allocator, default_theme: []const u8) !CachedIconFinder {
        return .{ .finder = try IconFinder.init(allocator, default_theme) };
    }
    pub fn deinit(self: *CachedIconFinder) void {
        self.clearAndFree();
        self.finder.deinit();
    }
    pub fn clear(self: *CachedIconFinder) void {
        var iter = self.cache.iterator();
        const allocator = self.finder.allocator;
        while (iter.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            if (kv.value_ptr.*) |val| allocator.free(val);
        }
        self.cache.clearRetainingCapacity();
    }
    pub fn clearAndFree(self: *CachedIconFinder) void {
        self.clear();
        self.cache.clearAndFree(self.finder.allocator);
    }
    pub fn find(self: *CachedIconFinder, icon_name: [:0]const u8, size: u16, scale: u16) !?[:0]const u8 {
        if (self.cache.get(icon_name)) |path| return path;

        const allocator = self.finder.allocator;
        var buf: [4096]u8 = undefined;
        const path = if (try self.finder.find(&buf, icon_name, size, scale)) |icon| try allocator.dupeZ(u8, icon) else null;
        try self.cache.put(allocator, try allocator.dupe(u8, icon_name), path);
        return path;
    }
};

pub const IconFinder = struct {
    default_theme: []const u8,
    themes: Themes,
    allocator: std.mem.Allocator,
    pub const Themes = std.StringHashMap(Theme);
    // cache: std.StringHashMap([:0]const u8),
    pub fn init(allocator: std.mem.Allocator, default_theme: []const u8) !IconFinder {
        return IconFinder{
            .allocator = allocator,
            .themes = try enumerateThemes(allocator),
            .default_theme = default_theme,
        };
    }
    pub fn enumerateThemes(allocator: std.mem.Allocator) !Themes {
        var themes = Themes.init(allocator);
        errdefer themes.deinit();
        var basedir_iter = BasedirIter{};
        while (basedir_iter.next()) |basedir_path| {
            if (std.fs.openDirAbsoluteZ(basedir_path, .{ .iterate = true })) |_basedir| {
                var basedir = _basedir;
                defer basedir.close();
                var iter = basedir.iterate();
                while (try iter.next()) |entry| {
                    // entry.kind;
                    if (!themes.contains(entry.name) and entry.kind == .directory) {
                        try themes.put(try allocator.dupe(u8, entry.name), undefined);
                    }
                }
            } else |err| log.debug("unable to open icon basedir {s}: {}", .{ basedir_path, err });
        }
        var iter = themes.iterator();
        while (iter.next()) |kv| {
            kv.value_ptr.init(kv.key_ptr.*, allocator) catch |err| switch (err) {
                error.InvalidTheme => {
                    allocator.free(kv.key_ptr.*);
                    themes.removeByPtr(kv.key_ptr);
                },
                else => {
                    log.err("Error on {s}", .{kv.key_ptr.*});
                    return err;
                },
            };
        }
        return themes;
    }
    pub fn deinit(self: *IconFinder) void {
        const allocator = self.allocator;
        var iter = self.themes.iterator();
        while (iter.next()) |kv| {
            allocator.free(kv.key_ptr.*);
            kv.value_ptr.deinit();
        }
        self.themes.deinit();
    }
    /// main function, writes icon path to buffer
    pub fn find(self: IconFinder, buf: []u8, icon_name: [:0]const u8, size: u16, scale: u16) !?[:0]u8 {
        const themes = self.themes;
        if (try self.findThemeInheritance(self.default_theme, buf, icon_name, size, scale)) |icon| {
            return icon;
        } else if (self.themes.get("hicolor")) |theme| {
            if (try theme.findIcon(buf, icon_name, size, scale)) |icon| {
                return icon;
            }
        } else {
            var iter = themes.valueIterator();
            while (iter.next()) |theme| {
                if (!std.mem.eql(u8, theme.name, self.default_theme) and !std.mem.eql(u8, theme.name, "hicolor")) {
                    if (try theme.findIcon(buf, icon_name, size, scale)) |icon| {
                        return icon;
                    }
                }
            }
        }
        return null;
    }
    fn findThemeInheritance(self: IconFinder, theme_name: []const u8, buf: []u8, icon_name: [:0]const u8, size: u16, scale: u16) !?[:0]u8 {
        const theme = self.themes.get(theme_name) orelse return null;
        if (try theme.findIcon(buf, icon_name, size, scale)) |icon| {
            return icon;
        } else {
            // inheritance
            for (theme.inherits) |parent| {
                if (try self.findThemeInheritance(parent, buf, icon_name, size, scale)) |icon| {
                    return icon;
                }
            }
        }
        return null;
    }
};

pub const Extension = enum {
    png,
    svg,
    xpm,
    pub inline fn str(self: Extension) [:0]const u8 {
        return switch (self) {
            .png => ".png",
            .svg => ".svg",
            .xpm => ".xpm",
        };
    }
    pub fn fromPath(path: [:0]const u8) ?Extension {
        return std.meta.stringToEnum(Extension, path[path.len - 3 ..]);
    }
};
test "extension from path check" {
    try testing.expectEqual(.svg, Extension.fromPath("/foo/bar/a.svg"));
    try testing.expectEqual(.png, Extension.fromPath("/foo/bar/a.png"));
    try testing.expectEqual(null, Extension.fromPath("/foo/bar/a.jpeg"));
}
pub const Theme = struct {
    /// internal name
    directory: []const u8,
    /// user readable name in theme, not directory name
    name: [:0]const u8 = "",
    comment: [:0]const u8 = "",
    inherits: [][]const u8 = &.{},
    basedirs: [][]const u8 = &.{},
    subdirs: []Directory = &.{},
    hidden: bool = false,
    example: ?[:0]const u8 = null,
    allocator: std.mem.Allocator,

    const extensions: []const Extension = &.{ .png, .svg, .xpm };
    /// TODO
    pub fn init(self: *Theme, directory: []const u8, allocator: std.mem.Allocator) !void {
        self.* = .{ .directory = directory, .allocator = allocator };
        errdefer self.deinit();
        const index_theme = "/index.theme";
        var basedirs = std.ArrayList([]const u8).init(allocator);
        var iter = BasedirIter{};
        const buf = &iter.buf;
        while (iter.next()) |basedir| {
            buf[basedir.len + directory.len] = 0;
            const dirpath = buf[0 .. basedir.len + directory.len :0];
            @memcpy(dirpath[basedir.len..], directory);
            if (std.fs.accessAbsoluteZ(dirpath, .{})) {
                try basedirs.append(try allocator.dupe(u8, basedir));
                if (self.name.len == 0) {
                    @memcpy(buf[dirpath.len .. dirpath.len + index_theme.len + 1], index_theme.ptr[0 .. index_theme.len + 1]);
                    self.parseThemeDescription(buf[0 .. dirpath.len + index_theme.len :0], allocator) catch |err| switch (err) {
                        error.FileNotFound => {},
                        else => return err,
                    };
                }
            } else |err| switch (err) {
                error.FileNotFound => {},
                error.PermissionDenied => log.warn("no read permissions for {s}", .{buf}),
                else => return err,
            }
        }
        self.basedirs = try basedirs.toOwnedSlice();
        if (self.name.len == 0) return error.InvalidTheme;
    }

    pub fn parseThemeDescription(self: *Theme, index_theme_file: [:0]const u8, allocator: std.mem.Allocator) !void {
        const file = try std.fs.openFileAbsoluteZ(index_theme_file, .{});
        defer file.close();
        var br = std.io.bufferedReader(file.reader());
        const reader = br.reader();
        var directories = std.ArrayList(Directory).init(allocator);
        var current_directory: ?Directory = null;
        var subdirs = std.StringHashMap(void).init(allocator);
        defer subdirs.deinit();
        var parser = Parser(@TypeOf(reader), 32768){ .reader = reader, .include_comments = false };
        {
            const n = try parser.next() orelse return error.InvalidFile;
            if (n != .group) return error.InvalidFile;
            if (!std.mem.eql(u8, n.group, "Icon Theme")) return error.InvalidFile;
        }
        while (try parser.next()) |line| switch (line) {
            .entry => |entry| {
                if (std.mem.eql(u8, entry.key, "Name")) {
                    self.name = try allocator.dupeZ(u8, entry.value);
                } else if (std.mem.eql(u8, entry.key, "Comment")) {
                    self.comment = try allocator.dupeZ(u8, entry.value);
                } else if (std.mem.eql(u8, entry.key, "Inherits")) {
                    var inherits = std.ArrayList([]const u8).init(allocator);
                    var iter = std.mem.splitScalar(u8, entry.value, ',');
                    while (iter.next()) |parent|
                        try inherits.append(try allocator.dupe(u8, parent));
                    self.inherits = try inherits.toOwnedSlice();
                } else if (std.mem.eql(u8, entry.key, "Directories") or std.mem.eql(u8, entry.key, "ScaledDirectories")) {
                    var iter = std.mem.splitScalar(u8, entry.value, ',');
                    while (iter.next()) |dir|
                        if (dir.len != 0) try subdirs.put(try allocator.dupe(u8, dir), {});
                } else if (std.mem.eql(u8, entry.key, "Hidden")) {
                    self.hidden = try entry.as(bool);
                }
            },
            .group => |name| {
                current_directory = if (subdirs.fetchRemove(name)) |kv| .{ .path = kv.key } else null;
                break;
            },
            else => unreachable,
        };

        // parse sub-directories
        while (try parser.next()) |line| switch (line) {
            .entry => |entry| {
                if (current_directory) |*dir| {
                    if (std.mem.eql(u8, entry.key, "Size")) {
                        dir.size = try entry.as(u16);
                    } else if (std.mem.eql(u8, entry.key, "Scale")) {
                        dir.scale = try entry.as(u16);
                    } else if (std.mem.eql(u8, entry.key, "Context")) {
                        dir.context = try allocator.dupe(u8, entry.value);
                    } else if (std.mem.eql(u8, entry.key, "Type")) {
                        dir.size_type = std.meta.stringToEnum(Directory.SizeType, entry.value) orelse return error.InvalidFile;
                    } else if (std.mem.eql(u8, entry.key, "MaxSize")) {
                        dir.max_size = try entry.as(u16);
                    } else if (std.mem.eql(u8, entry.key, "MinSize")) {
                        dir.min_size = try entry.as(u16);
                    }
                }
            },
            .group => |name| {
                if (current_directory) |*dir| {
                    if (dir.max_size == std.math.maxInt(u16)) dir.max_size = dir.size;
                    if (dir.min_size == 0) dir.min_size = dir.size;
                    try directories.append(dir.*);
                }
                current_directory = if (subdirs.fetchRemove(name)) |kv| .{ .path = kv.key } else null;
            },
            else => unreachable,
        };
        if (current_directory) |*dir| {
            if (dir.max_size == std.math.maxInt(u16)) dir.max_size = dir.size;
            if (dir.min_size == 0) dir.min_size = dir.size;
            try directories.append(dir.*);
        }
        if (subdirs.count() != 0) {
            log.warn("{s} directories does not match list in index.theme {}", .{ self.name, subdirs.count() });
            var iter = subdirs.keyIterator();
            while (iter.next()) |key| {
                log.warn("directory {s} is missing", .{key.*});
            }
        }
        self.subdirs = try directories.toOwnedSlice();
    }
    pub fn deinit(self: Theme) void {
        const allocator = self.allocator;
        if (self.name.len != 0) allocator.free(self.name);
        if (self.comment.len != 0) allocator.free(self.comment);
        for (self.inherits) |parent| allocator.free(parent);
        allocator.free(self.inherits);
        for (self.basedirs) |basedir| allocator.free(basedir);
        allocator.free(self.basedirs);
        for (self.subdirs) |subdir| {
            allocator.free(subdir.path);
            allocator.free(subdir.context);
        }
        allocator.free(self.subdirs);
        if (self.example) |example| allocator.free(example);
    }

    /// main function, writes icon path to buffer
    pub fn findIcon(self: Theme, buf: []u8, icon_name: [:0]const u8, size: u16, scale: u16) !?[:0]u8 {
        for (self.basedirs) |basedir| {
            const dir_len = basedir.len + self.directory.len + 1;
            if (buf.len < dir_len) return error.NoSpaceLeft;
            @memcpy(buf[0..basedir.len], basedir);
            @memcpy(buf[basedir.len .. dir_len - 1], self.directory);
            buf[dir_len - 1] = '/';
            for (self.subdirs) |subdir| {
                if (subdir.matchesSize(size, scale)) {
                    const subdir_len = dir_len + subdir.path.len + 1 + icon_name.len;
                    if (buf.len < subdir_len) return error.NoSpaceLeft;
                    @memcpy(buf[dir_len .. dir_len + subdir.path.len], subdir.path);
                    buf[dir_len + subdir.path.len] = '/';
                    @memcpy(buf[dir_len + subdir.path.len + 1 .. subdir_len], icon_name);
                    for (extensions) |ext| {
                        const extension = ext.str();
                        if (buf.len < subdir_len + extension.len + 1) return error.NoSpaceLeft;
                        @memcpy(buf[subdir_len .. subdir_len + extension.len + 1], extension.ptr[0 .. extension.len + 1]);
                        // check file exists
                        const path = buf[0 .. subdir_len + extension.len :0];
                        // log.debug("{s}", .{path});
                        if (std.fs.accessAbsoluteZ(path, .{})) {
                            return path;
                        } else |err| switch (err) {
                            error.FileNotFound => {},
                            error.PermissionDenied => log.warn("no read permissions for {s}", .{buf}),
                            else => return err,
                        }
                    }
                }
            }
        }
        return null;
    }
};
pub const Directory = struct {
    path: []const u8,
    size: u16 = undefined,
    scale: u16 = 1,
    context: []const u8 = "",
    size_type: SizeType = .Threshold,
    max_size: u16 = std.math.maxInt(u16),
    min_size: u16 = 0,
    threshold: u16 = 2,
    const SizeType = enum { Threshold, Fixed, Scalable };
    pub fn matchesSize(dir: Directory, size: u16, scale: u16) bool {
        if (scale != dir.scale) return false;
        return switch (dir.size_type) {
            .Threshold => @abs(@as(i32, dir.size) - size) <= dir.threshold,
            .Fixed => dir.size == size,
            .Scalable => dir.min_size <= size and size <= dir.max_size,
        };
    }
};

pub const BasedirIter = struct {
    buf: [std.posix.PATH_MAX]u8 = undefined,
    state: union(enum) { home_icons, data_dirs: std.mem.SplitIterator(u8, .scalar), pixmaps } = .home_icons,
    pub fn next(self: *BasedirIter) ?[:0]const u8 {
        const buf = &self.buf;
        switch (self.state) {
            .home_icons => {
                const data_dirs = std.posix.getenv("XDG_DATA_DIRS") orelse "";
                self.state = .{ .data_dirs = std.mem.splitScalar(u8, data_dirs, ':') };

                const home = std.posix.getenv("HOME") orelse "";
                @memcpy(buf[0..home.len], home);
                const icons = "/.icons/";
                @memcpy(buf[home.len .. home.len + icons.len + 1], icons.ptr[0 .. icons.len + 1]);
                return buf[0 .. home.len + icons.len :0];
            },
            .data_dirs => |*iter| {
                if (iter.next()) |dir| {
                    const icons = "/icons/";
                    @memcpy(buf[0..dir.len], dir);
                    @memcpy(buf[dir.len .. dir.len + icons.len + 1], icons[0 .. icons.len + 1]);
                    return buf[0 .. dir.len + icons.len :0];
                } else {
                    const pixmaps = "/usr/share/pixmaps/";
                    @memcpy(buf[0 .. pixmaps.len + 1], pixmaps.ptr[0 .. pixmaps.len + 1]);
                    self.state = .pixmaps;
                    return buf[0..pixmaps.len :0];
                }
            },
            .pixmaps => {
                return null;
            },
        }
    }
};
