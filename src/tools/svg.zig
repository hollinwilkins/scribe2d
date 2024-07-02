const std = @import("std");
const scribe = @import("scribe");
const svg = scribe.svg;

pub fn main() !void {
    var args = std.process.args();

    _ = args.skip();
    const svg_file = args.next() orelse @panic("need to provide a font file");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var image = try svg.Svg.parseFileAlloc(
        allocator,
        svg_file,
    );
    defer image.deinit();

    std.debug.print("Hello, World!\n", .{});
}
