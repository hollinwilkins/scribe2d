const std = @import("std");
const xml = @import("./xml/mod.zig");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = core.RectF32;

pub const Svg = struct {
    viewbox: RectF32,

    pub fn parseFileAlloc(allocator: Allocator, path: []const u8) !Svg {
        const absolute_path = try std.fs.realpathAlloc(allocator, path);
        defer allocator.free(absolute_path);

        var file = try std.fs.openFileAbsolute(absolute_path, std.fs.File.OpenFlags{});
        defer file.close();

        var doc = try xml.parse(allocator, path, file.reader());
        defer doc.deinit();

        doc.acquire();
        defer doc.release();

        std.debug.print("Parsed document: {s}...\n", .{doc.root.tag_name.slice()});
        std.debug.print("Parsed viewport: {s}...\n", .{doc.root.attr("viewBox").?});

        return Svg{
            .viewbox = RectF32{},
        };
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }
};
