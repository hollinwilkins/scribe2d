const std = @import("std");
const scriobh = @import("scriobh");
const zstbi = @import("zstbi");
const text = scriobh.text;
const draw = scriobh.draw;
const core = scriobh.core;

pub fn main() !void {
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

    std.debug.print("Font Info: {s}\n", .{font_file});
    var rt_iter = face.unmanaged.raw_tables.table_records.iterator();
    while (rt_iter.next()) |table| {
        std.debug.print("Table: {s}\n", .{table.tag.toBytes()});
    }

    var glyph_paths = draw.Paths.init(allocator);
    defer glyph_paths.deinit();
    var builder = draw.PathBuilder.create(&glyph_paths);

    // const glyph_id = face.unmanaged.tables.cmap.?.subtables.getGlyphIndex(codepoint).?;
    _ = try face.outline(glyph_id, @floatFromInt(size), text.GlyphPen.Debug.Instance);
    const bounds = try face.outline(glyph_id, @floatFromInt(size), builder.glyphPen());
    _ = bounds;

    std.debug.print("\n", .{});
    std.debug.print("Curves:\n", .{});
    std.debug.print("-----------------------------\n", .{});
    const path = glyph_paths.getPathRecords()[0];
    const subpath_records = glyph_paths.getSubpathRecords()[path.subpath_offsets.start..path.subpath_offsets.end];
    for (subpath_records, 0..) |subpath_record, subpath_index| {
        const curve_records = glyph_paths.getCurveRecords()[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
        for (curve_records, 0..) |curve_record, curve_index| {
            const curve = glyph_paths.getCurve(curve_record);
            std.debug.print("Curve({},{}): {}\n", .{ subpath_index, curve_index, curve });
        }
    }
    std.debug.print("-----------------------------\n", .{});

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

    var line_soup = try draw.LineSoup.initScene(allocator, scene);
    defer line_soup.deinit();

    // const dimensions = core.DimensionsU32{
    //     .width = size * 3,
    //     .height = size,
    // };

    // var half_planes = try draw.HalfPlanesU16.init(allocator);
    // defer half_planes.deinit();

    // const rasterizer = draw.LineSoupRasterizer.create(&half_planes);

    // zstbi.init(allocator);
    // defer zstbi.deinit();

    // var image = try zstbi.Image.createEmpty(
    //     dimensions.width,
    //     dimensions.height,
    //     3,
    //     .{},
    // );
    // defer image.deinit();

    // var texture = draw.TextureUnmanaged{
    //     .dimensions = dimensions,
    //     .format = draw.TextureFormat.SrgbU8,
    //     .bytes = image.data,
    // };

    // std.debug.print("\n============== Boundary Texture\n\n", .{});
    // texture.clear(draw.Color{
    //     .r = 1.0,
    //     .g = 1.0,
    //     .b = 1.0,
    //     .a = 1.0,
    // });

    // var flat_data = try draw.PathFlattener.flattenAlloc(
    //     allocator,
    //     scene.getMetadatas(),
    //     scene.paths,
    //     scene.getStyles(),
    //     scene.getTransforms(),
    // );
    // defer flat_data.deinit();

    // var pen = draw.SoupPen.init(allocator, &rasterizer);
    // try pen.draw(flat_data.fill_lines, scene.metadata.items, &texture);

    // for (0..texture.dimensions.height) |y| {
    //     std.debug.print("{:0>4}: ", .{y});
    //     for (0..texture.dimensions.height) |x| {
    //         const pixel = texture.getPixelUnsafe(core.PointU32{
    //             .x = @intCast(x),
    //             .y = @intCast(y),
    //         });

    //         if (pixel.r < 1.0) {
    //             std.debug.print("#", .{});
    //         } else {
    //             std.debug.print(";", .{});
    //         }
    //     }

    //     std.debug.print("\n", .{});
    // }

    // std.debug.print("==============\n", .{});

    // try image.writeToFile("/tmp/output.png", .png);
}
