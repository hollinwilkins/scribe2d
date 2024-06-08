const std = @import("std");
const scriobh = @import("scriobh");
const text = scriobh.text;
const draw = scriobh.draw;
const core = scriobh.core;

pub fn main() !void {
    var args = std.process.args();

    _ = args.skip();
    const font_file = args.next() orelse @panic("need to provide a font file");
    const glyph_id_str = args.next() orelse @panic("need to provide a glyph_id");
    const glyph_id = try std.fmt.parseInt(u16, glyph_id_str, 10);
    const size_str = args.next() orelse "16";
    const size = try std.fmt.parseInt(u32, size_str, 10);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var face = try text.Face.initFile(allocator, font_file);
    defer face.deinit();

    var pen = try draw.Pen.init(allocator);
    defer pen.deinit();
    _ = try face.unmanaged.tables.glyf.?.outline(glyph_id, pen.textOutliner());
    const path = try pen.createPathAlloc(allocator);
    defer path.deinit();

    const dimensions = core.DimensionsU32{
        .width = size,
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
            .x = dimensions.width,
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
    for (raster_data.getSubpaths(), 0..) |subpath, subpath_index| {
        for (raster_data.getCurves()[subpath.curve_offsets.start..subpath.curve_offsets.end], 0..) |curve, curve_index| {
            std.debug.print("Curve({},{}): {}\n", .{ subpath_index, curve_index, curve.curve_fn });
        }
    }

    std.debug.print("\n", .{});
    std.debug.print("Pixel Intersections:\n", .{});
    for (raster_data.getSubpaths(), 0..) |subpath, subpath_index| {
        for (raster_data.getCurveRecords()[subpath.curve_offsets.start..subpath.curve_offsets.end], 0..) |curve_record, curve_index| {
            for (raster_data.getPixelIntersections()[curve_record.pixel_intersection_offests.start..curve_record.pixel_intersection_offests.end]) |pixel_intersection| {
                std.debug.print("PixelIntersection({},{}): Pixel({},{}), T({}), Intersection({},{})\n", .{
                    subpath_index,
                    curve_index,
                    pixel_intersection.getPixel().x,
                    pixel_intersection.getPixel().y,
                    pixel_intersection.getT(),
                    pixel_intersection.getPoint().x,
                    pixel_intersection.getPoint().y,
                });
            }
            std.debug.print("-----------------------------\n", .{});
        }
    }

    std.debug.print("\n", .{});
    std.debug.print("Curve Fragments:\n", .{});
    for (raster_data.getCurveFragments()) |curve_fragment| {
        std.debug.print("CurveFragment, Pixel({},{}), Intersection(({},{}),({},{}):({},{}))\n", .{
            curve_fragment.pixel.x,
            curve_fragment.pixel.y,
            curve_fragment.intersections[0].t,
            curve_fragment.intersections[1].t,
            curve_fragment.intersections[0].point.x,
            curve_fragment.intersections[0].point.y,
            curve_fragment.intersections[1].point.x,
            curve_fragment.intersections[1].point.y,
        });
    }
    std.debug.print("-----------------------------\n", .{});

    std.debug.print("\n", .{});
    std.debug.print("Boundary Fragments:\n", .{});
    for (raster_data.getBoundaryFragments()) |boundary_fragment| {
        std.debug.print("BoundaryFragment, Pixel({},{}), StencilMask({b:0>16})\n", .{
            boundary_fragment.pixel.x,
            boundary_fragment.pixel.y,
            boundary_fragment.stencil_mask,
        });
    }

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
                .a = 1.0,
            };
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
}
