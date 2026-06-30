const std = @import("std");
const log = std.log;
pub const cairo = @import("cairo.zig");
pub const c = @cImport({
    @cInclude("librsvg/rsvg.h");
});

pub const Handle = opaque {
    pub extern fn rsvg_handle_render_document(handle: *Handle, cr: *cairo.Context, viewport: *const Rectangle, @"error": ?*?*GError) bool;
    pub const renderDocument = rsvg_handle_render_document;

    pub extern fn g_object_unref(handle: *Handle) void;
    pub const unref = g_object_unref;

    pub extern fn rsvg_handle_new_from_gfile_sync(file: *GFile, flags: Flags, cancellable: ?*GCancellable, @"error": ?*?*GError) ?*Handle;
    pub const newFromGfileSync = rsvg_handle_new_from_gfile_sync;

    pub extern fn rsvg_handle_new_from_file(filename: [*:0]const u8, @"error": ?*?*GError) ?*Handle;
    pub const newFromFile = rsvg_handle_new_from_file;

    pub extern fn rsvg_handle_set_dpi(handle: *Handle, f64) void;
    pub const setDpi = rsvg_handle_set_dpi;

    pub const Flags = struct {
        // 0
        pub const NONE = c.RSVG_HANDLE_FLAGS_NONE;
        // 1 << 0
        pub const UNLIMITED = c.RSVG_HANDLE_FLAG_UNLIMITED;
        // 1 << 1
        pub const KEEP_IMAGE_DATA = c.RSVG_HANDLE_FLAG_KEEP_IMAGE_DATA;
    };
};
pub const Rectangle = struct {
    x: f64 = 0,
    y: f64 = 0,
    width: f64,
    height: f64,
};

pub const GFile = opaque {
    pub extern fn g_file_new_for_path(path: [*:0]const u8) *GFile;
    pub const newForPath = g_file_new_for_path;

    pub extern fn g_object_unref(object: *GFile) void;
    pub const unref = g_object_unref;
};
pub const GCancellable = opaque {};
pub const GError = extern struct {
    domain: u32, // gquark
    code: i32,
    message: [*:0]const u8,

    pub extern fn g_error_free(@"error": *GError) void;
    pub const free = g_error_free;
};
/// helper function which reads from a file and then writes to a cairo context
pub fn renderFile(cr: *const cairo.Context, path: [*:0]const u8, viewport: *const Rectangle) !void {
    var gerr: ?*GError = null;
    const handle = Handle.newFromFile(path, &gerr) orelse {
        log.err("could not open {s}: {s}", .{ path, gerr.?.message });
        gerr.free();
        return error.FileNotFound;
    };
    defer handle.unref();
    handle.setDpi(96.0);
    if (!handle.renderDocument(cr, viewport, &gerr)) {
        log.err("could not render: {s}", .{gerr.?.message});
        gerr.free();
        return error.CouldNotRender;
    }
}
