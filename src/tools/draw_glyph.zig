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

    var builder = try draw.PathBuilder.init(allocator);
    defer builder.deinit();

    // const glyph_id = face.unmanaged.tables.cmap.?.subtables.getGlyphIndex(codepoint).?;
    _ = try face.outline(glyph_id, @floatFromInt(size), text.GlyphPen.Debug.Instance);
    const bounds = try face.outline(glyph_id, @floatFromInt(size), builder.glyphPen());
    _ = bounds;
    var path = try builder.createPathAlloc(allocator);
    path.unmanaged.subpaths.len -= 0;
    defer path.deinit();

    const dimensions = core.DimensionsU32{
        .width = size * 3,
        .height = size,
    };

    var rasterizer = try draw.Rasterizer.init(allocator);
    defer rasterizer.deinit();

    var raster_data = try rasterizer.rasterizeDebug(&path);
    defer raster_data.deinit();

    // output curves
    std.debug.print("\n", .{});
    std.debug.print("Curves:\n", .{});
    std.debug.print("OFFSETS2: {}\n", .{builder.subpaths.items[0].curve_offsets});
    for (raster_data.getSubpaths(), 0..) |subpath, subpath_index| {
        for (raster_data.getCurves()[subpath.curve_offsets.start..subpath.curve_offsets.end], 0..) |curve, curve_index| {
            std.debug.print("Curve({},{}): {}\n", .{ subpath_index, curve_index, curve.curve_fn });
        }
    }

    // std.debug.print("\n", .{});
    // std.debug.print("Grid Intersections:\n", .{});
    // for (raster_data.getSubpaths(), 0..) |subpath, subpath_index| {
    //     for (raster_data.getCurveRecords()[subpath.curve_offsets.start..subpath.curve_offsets.end], 0..) |curve_record, curve_index| {
    //         for (raster_data.getGridIntersections()[curve_record.grid_intersection_offests.start..curve_record.grid_intersection_offests.end]) |grid_intersection| {
    //             std.debug.print("GridIntersection({},{}): Pixel({},{}), T({}), Intersection({},{})\n", .{
    //                 subpath_index,
    //                 curve_index,
    //                 grid_intersection.getPixel().x,
    //                 grid_intersection.getPixel().y,
    //                 grid_intersection.getT(),
    //                 grid_intersection.getPoint().x,
    //                 grid_intersection.getPoint().y,
    //             });
    //         }
    //         std.debug.print("-----------------------------\n", .{});
    //     }
    // }

    // std.debug.print("\n", .{});
    // std.debug.print("Curve Fragments:\n", .{});
    // for (raster_data.getCurveFragments()) |curve_fragment| {
    //     std.debug.print("CurveFragment, Pixel({},{}), Intersection(({},{}),({},{}):({},{}))\n", .{
    //         curve_fragment.pixel.x,
    //         curve_fragment.pixel.y,
    //         curve_fragment.intersections[0].t,
    //         curve_fragment.intersections[1].t,
    //         curve_fragment.intersections[0].point.x,
    //         curve_fragment.intersections[0].point.y,
    //         curve_fragment.intersections[1].point.x,
    //         curve_fragment.intersections[1].point.y,
    //     });
    // }
    // std.debug.print("-----------------------------\n", .{});

    // std.debug.print("\n", .{});
    // std.debug.print("Boundary Fragments:\n", .{});
    // for (raster_data.getBoundaryFragments(), 0..) |boundary_fragment, index| {
    //     std.debug.print("BoundaryFragment({}), MainRayWinding({}), Pixel({},{}), StencilMask({b:0>16})\n", .{
    //         index,
    //         boundary_fragment.main_ray_winding,
    //         boundary_fragment.pixel.x,
    //         boundary_fragment.pixel.y,
    //         boundary_fragment.stencil_mask,
    //     });
    // }

    // std.debug.print("\n", .{});
    // std.debug.print("Spans:\n", .{});
    // for (raster_data.getSpans()) |span| {
    //     std.debug.print("Span, Y({}), X({},{}), Winding({})\n", .{
    //         span.y,
    //         span.x_range.start,
    //         span.x_range.end,
    //         span.winding,
    //     });
    // }

    zstbi.init(allocator);
    defer zstbi.deinit();

    var image = try zstbi.Image.createEmpty(
        dimensions.width,
        dimensions.height,
        4,
        .{},
    );
    defer image.deinit();

    var texture = draw.TextureUnmanaged{
        .dimensions = dimensions,
        .format = draw.TextureFormat.SrgbaU8,
        .bytes = image.data,
    };

    std.debug.print("\n============== Boundary Texture\n\n", .{});
    texture.clear(draw.Color{
        .r = 1.0,
        .g = 1.0,
        .b = 1.0,
        .a = 1.0,
    });

    for (raster_data.getBoundaryFragments()) |fragment| {
        // const pixel = fragment.getPixel();
        const pixel = fragment.pixel;
        if (pixel.x >= 0 and pixel.y >= 0) {
            const intensity = 1.0 - fragment.getIntensity();
            const is_set = texture.setPixel(core.PointU32{
                .x = @intCast(pixel.x),
                .y = @intCast(pixel.y),
            }, draw.Color{
                .r = intensity,
                .g = intensity,
                .b = intensity,
                .a = 1.0,
            });
            std.debug.assert(is_set);
        }
    }

    for (raster_data.getSpans()) |span| {
        for (0..span.x_range.size()) |x_offset| {
            if (span.filled) {
                const x = @as(u32, @intCast(span.x_range.start)) + @as(u32, @intCast(x_offset));
                const is_set = texture.setPixel(core.PointU32{
                    .x = @intCast(x),
                    .y = @intCast(span.y),
                }, draw.Color{
                    .r = 0.0,
                    .g = 0.0,
                    .b = 0.0,
                    .a = 1.0,
                });

                std.debug.assert(is_set);
            }
        }
    }

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

    try image.writeToFile("/tmp/output.png", .png);
}
