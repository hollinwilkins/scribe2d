const std = @import("std");
const scribe = @import("scribe");
const zstbi = @import("zstbi");
const zdawn = @import("zdawn");
const text = scribe.text;
const draw = scribe.draw;
const core = scribe.core;
const wgpu = zdawn.wgpu;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var encoder = draw.Encoder.init(allocator);
    defer encoder.deinit();

    {
        try encoder.encodeColor(draw.ColorU8{
            .a = 255,
        });
        try encoder.encodeColor(draw.ColorU8{
            .r = 255,
            .a = 255,
        });
        var style = draw.Style{};
        style.setFill(draw.Style.Fill{
            .brush = .color,
        });
        style.setStroke(draw.Style.Stroke{
            .brush = .color,
            .start_cap = .round,
            .end_cap = .round,
            .join = .miter,
        });
        try encoder.encodeStyle(style);

        var path_encoder = encoder.pathEncoder(f32);
        try path_encoder.moveTo(0.0, 0.0);
        try path_encoder.lineTo(100.0, 100.0);
        try path_encoder.quadTo(150.0, 150.0, 200.0, 100.0);
        try path_encoder.cubicTo(220.0, 80.0, 140.0, 60.0, 0.0, 0.0);

        try path_encoder.moveTo(500.0, 500.0);
        try path_encoder.cubicTo(550.0, 550.0, 512.0, 600.0, 330.0, 700.0);
        try path_encoder.lineTo(500.0, 500.0);
        try path_encoder.finish();
    }

    {
        var path_encoder = encoder.pathEncoder(f32);
        try path_encoder.moveTo(700.0, 50.0);
        try path_encoder.cubicTo(777.0, 130.0, 800.0, 100.0, 730.0, 300.0);
        // try path_encoder.lineTo(700.0, 50.0);
        try path_encoder.finish();
    }

    {
        try encoder.encodeColor(draw.ColorU8{
            .g = 255,
            .a = 255,
        });
        var style = draw.Style{};
        style.setStroke(draw.Style.Stroke{
            .brush = .color,
            .start_cap = .round,
            .end_cap = .round,
            .join = .miter,
        });
        try encoder.encodeStyle(style);

        var path_encoder = encoder.pathEncoder(f32);
        try path_encoder.moveTo(400.0, 500.0);
        try path_encoder.lineTo(700.0, 700.0);
        try path_encoder.quadTo(750.0, 650.0, 700.0, 600.0);
        try path_encoder.finish();
    }

    var half_planes = try draw.HalfPlanesU16.init(allocator);
    defer half_planes.deinit();

    var config = draw.cpu.CpuRasterizer.Config{};
    config.debug_flags.expand_monoids = true;
    config.debug_flags.calculate_lines = true;
    var rasterizer = try draw.cpu.CpuRasterizer.init(allocator, &half_planes, config);
    defer rasterizer.deinit();

    rasterizer.rasterize(encoder.encode());
}

// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const allocator = gpa.allocator();

//     var args = std.process.args();
//     _ = args.next();
//     const svg_file = args.next() orelse @panic("need to provide svg file");
//     const output_file = args.next() orelse @panic("need to provide output file");
//     const debug_point = args.next();

//     var svg = try scribe.svg.Svg.parseFileAlloc(allocator, svg_file);
//     defer svg.deinit();

//     var encoder = draw.Encoder.init(allocator);
//     defer encoder.deinit();

//     // {
//     //     try encoder.encodeColor(draw.ColorU8{
//     //         .a = 255,
//     //     });
//     //     try encoder.encodeColor(draw.ColorU8{
//     //         .r = 255,
//     //         .a = 255,
//     //     });
//     //     var style = draw.Style{};
//     //     style.setFill(draw.Style.Fill{
//     //         .brush = .color,
//     //     });
//     //     style.setStroke(draw.Style.Stroke{
//     //         .brush = .color,
//     //         .start_cap = .round,
//     //         .end_cap = .round,
//     //         .join = .miter,
//     //     });
//     //     try encoder.encodeStyle(style);

