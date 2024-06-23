const std = @import("std");
const scriobh = @import("scriobh");
const zstbi = @import("zstbi");
const text = scriobh.text;
const draw = scriobh.draw;
const core = scriobh.core;

pub fn main() !void {
    std.debug.print("Hello, world!\n", .{});

    var args = std.process.args();

    _ = args.skip();
    const font_file = args.next() orelse @panic("need to provide a font file");
    const codepoint_str = args.next() orelse @panic("need to provide a codepoint string");
    // const codepoint: u32 = @intCast(codepoint_str[0]);
    const glyph_id: u16 = try std.fmt.parseInt(u16, codepoint_str, 10);
    const size_str = args.next() orelse "16";
    const size = try std.fmt.parseInt(u32, size_str, 10);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var face = try text.Face.initFile(allocator, font_file);
    defer face.deinit();

    var glyph_paths = draw.Paths.init(allocator);
    defer glyph_paths.deinit();
    var builder = draw.PathBuilder.create(&glyph_paths);
    const bounds = try face.outline(glyph_id, @floatFromInt(size), builder.glyphPen());
    _ = bounds;

    var scene = try draw.Scene.init(allocator);
    defer scene.deinit();

    try scene.paths.copyPath(glyph_paths, 0);
    const style = try scene.pushStyle();
    style.fill = draw.Style.Fill{
        .color = draw.Color{
            .r = 1.0,
            .g = 0.0,
            .b = 0.0,
            .a = 1.0,
        },
    };

    var flat_data = try draw.PathFlattener.flattenAlloc(
        allocator,
        scene.getMetadatas(),
        scene.paths,
        scene.getStyles(),
        scene.getTransforms(),
    );
    defer flat_data.deinit();

    std.debug.print("===================\n", .{});
    std.debug.print("Lines:\n", .{});
    for (flat_data.fill_lines.getLines()) |line| {
        std.debug.print("{}\n", .{ line });
    }
    std.debug.print("===================\n", .{});
}
