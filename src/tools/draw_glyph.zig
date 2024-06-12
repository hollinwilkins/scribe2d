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

    var pen = try draw.Pen.init(allocator);
    defer pen.deinit();

    // const glyph_id = face.unmanaged.tables.cmap.?.subtables.getGlyphIndex(codepoint).?;
    _ = try face.unmanaged.tables.glyf.?.outline(glyph_id, text.TextOutliner.Debug.Instance);
    const aspect_ratio = try face.unmanaged.tables.glyf.?.outline(glyph_id, pen.textOutliner());
    var path = try pen.createPathAlloc(allocator);
    path.unmanaged.subpaths.len -= 0;
    defer path.deinit();

    const dimensions = core.DimensionsU32{
        .width = size * 3,
        .height = size,
    };

    var texture = try draw.UnmanagedTextureRgba.create(allocator, dimensions);
    defer texture.deinit(allocator);
    var texture_view = texture.createView(core.RectU32{
        .min = core.PointU32{
            .x = 0,
            .y = 0,
        },
        .max = core.PointU32{
            .x = @intFromFloat(@as(f64, @floatFromInt(dimensions.height)) * aspect_ratio),
            .y = dimensions.height,
        },
    }).?;

    var raster = try draw.Raster.init(allocator);
    defer raster.deinit();

    var raster_data = try raster.rasterizeDebug(&path, &texture_view);
    defer raster_data.deinit();

    // output curves
    std.debug.print("\n", .{});
    std.debug.print("Curves:\n", .{});
    std.debug.print("OFFSETS2: {}\n", .{pen.subpaths.items[0].curve_offsets});
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

    std.debug.print("\n============== Boundary Texture\n\n", .{});
    var boundary_texture = try draw.UnmanagedTextureMonotone.create(allocator, core.DimensionsU32{
        .width = dimensions.width + 2,
        .height = dimensions.height + 2,
    });
    defer boundary_texture.deinit(allocator);
    boundary_texture.clear(draw.Monotone{ .a = 0.0 });
    var boundary_texture_view = boundary_texture.createView(core.RectU32.create(core.PointU32{
        .x = 1,
        .y = 1,
    }, core.PointU32{
        .x = dimensions.width + 1,
        .y = dimensions.height + 1,
    })).?;

    for (raster_data.getBoundaryFragments()) |fragment| {
        // const pixel = fragment.getPixel();
        const pixel = fragment.pixel;
        if (pixel.x >= 0 and pixel.y >= 0) {
            boundary_texture_view.getPixelUnsafe(core.PointU32{
                .x = @intCast(pixel.x),
                .y = @intCast(pixel.y),
            }).* = draw.Monotone{
                .a = fragment.getIntensity(),
            };
        }
    }

    for (raster_data.getSpans()) |span| {
        for (0..span.x_range.size()) |x_offset| {
            if (span.filled) {
                const x = @as(u32, @intCast(span.x_range.start)) + @as(u32, @intCast(x_offset));
                boundary_texture_view.getPixelUnsafe(core.PointU32{
                    .x = @intCast(x),
                    .y = @intCast(span.y),
                }).* = draw.Monotone{
                    .a = 1.0,
                };
            }
        }
    }

    for (0..boundary_texture_view.view.getHeight()) |y| {
        std.debug.print("{:0>4}: ", .{y});
        for (boundary_texture_view.getRow(@intCast(y)).?) |pixel| {
            if (pixel.a > 0.0) {
                std.debug.print("#", .{});
            } else {
                std.debug.print(";", .{});
            }
        }

        std.debug.print("\n", .{});
    }

    std.debug.print("==============\n", .{});

    zstbi.init(allocator);
    defer zstbi.deinit();

    var image = try zstbi.Image.createEmpty(
        dimensions.width,
        dimensions.height,
        3,
        .{},
    );
    defer image.deinit();

    for (image.data) |*v| {
        v.* = std.math.maxInt(u8);
    }

    for (0..boundary_texture_view.getDimensions().height) |y| {
        for (boundary_texture_view.getRow(@intCast(y)).?, 0..) |pixel, x| {
            if (x == 127 and y == 64) {
                std.debug.print("Intensity: {}\n", .{pixel.a});
            }
            const image_pixel = (y * image.bytes_per_row) + (x * image.num_components * image.bytes_per_component);
            const value = std.math.maxInt(u8) - std.math.clamp(
                @as(u8, @intFromFloat(@round(std.math.pow(f32, pixel.a, 1.0 / 2.2) * std.math.maxInt(u8)))),
                0,
                std.math.maxInt(u8),
            );
            // const value = std.math.maxInt(u8) - std.math.clamp(
            //     @as(u8, @intFromFloat(@round(pixel.a * std.math.maxInt(u8)))),
            //     0,
            //     std.math.maxInt(u8),
            // );
            // const value: u8 = if (pixel.a > 0.0) 0 else std.math.maxInt(u8);
            image.data[image_pixel] = value;
            image.data[image_pixel + 1] = value;
            image.data[image_pixel + 2] = value;
        }
    }

    try image.writeToFile("/tmp/output.png", .png);
}