//     //     var path_encoder = encoder.pathEncoder(f32);
//     //     try path_encoder.moveTo(0.0, 0.0);
//     //     try path_encoder.lineTo(100.0, 100.0);
//     //     try path_encoder.quadTo(150.0, 150.0, 200.0, 100.0);
//     //     try path_encoder.cubicTo(220.0, 80.0, 140.0, 60.0, 0.0, 0.0);

//     //     try path_encoder.moveTo(500.0, 500.0);
//     //     try path_encoder.cubicTo(550.0, 550.0, 512.0, 600.0, 330.0, 700.0);
//     //     try path_encoder.lineTo(500.0, 500.0);
//     //     try path_encoder.finish();
//     // }

//     // {
//     //     var path_encoder = encoder.pathEncoder(f32);
//     //     try path_encoder.moveTo(700.0, 50.0);
//     //     try path_encoder.cubicTo(777.0, 130.0, 800.0, 100.0, 730.0, 300.0);
//     //     // try path_encoder.lineTo(700.0, 50.0);
//     //     try path_encoder.finish();
//     // }

//     // {
//     //     try encoder.encodeColor(draw.ColorU8{
//     //         .g = 255,
//     //         .a = 255,
//     //     });
//     //     var style = draw.Style{};
//     //     style.setStroke(draw.Style.Stroke{
//     //         .brush = .color,
//     //         .start_cap = .round,
//     //         .end_cap = .round,
//     //         .join = .miter,
//     //     });
//     //     try encoder.encodeStyle(style);

//     //     var path_encoder = encoder.pathEncoder(f32);
//     //     try path_encoder.moveTo(400.0, 500.0);
//     //     try path_encoder.lineTo(700.0, 700.0);
//     //     try path_encoder.quadTo(750.0, 650.0, 700.0, 600.0);
//     //     try path_encoder.finish();
//     // }

//     try svg.encode(&encoder);

//     const bigger = (core.TransformF32{
//         .scale = core.PointF32.create(4.0, 4.0),
//     }).toAffine();

//     for (encoder.transforms.items) |*tf| {
//         tf.* = bigger.mul(tf.*);
//     }

//     const bounds = encoder.calculateBounds();

//     const center = (core.TransformF32{
//         .translate = core.PointF32.create(-bounds.min.x + 32.0, -bounds.min.y + 32.0),
//     }).toAffine();

//     for (encoder.transforms.items) |*tf| {
//         tf.* = center.mul(tf.*);
//     }

//     const dimensions = core.DimensionsU32{
//         .width = @intFromFloat(@ceil(bounds.getWidth()) + 64.0),
//         .height = @intFromFloat(@ceil(bounds.getHeight()) + 64.0),
//     };

//     const encoding = encoder.encode();

//     const gctx = try zdawn.GraphicsContext.create(allocator, .{});
//     defer gctx.destroy(allocator);

//     var half_planes = try draw.HalfPlanesU16.init(allocator);
//     defer half_planes.deinit();

//     const rasterizer_config = draw.CpuRasterizer.Config{
//         .run_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
//         // .debug_flags = 0,
//         .debug_flags = draw.CpuRasterizer.Config.RUN_FLAG_EXPAND_MONOIDS,
//         // .debug_flags = draw.CpuRasterizer.Config.RUN_FLAG_ESTIMATE_SEGMENTS,
//         // .debug_single_pass = true,
//         .kernel_config = draw.KernelConfig.DEFAULT,
//         // .flush_texture_span = false,
//     };
//     var rasterizer = try draw.CpuRasterizer.init(
//         allocator,
//         &half_planes,
//         rasterizer_config,
//         encoding,
//     );
//     defer rasterizer.deinit();

//     zstbi.init(allocator);
//     defer zstbi.deinit();

//     var image = try zstbi.Image.createEmpty(
//         dimensions.width,
//         dimensions.height,
//         3,
//         .{},
//     );
//     defer image.deinit();

//     var texture = draw.TextureUnmanaged{
//         .dimensions = dimensions,
//         .format = draw.TextureFormat.RgbU8,
//         .bytes = image.data,
//     };
//     texture.clear(draw.Colors.WHITE);

