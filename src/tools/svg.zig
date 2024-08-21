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
    _ = args.next();
    const svg_file = args.next() orelse @panic("need to provide svg file");
    const output_file = args.next() orelse @panic("need to provide output file");
    const debug_point = args.next();

    var svg = try scribe.svg.Svg.parseFileAlloc(allocator, svg_file);
    defer svg.deinit();

    var encoder = draw.Encoder.init(allocator);
    defer encoder.deinit();

    try svg.encode(&encoder);

    const bigger = (core.TransformF32{
        .scale = core.PointF32.create(2.0, 2.0),
    }).toAffine();

    for (encoder.transforms.items) |*tf| {
        tf.* = bigger.mul(tf.*);
    }

    const bounds = encoder.calculateBounds();

    const center = (core.TransformF32{
        .translate = core.PointF32.create(-bounds.min.x + 32.0, -bounds.min.y + 32.0),
    }).toAffine();

    for (encoder.transforms.items) |*tf| {
        tf.* = center.mul(tf.*);
    }

    const dimensions = core.DimensionsU32{
        .width = @intFromFloat(@ceil(bounds.getWidth()) + 64.0),
        .height = @intFromFloat(@ceil(bounds.getHeight()) + 64.0),
    };

    const encoding = encoder.encode();

    var half_planes = try draw.HalfPlanesU16.init(allocator);
    defer half_planes.deinit();

    const rasterizer_config = draw.CpuRasterizer.Config{
        .run_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
        .debug_flags = 0,
        // .debug_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALLOCATE_LINES,
        // .debug_flags = draw.CpuRasterizer.Config.RUN_FLAG_ESTIMATE_SEGMENTS,
        // .debug_single_pass = true,
        .kernel_config = draw.KernelConfig.DEFAULT,
        // .flush_texture_span = false,
    };
    var rasterizer = try draw.CpuRasterizer.init(
        allocator,
        &half_planes,
        rasterizer_config,
        encoding,
    );
    defer rasterizer.deinit();

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
        .format = draw.TextureFormat.RgbU8,
        .bytes = image.data,
    };
    texture.clear(draw.Colors.WHITE);

    try rasterizer.rasterize(&texture);

    rasterizer.debugPrint(texture);

    try image.writeToFile(output_file, .png);

    if (debug_point) |dbg_point_str| {
        var dbg_point = core.PointI32{};
        var it = std.mem.split(u8, dbg_point_str, ",");

        if (it.next()) |x_str| {
            dbg_point.x = std.fmt.parseInt(i32, x_str, 10) catch @panic("Invalid x for debug point");
        }

        if (it.next()) |y_str| {
            dbg_point.y = std.fmt.parseInt(i32, y_str, 10) catch @panic("Invalid y for debug point");
        }

        std.debug.print("===================== Debug Point: {} =====================\n", .{dbg_point});
        for (rasterizer.paths.items) |path| {
            const path_monoid = rasterizer.path_monoids.items[path.segment_index];
            const fill_boundary_fragments = rasterizer.boundary_fragments.items[path.boundary_offset.start_fill_offset..path.boundary_offset.end_fill_offset];
            const stroke_boundary_fragments = rasterizer.boundary_fragments.items[path.boundary_offset.start_stroke_offset..path.boundary_offset.end_stroke_offset];

            std.debug.print("Path({})\n", .{path_monoid.path_index});
            std.debug.print("------------- Fill Boundary Fragments ------------\n", .{});
            for (fill_boundary_fragments) |boundary_fragment| {
                if (std.meta.eql(boundary_fragment.pixel, dbg_point)) {
                    std.debug.print("BoundaryFragment({},{})({},{})-({},{}): IsMerge({}), T1({}), T2({}), MainRayWinding({})\n", .{
                        boundary_fragment.pixel.x,
                        boundary_fragment.pixel.y,
                        boundary_fragment.intersections[0].point.x,
                        boundary_fragment.intersections[0].point.y,
                        boundary_fragment.intersections[1].point.x,
                        boundary_fragment.intersections[1].point.y,
                        boundary_fragment.is_merge,
                        boundary_fragment.intersections[0].t,
                        boundary_fragment.intersections[1].t,
                        boundary_fragment.main_ray_winding,
                    });
                    std.debug.print("-----\n", .{});
                    boundary_fragment.masks.debugPrint();
                    std.debug.print("-----\n", .{});
                    std.debug.print("StencilMask({b:0>16}), Intensity({})\n", .{
                        boundary_fragment.stencil_mask,
                        boundary_fragment.getIntensity(),
                    });
                    std.debug.print("-----------------------------\n", .{});
                }
            }
            std.debug.print("------------- End Fill Boundary Fragments ------------\n", .{});

            std.debug.print("------------- Stroke Boundary Fragments ------------\n", .{});
            for (stroke_boundary_fragments) |boundary_fragment| {
                if (std.meta.eql(boundary_fragment.pixel, dbg_point)) {
                    std.debug.print("BoundaryFragment({},{})({},{})-({},{}): IsMerge({}), T1({}), T2({}), MainRayWinding({})\n", .{
                        boundary_fragment.pixel.x,
                        boundary_fragment.pixel.y,
                        boundary_fragment.intersections[0].point.x,
                        boundary_fragment.intersections[0].point.y,
                        boundary_fragment.intersections[1].point.x,
                        boundary_fragment.intersections[1].point.y,
                        boundary_fragment.is_merge,
                        boundary_fragment.intersections[0].t,
                        boundary_fragment.intersections[1].t,
                        boundary_fragment.main_ray_winding,
                    });
                    std.debug.print("-----\n", .{});
                    boundary_fragment.masks.debugPrint();
                    std.debug.print("-----\n", .{});
                    std.debug.print("StencilMask({b:0>16}), Intensity({})\n", .{
                        boundary_fragment.stencil_mask,
                        boundary_fragment.getIntensity(),
                    });
                    std.debug.print("-----------------------------\n", .{});
                }
            }
            std.debug.print("------------- End Stroke Boundary Fragments ------------\n", .{});
        }
    }
}
