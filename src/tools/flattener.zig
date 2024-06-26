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
    _ = try face.outline(glyph_id, @floatFromInt(size), text.GlyphPen.Debug.Instance);
    const bounds = try face.outline(glyph_id, @floatFromInt(size), builder.glyphPen());
    _ = bounds;

    for (glyph_paths.path_records.items, 0..) |path_record, path_index| {
        std.debug.print("=========== Path({}) =========\n", .{path_index});
        const subpath_records = glyph_paths.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
        for (subpath_records, 0..) |subpath_record, subpath_index| {
            std.debug.print("=========== Subath({}) =========\n", .{subpath_index});
            const curve_records = glyph_paths.curve_records.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
            for (curve_records, 0..) |curve_record, curve_record_index| {
                const points = glyph_paths.points.items[curve_record.point_offsets.start..curve_record.point_offsets.end];
                std.debug.print("CurveRecord({}, {any})\n", .{curve_record_index, points});
            }
            std.debug.print("=========== End Subath({}) =========\n", .{subpath_index});
        }
        std.debug.print("=========== End Path({}) =========\n", .{path_index});
    }

    var scene = try draw.Scene.init(allocator);
    defer scene.deinit();

    const style = try scene.pushStyle();
    style.fill = draw.Style.Fill{
        .color = draw.Color{
            .r = 1.0,
            .g = 0.0,
            .b = 0.0,
            .a = 1.0,
        },
    };
    try scene.paths.copyPath(glyph_paths, 0);
    try scene.close();

    var encoding = try draw.LineSoupEstimator.estimateSceneAlloc(allocator, scene);
    defer encoding.deinit();

    // var flat_data = try draw.PathFlattener.flattenAlloc(
    //     allocator,
    //     scene.getMetadatas(),
    //     scene.paths,
    //     scene.getStyles(),
    //     scene.getTransforms(),
    // );
    // defer flat_data.deinit();

    // std.debug.print("===================\n", .{});
    // std.debug.print("Lines:\n", .{});
    // for (flat_data.fill_lines.getItems()) |line| {
    //     std.debug.print("{}\n", .{ line });
    // }
    // std.debug.print("===================\n", .{});

    // var half_planes = try draw.HalfPlanesU16.init(allocator);
    // defer half_planes.deinit();

    // var soup_rasterizer = draw.LineSoupRasterizer.create(&half_planes);
    // var raster_data = try soup_rasterizer.rasterizeAlloc(allocator, flat_data.fill_lines);
    // defer raster_data.deinit();
}
