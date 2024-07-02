const std = @import("std");
const xml = @import("./xml/mod.zig");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = core.RectF32;

pub const Svg = struct {
    viewbox: RectF32,

    pub fn parseFileAlloc(allocator: Allocator, path: []const u8) !Svg {
        const absolute_path = std.fs.realpathAlloc(allocator, path);
        defer allocator.free(absolute_path);

        var file = try std.fs.openFileAbsolute(absolute_path, std.fs.File.OpenFlags{});
        defer file.close();

        var doc = try xml.parse(allocator, path, file.reader());
        defer doc.deinit();

        std.debug.print("Parsed document...\n", .{});
    }
};
