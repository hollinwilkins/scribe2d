const std = @import("std");
const scribe = @import("scribe");
const zstbi = @import("zstbi");
const text = scribe.text;
const draw = scribe.draw;
const core = scribe.core;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();

    _ = args.skip();
    const font_file = args.next() orelse @panic("need to provide a font file");
    const codepoint_str = args.next() orelse @panic("need to provide a codepoint string");
    // const codepoint: u32 = @intCast(codepoint_str[0]);
    const glyph_id: u16 = try std.fmt.parseInt(u16, codepoint_str, 10);
    const size_str = args.next() orelse "16";
    const size = try std.fmt.parseInt(u32, size_str, 10);
    const output_file = args.next() orelse @panic("need to provide output file");

    var face = try text.Face.initFile(allocator, font_file);
    defer face.deinit();

    std.debug.print("Font Info: {s}\n", .{font_file});
    var rt_iter = face.unmanaged.raw_tables.table.iterator();
    while (rt_iter.next()) |table| {
        std.debug.print("Table: {s}\n", .{table.tag.toBytes()});
    }

    var encoder = draw.Encoder.init(allocator);
    defer encoder.deinit();

    _ = output_file;

    try encoder.encodeColor(draw.ColorU8{
        .r = 255,
        .g = 255,
        .b = 0,
        .a = 255,
    });
    var style = draw.Style{};
    style.setFill(draw.Style.Fill{
        .brush = .color,
    });
    // style.setStroke(draw.Style.Stroke{
    //     .join = .bevel,
    // });
    try encoder.encodeStyle(style);

    var path_encoder = encoder.pathEncoder(f32);

    _ = try face.outline(glyph_id, @floatFromInt(size), text.GlyphPen.Debug.Instance);
    _ = try face.outline(glyph_id, @floatFromInt(size), path_encoder.glyphPen());

    var half_planes = try draw.HalfPlanesU16.init(allocator);
    defer half_planes.deinit();

    const encoding = encoder.encode();
    const rasterizer_config = draw.CpuRasterizer.Config{
        .run_flags = draw.CpuRasterizer.Config.RUN_FLAG_FLATTEN,
    };
    var rasterizer = try draw.CpuRasterizer.init(
        allocator,
        &half_planes,
        rasterizer_config,
        encoding,
    );
    defer rasterizer.deinit();

    var texture = try draw.Texture.init(allocator, core.DimensionsU32{
        .width = 50,
        .height = 50,
    }, draw.TextureFormat.RgbaU8);
    defer texture.deinit();
    texture.clear(draw.Colors.WHITE);

    try rasterizer.rasterize(&texture);

    rasterizer.debugPrint(texture);

    // var args = std.process.args();

    // _ = args.skip();
    // const font_file = args.next() orelse @panic("need to provide a font file");
    // const codepoint_str = args.next() orelse @panic("need to provide a codepoint string");
    // // const codepoint: u32 = @intCast(codepoint_str[0]);
    // const glyph_id: u16 = try std.fmt.parseInt(u16, codepoint_str, 10);
    // const size_str = args.next() orelse "16";
    // const size = try std.fmt.parseInt(u32, size_str, 10);
    // const output_file = args.next() orelse @panic("need to provide output file");

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    // var face = try text.Face.initFile(allocator, font_file);
    // defer face.deinit();

    // std.debug.print("Font Info: {s}\n", .{font_file});
    // var rt_iter = face.unmanaged.raw_tables.table.iterator();
    // while (rt_iter.next()) |table| {
    //     std.debug.print("Table: {s}\n", .{table.tag.toBytes()});
    // }

    // var glyph_paths = draw.Shape.init(allocator);
    // defer glyph_paths.deinit();
    // var builder = draw.ShapeBuilder.create(&glyph_paths);

    // // const glyph_id = face.unmanaged.tables.cmap.?.subtables.getGlyphIndex(codepoint).?;
    // // _ = try face.outline(glyph_id, @floatFromInt(size), text.GlyphPen.Debug.Instance);
    // _ = try face.outline(glyph_id, @floatFromInt(size), builder.glyphPen());

    // const outline_width: f32 = 2.0;
    // var scene = try draw.Scene.init(allocator);
    // defer scene.deinit();
    // const style = try scene.pushStyle();
    // style.stroke = draw.Style.Stroke{
    //     .color = draw.Color.BLACK,
    //     .width = outline_width,
    //     .join = .round,
    // };
    // style.fill = draw.Style.Fill{
    //     .color = draw.Color.BLUE,
    // };

    // try scene.shape.copyPath(glyph_paths, 0);
    // try scene.close();

    // // rotate and scale the glyph
    // {
    //     const transform = (core.TransformF32{
    //         .scale = core.PointF32{
    //             .x = 1.0,
    //             .y = 1.0,
    //         },
    //         .rotate = 0.0,
    //     });
    //     scene.shape.transformMatrixInPlace(transform.toMatrix());
    // }

    // const dimensions = core.DimensionsU32{
    //     .width = @intFromFloat(@ceil(scene.shape.bounds.getWidth() + outline_width / 2.0 + 16.0)),
    //     .height = @intFromFloat(@ceil(scene.shape.bounds.getHeight() + outline_width / 2.0 + 16.0)),
    // };

    // // translate the glyph
    // {
    //     const transform = (core.TransformF32{
    //         .translate = core.PointF32{
    //             .x = @floatFromInt(dimensions.width / 2),
    //             .y = @floatFromInt(dimensions.height / 2),
    //         },
    //     });
    //     scene.shape.transformMatrixInPlace(transform.toMatrix());
    // }

    // var soup = try draw.PathFlattener.flattenSceneAlloc(allocator, draw.KernelConfig.DEFAULT, scene);
    // defer soup.deinit();

    // // soup.path.items = soup.path.items[2..3];
    // // soup.path.items[0].subpath_offsets.start += 1;

    // var half_planes = try draw.HalfPlanesU16.init(allocator);
    // defer half_planes.deinit();

    // {
    //     std.debug.print("\n", .{});
    //     std.debug.print("Curves:\n", .{});
    //     std.debug.print("-----------------------------\n", .{});
    //     const path = glyph_paths.paths.items[0];
    //     const subpaths = glyph_paths.subpaths.items[path.subpath_offsets.start..path.subpath_offsets.end];
    //     for (subpaths, 0..) |subpath, subpath_index| {
    //         const curves = glyph_paths.curves.items[subpath.curve_offsets.start..subpath.curve_offsets.end];
    //         for (curves, 0..) |curve, curve_index| {
    //             const points = glyph_paths.points.items[curve.point_offsets.start..curve.point_offsets.end];
    //             std.debug.print("Curve({},{},{}): {any}\n", .{
    //                 subpath_index,
    //                 curve_index,
    //                 curve.kind,
    //                 points,
    //             });
    //         }
    //     }
    //     std.debug.print("-----------------------------\n", .{});
    // }

    // {
    //     std.debug.print("\n", .{});
    //     std.debug.print("Line Soup:\n", .{});
    //     std.debug.print("-----------------------------\n", .{});
    //     var line_count: usize = 0;
    //     for (soup.flat_paths.items, 0..) |path, path_index| {
    //         std.debug.print("-- Path({}) --\n", .{path_index});

    //         const subpaths = soup.flat_subpaths.items[path.flat_subpath_offsets.start..path.flat_subpath_offsets.end];
    //         for (subpaths, 0..) |subpath, subpath_index| {
    //             std.debug.print("-- Subpath({}) --\n", .{subpath_index});
    //             const curves = soup.flat_curves.items[subpath.flat_curve_offsets.start..subpath.flat_curve_offsets.end];
    //             for (curves) |curve| {
    //                 const lines = soup.lines.items[curve.item_offsets.start..curve.item_offsets.end];
    //                 for (lines) |*line| {
    //                     std.debug.print("{}: {}\n", .{ line_count, line });
    //                     line_count += 1;

    //                     // const offset = 16.0;
    //                     // line.start.x += offset;
    //                     // line.start.y += offset;
    //                     // line.end.x += offset;
    //                     // line.end.y += offset;
    //                 }
    //             }
    //         }
    //     }
    //     std.debug.print("-----------------------------\n", .{});
    // }
    // const rasterizer = draw.Rasterizer.create(&half_planes);

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
    // texture.clear(draw.Color{
    //     .r = 1.0,
    //     .g = 1.0,
    //     .b = 1.0,
    //     .a = 1.0,
    // });

    // var pen = draw.SoupPen.init(allocator, &rasterizer);
    // try pen.draw(
    //     &soup,
    //     &texture,
    // );

    // {
    //     std.debug.print("\n", .{});
    //     std.debug.print("Shape Summary:\n", .{});
    //     for (soup.path.items) |path| {
    //         const subpath_count = path.subpath_offsets.size();
    //         const boundary_fragment_count = path.boundary_offsets.size();
    //         const merge_fragment_count = path.merge_offsets.size();
    //         const span_count = path.span_offsets.size();

    //         std.debug.print("-----------------------------\n", .{});
    //         std.debug.print("Subpaths({}), BoundaryFragments({}), MergeFragments({}), Spans({})\n", .{
    //             subpath_count,
    //             boundary_fragment_count,
    //             merge_fragment_count,
    //             span_count,
    //         });
    //         std.debug.print("SubpathOffsets({},{}), BoundaryFragmentOffsets({},{}), MergeFragmentOffsets({},{}), SpanOffsets({},{})\n", .{
    //             path.subpath_offsets.start,
    //             path.subpath_offsets.end,
    //             path.boundary_offsets.start,
    //             path.boundary_offsets.end,
    //             path.merge_offsets.start,
    //             path.merge_offsets.end,
    //             path.span_offsets.start,
    //             path.span_offsets.end,
    //         });

    //         // const subpath = soup.subpath.items[path.subpath_offsets.start..path.subpath_offsets.end];
    //         // for (subpath) |subpath| {
    //         //     const intersection_count = subpath.intersection_offsets.size();
    //         //     std.debug.print("Intersections({}), IntersectionOffsets({},{})\n", .{
    //         //         intersection_count,
    //         //         subpath.intersection_offsets.start,
    //         //         subpath.intersection_offsets.end,
    //         //     });
    //         // }
    //     }
    //     std.debug.print("-----------------------------\n", .{});
    // }

    // {
    //     std.debug.print("\n", .{});
    //     std.debug.print("Grid Intersections:\n", .{});
    //     std.debug.print("-----------------------------\n", .{});
    //     for (soup.grid_intersections.items) |grid_intersection| {
    //         std.debug.print("({},{}): T({}), ({},{})\n", .{
    //             grid_intersection.pixel.x,
    //             grid_intersection.pixel.y,
    //             grid_intersection.intersection.t,
    //             grid_intersection.intersection.point.x,
    //             grid_intersection.intersection.point.y,
    //         });
    //     }
    //     std.debug.print("-----------------------------\n", .{});
    // }

    // {
    //     std.debug.print("\n", .{});
    //     std.debug.print("Boundary Fragments:\n", .{});
    //     std.debug.print("-----------------------------\n", .{});
    //     for (soup.boundary_fragments.items) |boundary_fragment| {
    //         std.debug.print("({},{}): ({},{}), ({},{})\n", .{
    //             boundary_fragment.pixel.x,
    //             boundary_fragment.pixel.y,
    //             boundary_fragment.intersections[0].point.x,
    //             boundary_fragment.intersections[0].point.y,
    //             boundary_fragment.intersections[1].point.x,
    //             boundary_fragment.intersections[1].point.y,
    //         });
    //     }
    //     std.debug.print("-----------------------------\n", .{});
    // }

    // {
    //     std.debug.print("\n============== Boundary Texture\n\n", .{});
    //     for (0..texture.dimensions.height) |y| {
    //         std.debug.print("{:0>4}: ", .{y});
    //         for (0..texture.dimensions.width) |x| {
    //             const pixel = texture.getPixelUnsafe(core.PointU32{
    //                 .x = @intCast(x),
    //                 .y = @intCast(y),
    //             });

    //             if (pixel.r < 1.0) {
    //                 std.debug.print("#", .{});
    //             } else {
    //                 std.debug.print(";", .{});
    //             }
    //         }

    //         std.debug.print("\n", .{});
    //     }

    //     std.debug.print("==============\n", .{});
    // }
    // try image.writeToFile(output_file, .png);
}