//     try rasterizer.rasterize(&texture);

//     rasterizer.debugPrint(texture);

//     try image.writeToFile(output_file, .png);

//     if (debug_point) |dbg_point_str| {
//         var it = std.mem.split(u8, dbg_point_str, ",");
//         var n0: ?i32 = null;
//         var n1: ?i32 = null;

//         if (it.next()) |x_str| {
//             n0 = std.fmt.parseInt(i32, x_str, 10) catch @panic("Invalid x for debug point");
//         }

//         if (it.next()) |y_str| {
//             n1 = std.fmt.parseInt(i32, y_str, 10) catch @panic("Invalid y for debug point");
//         }

//         if (n0 != null and n1 != null) {
//             const dbg_point = core.PointI32.create(n0.?, n1.?);

//             std.debug.print("===================== Debug Point: {} =====================\n", .{dbg_point});
//             for (rasterizer.paths.items) |path| {
//                 const path_monoid = rasterizer.path_monoids.items[path.segment_index];
//                 const fill_boundary_fragments = rasterizer.boundary_fragments.items[path.boundary_offset.start_fill_offset..path.boundary_offset.end_fill_offset];
//                 const stroke_boundary_fragments = rasterizer.boundary_fragments.items[path.boundary_offset.start_stroke_offset..path.boundary_offset.end_stroke_offset];

//                 std.debug.print("Path({})\n", .{path_monoid.path_index});
//                 std.debug.print("------------- Fill Boundary Fragments ------------\n", .{});
//                 for (fill_boundary_fragments) |boundary_fragment| {
//                     if (std.meta.eql(boundary_fragment.pixel, dbg_point)) {
//                         std.debug.print("BoundaryFragment({},{})({},{})-({},{}): IsMerge({}), T1({}), T2({}), MainRayWinding({})\n", .{
//                             boundary_fragment.pixel.x,
//                             boundary_fragment.pixel.y,
//                             boundary_fragment.intersections[0].point.x,
//                             boundary_fragment.intersections[0].point.y,
//                             boundary_fragment.intersections[1].point.x,
//                             boundary_fragment.intersections[1].point.y,
//                             boundary_fragment.is_merge,
//                             boundary_fragment.intersections[0].t,
//                             boundary_fragment.intersections[1].t,
//                             boundary_fragment.main_ray_winding,
//                         });
//                         std.debug.print("-----\n", .{});
//                         boundary_fragment.masks.debugPrint();
//                         std.debug.print("-----\n", .{});
//                         std.debug.print("StencilMask({b:0>16}), Intensity({})\n", .{
//                             boundary_fragment.stencil_mask,
//                             boundary_fragment.getIntensity(),
//                         });
//                         std.debug.print("-----------------------------\n", .{});
//                     }
//                 }
//                 std.debug.print("------------- End Fill Boundary Fragments ------------\n", .{});

//                 std.debug.print("------------- Stroke Boundary Fragments ------------\n", .{});
//                 for (stroke_boundary_fragments) |boundary_fragment| {
//                     if (std.meta.eql(boundary_fragment.pixel, dbg_point)) {
//                         std.debug.print("BoundaryFragment({},{})({},{})-({},{}): IsMerge({}), T1({}), T2({}), MainRayWinding({})\n", .{
//                             boundary_fragment.pixel.x,
//                             boundary_fragment.pixel.y,
//                             boundary_fragment.intersections[0].point.x,
//                             boundary_fragment.intersections[0].point.y,
//                             boundary_fragment.intersections[1].point.x,
//                             boundary_fragment.intersections[1].point.y,
//                             boundary_fragment.is_merge,
//                             boundary_fragment.intersections[0].t,
//                             boundary_fragment.intersections[1].t,
//                             boundary_fragment.main_ray_winding,
//                         });
//                         std.debug.print("-----\n", .{});
//                         boundary_fragment.masks.debugPrint();
//                         std.debug.print("-----\n", .{});
//                         std.debug.print("StencilMask({b:0>16}), Intensity({})\n", .{
//                             boundary_fragment.stencil_mask,
//                             boundary_fragment.getIntensity(),
//                         });
//                         std.debug.print("-----------------------------\n", .{});
//                     }
//                 }
//                 std.debug.print("------------- End Stroke Boundary Fragments ------------\n", .{});
//             }
//         } else if (n0 != null) {
//             const y = n0.?;

