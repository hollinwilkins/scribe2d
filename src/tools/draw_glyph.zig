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
    const output_file = args.next() orelse @panic("need to provide output file");

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
    // _ = try face.outline(glyph_id, @floatFromInt(size), text.GlyphPen.Debug.Instance);
    const bounds = try face.outline(glyph_id, @floatFromInt(size), builder.glyphPen());
    _ = bounds;

    var scene = try draw.Scene.init(allocator);
    defer scene.deinit();

    const style = try scene.pushStyle();
    style.stroke = draw.Style.Stroke{
        .color = draw.Color.BLACK,
        .width = 4.0,
    };
    style.fill = draw.Style.Fill{
        .color = draw.Color.RED,
    };
    try scene.paths.copyPath(glyph_paths, 0);
    try scene.close();

    var soup = try draw.PathFlattener.flattenSceneAlloc(allocator, scene);
    defer soup.deinit();

    // soup.path_records.items = soup.path_records.items[2..3];
    // soup.path_records.items[0].subpath_offsets.start += 1;

    const dimensions = core.DimensionsU32{
        .width = size,
        .height = size,
    };

    var half_planes = try draw.HalfPlanesU16.init(allocator);
    defer half_planes.deinit();

    {
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
    }
    {
        std.debug.print("\n", .{});
        std.debug.print("Line Soup:\n", .{});
        std.debug.print("-----------------------------\n", .{});
        var line_count: usize = 0;
        for (soup.path_records.items, 0..) |path_record, path_index| {
            std.debug.print("-- Path({}) --\n", .{path_index});

            const subpath_records = soup.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
            for (subpath_records, 0..) |subpath_record, subpath_index| {
                std.debug.print("-- Subpath({}) --\n", .{subpath_index});
                const curve_records = soup.curve_records.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
                for (curve_records) |curve_record| {
                    const lines = soup.items.items[curve_record.item_offsets.start..curve_record.item_offsets.end];
                    for (lines) |*line| {
                        std.debug.print("{}: {}\n", .{ line_count, line });
                        line_count += 1;

                        const offset = 16.0;
                        line.start.x += offset;
                        line.start.y += offset;
                        line.end.x += offset;
                        line.end.y += offset;
                    }
                }
            }
        }
        std.debug.print("-----------------------------\n", .{});
    }
    const rasterizer = draw.LineSoupRasterizer.create(&half_planes);

    zstbi.init(allocator);
    defer zstbi.deinit();

    var image = try zstbi.Image.createEmpty(
        dimensions.width,
        dimensions.height,
        3,
        .{},
    );
    defer image.deinit();

    var texture = draw.TextureUnmanaged{
        .dimensions = dimensions,
        .format = draw.TextureFormat.SrgbU8,
        .bytes = image.data,
    };
    texture.clear(draw.Color{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
        .a = 1.0,
    });

    var pen = draw.SoupPen.init(allocator, &rasterizer);
    try pen.draw(
        &soup,
        &texture,
    );

    {
        std.debug.print("\n", .{});
        std.debug.print("Paths Summary:\n", .{});
        for (soup.path_records.items) |path_record| {
            const subpath_count = path_record.subpath_offsets.size();
            const boundary_fragment_count = path_record.boundary_offsets.size();
            const merge_fragment_count = path_record.merge_offsets.size();
            const span_count = path_record.span_offsets.size();

            std.debug.print("-----------------------------\n", .{});
            std.debug.print("Subpaths({}), BoundaryFragments({}), MergeFragments({}), Spans({})\n", .{
                subpath_count,
                boundary_fragment_count,
                merge_fragment_count,
                span_count,
            });
            std.debug.print("SubpathOffsets({},{}), BoundaryFragmentOffsets({},{}), MergeFragmentOffsets({},{}), SpanOffsets({},{})\n", .{
                path_record.subpath_offsets.start,
                path_record.subpath_offsets.end,
                path_record.boundary_offsets.start,
                path_record.boundary_offsets.end,
                path_record.merge_offsets.start,
                path_record.merge_offsets.end,
                path_record.span_offsets.start,
                path_record.span_offsets.end,
            });

            const subpath_records = soup.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
            for (subpath_records) |subpath_record| {
                const intersection_count = subpath_record.intersection_offsets.size();
                std.debug.print("Intersections({}), IntersectionOffsets({},{})\n", .{
                    intersection_count,
                    subpath_record.intersection_offsets.start,
                    subpath_record.intersection_offsets.end,
                });
            }
        }
        std.debug.print("-----------------------------\n", .{});
    }

    {
        std.debug.print("\n", .{});
        std.debug.print("Grid Intersections:\n", .{});
        std.debug.print("-----------------------------\n", .{});
        for (soup.grid_intersections.items) |grid_intersection| {
            std.debug.print("({},{}): T({}), ({},{})\n", .{
                grid_intersection.pixel.x,
                grid_intersection.pixel.y,
                grid_intersection.intersection.t,
                grid_intersection.intersection.point.x,
                grid_intersection.intersection.point.y,
            });
        }
        std.debug.print("-----------------------------\n", .{});
    }

    {
        std.debug.print("\n", .{});
        std.debug.print("Boundary Fragments:\n", .{});
        std.debug.print("-----------------------------\n", .{});
        for (soup.boundary_fragments.items) |boundary_fragment| {
            std.debug.print("({},{}): ({},{}), ({},{})\n", .{
                boundary_fragment.pixel.x,
                boundary_fragment.pixel.y,
                boundary_fragment.intersections[0].point.x,
                boundary_fragment.intersections[0].point.y,
                boundary_fragment.intersections[1].point.x,
                boundary_fragment.intersections[1].point.y,
            });
        }
        std.debug.print("-----------------------------\n", .{});
    }

    {
        std.debug.print("\n============== Boundary Texture\n\n", .{});
        for (0..texture.dimensions.height) |y| {
            std.debug.print("{:0>4}: ", .{y});
            for (0..texture.dimensions.height) |x| {
                const pixel = texture.getPixelUnsafe(core.PointU32{
                    .x = @intCast(x),
                    .y = @intCast(y),
                });

                if (pixel.r < 1.0) {
                    std.debug.print("#", .{});
                } else {
                    std.debug.print(";", .{});
                }
            }

            std.debug.print("\n", .{});
        }

        std.debug.print("==============\n", .{});
    }
    try image.writeToFile(output_file, .png);
}