//             std.debug.print("===================== Debug Line: {} =====================\n", .{y});
//             for (rasterizer.paths.items) |path| {
//                 const path_monoid = rasterizer.path_monoids.items[path.segment_index];
//                 const fill_boundary_fragments = rasterizer.boundary_fragments.items[path.boundary_offset.start_fill_offset..path.boundary_offset.end_fill_offset];
//                 const stroke_boundary_fragments = rasterizer.boundary_fragments.items[path.boundary_offset.start_stroke_offset..path.boundary_offset.end_stroke_offset];

//                 std.debug.print("Path({})\n", .{path_monoid.path_index});
//                 std.debug.print("------------- Fill Boundary Fragments ------------\n", .{});
//                 for (fill_boundary_fragments) |boundary_fragment| {
//                     if (boundary_fragment.pixel.y == y) {
//                     // if (boundary_fragment.pixel.y == y and boundary_fragment.is_merge) {
//                         std.debug.print("BoundaryFragment({},{})({},{})-({},{}): IsMerge({}), T1({}), T2({}), MainRayWinding({})\n", .{
//                             boundary_fragment.pixel.x,
//                             boundary_fragment.pixel.y,
//                             boundary_fragment.intersections[0].point.x,
//                             boundary_fragment.intersections[0].point.y,
//                             boundary_fragment.intersections[1].point.x,
//                             boundary_fragment.intersections[1].point.y,
//                             boundary_fragment.is_merge,
//                             boundary_fragment.intersections[0].t,
//                             boundary_fragment.intersections[1].t,
//                             boundary_fragment.main_ray_winding,
//                         });
//                         std.debug.print("-----\n", .{});
//                         boundary_fragment.masks.debugPrint();
//                         std.debug.print("-----\n", .{});
//                         std.debug.print("StencilMask({b:0>16}), Intensity({})\n", .{
//                             boundary_fragment.stencil_mask,
//                             boundary_fragment.getIntensity(),
//                         });
//                         std.debug.print("-----------------------------\n", .{});
//                     }
//                 }
//                 std.debug.print("------------- End Fill Boundary Fragments ------------\n", .{});

//                 std.debug.print("------------- Stroke Boundary Fragments ------------\n", .{});
//                 for (stroke_boundary_fragments) |boundary_fragment| {
//                     if (boundary_fragment.pixel.y == y) {
//                     // if (boundary_fragment.pixel.y == y and boundary_fragment.is_merge) {
//                         std.debug.print("BoundaryFragment({},{})({},{})-({},{}): IsMerge({}), T1({}), T2({}), MainRayWinding({})\n", .{
//                             boundary_fragment.pixel.x,
//                             boundary_fragment.pixel.y,
//                             boundary_fragment.intersections[0].point.x,
//                             boundary_fragment.intersections[0].point.y,
//                             boundary_fragment.intersections[1].point.x,
//                             boundary_fragment.intersections[1].point.y,
//                             boundary_fragment.is_merge,
//                             boundary_fragment.intersections[0].t,
//                             boundary_fragment.intersections[1].t,
//                             boundary_fragment.main_ray_winding,
//                         });
//                         std.debug.print("-----\n", .{});
//                         boundary_fragment.masks.debugPrint();
//                         std.debug.print("-----\n", .{});
//                         std.debug.print("StencilMask({b:0>16}), Intensity({})\n", .{
//                             boundary_fragment.stencil_mask,
//                             boundary_fragment.getIntensity(),
//                         });
//                         std.debug.print("-----------------------------\n", .{});
//                     }
//                 }
//                 std.debug.print("------------- End Stroke Boundary Fragments ------------\n", .{});
//             }
//         }
//     }
// }
