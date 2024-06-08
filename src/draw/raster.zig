const std = @import("std");
const path_module = @import("./path.zig");
const curve_module = @import("./curve.zig");
const core = @import("../core/root.zig");
const texture_module = @import("./texture.zig");
const msaa = @import("./msaa.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TextureViewRgba = texture_module.TextureViewRgba;
const Path = path_module.Path;
const PointF32 = core.PointF32;
const PointU32 = core.PointU32;
const PointI32 = core.PointI32;
const DimensionsF32 = core.DimensionsF32;
const DimensionsU32 = core.DimensionsU32;
const RectU32 = core.RectU32;
const RectF32 = core.RectF32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const RangeI32 = core.RangeI32;
const RangeUsize = core.RangeUsize;
const Shape = curve_module.Shape;
const Curve = curve_module.Curve;
const Line = curve_module.Line;
const Intersection = curve_module.Intersection;
const UnmanagedTexture = texture_module.UnmanagedTexture;
const HalfPlanesU16 = msaa.HalfPlanesU16;

pub const CurveRecord = struct {
    pixel_intersection_offests: RangeU32,
};

pub const RasterData = struct {
    const CurveRecordList = std.ArrayListUnmanaged(CurveRecord);
    const PixelIntersectionList = std.ArrayListUnmanaged(PixelIntersection);

    allocator: Allocator,
    path: *const Path,
    view: *TextureViewRgba,
    curve_records: CurveRecordList = CurveRecordList{},
    pixel_intersections: PixelIntersectionList = PixelIntersectionList{},

    pub fn init(allocator: Allocator, path: *const Path, view: *TextureViewRgba) RasterData {
        return RasterData{
            .allocator = allocator,
            .path = path,
            .view = view,
        };
    }

    pub fn deinit(self: *RasterData) void {
        self.curve_records.deinit(self.allocator);
        self.pixel_intersections.deinit(self.allocator);
    }

    pub fn getPath(self: RasterData) *const Path {
        return self.path;
    }

    pub fn getView(self: *RasterData) *TextureViewRgba {
        return self.view;
    }

    pub fn getShapes(self: RasterData) []const Shape {
        return self.path.getShapes();
    }

    pub fn getCurves(self: RasterData) []const Curve {
        return self.path.getCurves();
    }

    pub fn getCurveRecords(self: *RasterData) []CurveRecord {
        return self.curve_records.items;
    }

    pub fn getPixelIntersections(self: *RasterData) []PixelIntersection {
        return self.pixel_intersections.items;
    }

    pub fn addCurveRecord(self: *RasterData) !*CurveRecord {
        return try self.curve_records.addOne(self.allocator);
    }

    pub fn addPixelIntersection(self: *RasterData) !*PixelIntersection {
        return try self.pixel_intersections.addOne(self.allocator);
    }
};

pub const PixelIntersection = struct {
    intersection: Intersection,
    pixel: PointI32,

    pub fn create(intersection: Intersection) PixelIntersection {
        return PixelIntersection{ .intersection = intersection, .pixel = PointI32{
            .x = @intFromFloat(intersection.point.x),
            .y = @intFromFloat(intersection.point.y),
        } };
    }

    pub fn getT(self: PixelIntersection) f32 {
        return self.intersection.t;
    }

    pub fn getPoint(self: PixelIntersection) PointF32 {
        return self.intersection.point;
    }

    pub fn getPixel(self: PixelIntersection) PointI32 {
        return self.pixel;
    }
};

// pub const PixelCurve = struct {
//     shape_index: u32,
//     curve_index: u32,
//     pixel: PointI32,
//     intersection1: Intersection,
//     intersection2: Intersection,
//     horizontal_mask: u16,
//     horizontal_sign: i2,
//     vertical_mask: u16,
//     vertical_sign: i2,

//     pub fn getLine(self: PixelCurve) Line {
//         return Line.create(self.intersection1.point, self.intersection2.point);
//     }
// };
// pub const PixelCurveList = std.ArrayList(PixelCurve);

// pub const BoundaryFragment = struct {
//     pixel: PointI32,
//     winding: f32,
//     bitmask: u16 = 0,
// };
// pub const BoundaryFragmentList = std.ArrayList(BoundaryFragment);

pub const Raster = struct {
    const BitmaskTexture = UnmanagedTexture(u16);

    allocator: Allocator,
    half_planes: HalfPlanesU16,

    pub fn init(allocator: Allocator) !Raster {
        return Raster{
            .allocator = allocator,
            .half_planes = try HalfPlanesU16.create(allocator, &msaa.UV_SAMPLE_COUNT_16),
        };
    }

    pub fn deinit(self: *Raster) void {
        self.half_planes.deinit();
    }

    pub fn rasterizeDebug(self: *Raster, path: *const Path, view: *TextureViewRgba) !RasterData {
        var raster_data = RasterData.init(self.allocator, path, view);
        errdefer raster_data.deinit();

        try self.populateIntersections(&raster_data);

        return raster_data;
    }

    pub fn populateIntersections(self: *Raster, raster_data: *RasterData) !void {
        _ = self;
        var monotonic_cuts: [2]Intersection = [_]Intersection{undefined} ** 2;

        const pixel_view_dimensions = raster_data.getView().getDimensions();
        const scaled_pixel_dimensions = DimensionsF32{
            .width = @floatFromInt(pixel_view_dimensions.width),
            .height = @floatFromInt(pixel_view_dimensions.height),
        };

        for (raster_data.getShapes()) |shape| {
            for (raster_data.getCurves()[shape.curve_offsets.start..shape.curve_offsets.end]) |curve| {
                var pixel_intersection_offsets = RangeU32{
                    .start = @intCast(raster_data.getPixelIntersections().len),
                    .end = @intCast(raster_data.getPixelIntersections().len),
                };
                const scaled_curve = curve.invertY().scale(scaled_pixel_dimensions);
                const scaled_curve_bounds = scaled_curve.getBounds();

                // first virtual intersection
                (try raster_data.addPixelIntersection()).* = PixelIntersection.create(
                    Intersection{
                        .t = 0.0,
                        .point = scaled_curve.applyT(0.0),
                    },
                );

                // scan x lines within bounds
                const grid_x_size: usize = @intFromFloat(scaled_curve_bounds.getWidth());
                const grid_x_start: i32 = @intFromFloat(scaled_curve_bounds.min.x);
                for (0..grid_x_size + 1) |x_offset| {
                    const grid_x = grid_x_start + @as(i32, @intCast(x_offset));
                    try scanX(
                        raster_data,
                        @as(f32, @floatFromInt(grid_x)),
                        scaled_curve,
                        scaled_curve_bounds,
                    );
                }

                // scan y lines within bounds
                const grid_y_size: usize = @intFromFloat(scaled_curve_bounds.getHeight());
                const grid_y_start: i32 = @intFromFloat(scaled_curve_bounds.min.y);
                for (0..grid_y_size + 1) |y_offset| {
                    const grid_y = grid_y_start + @as(i32, @intCast(y_offset));
                    try scanY(
                        raster_data,
                        @as(f32, @floatFromInt(grid_y)),
                        scaled_curve,
                        scaled_curve_bounds,
                    );
                }

                // insert monotonic cuts, which ensure curves are monotonic within a pixel
                for (scaled_curve.monotonicCuts(&monotonic_cuts)) |intersection| {
                    const ao = try raster_data.addPixelIntersection();
                    ao.* = PixelIntersection.create(intersection);
                }

                // last virtual intersection
                (try raster_data.addPixelIntersection()).* = PixelIntersection.create(Intersection{
                    .t = 1.0,
                    .point = scaled_curve.applyT(1.0),
                });

                pixel_intersection_offsets.end = @intCast(raster_data.getPixelIntersections().len);

                // sort by t within a curve
                std.mem.sort(
                    PixelIntersection,
                    raster_data.getPixelIntersections()[pixel_intersection_offsets.start..pixel_intersection_offsets.end],
                    @as(u32, 0),
                    pixelIntersectionLessThan,
                );

                // add curve record with offsets
                (try raster_data.addCurveRecord()).* = CurveRecord{
                    .pixel_intersection_offests = pixel_intersection_offsets,
                };
            }
        }
    }

    fn pixelIntersectionLessThan(_: u32, left: PixelIntersection, right: PixelIntersection) bool {
        if (left.getT() < right.getT()) {
            return true;
        }

        return false;
    }

    // intersections must be sorted by curve_index, t
    // pub fn createFragmentIntersectionsAlloc(self: *@This(), allocator: Allocator, intersections: []const PathIntersection) !FragmentIntersectionList {
    //     _ = self;
    //     var fragment_intersections = try FragmentIntersectionList.initCapacity(allocator, intersections.len - 1);

    //     for (0..intersections.len) |index| {
    //         if (index + 1 >= intersections.len) {
    //             break;
    //         }

    //         var intersection1 = intersections[index];
    //         var intersection2 = intersections[index + 1];
    //         if (std.meta.eql(intersection1.getPoint(), intersection2.getPoint())) {
    //             continue;
    //         }

    //         if (intersection1.is_end or intersection1.shape_index != intersection2.shape_index or intersection1.curve_index != intersection2.curve_index) {
    //             continue;
    //         }

    //         const x_offset: f32 = @floatFromInt(@abs(intersection1.getPixel().x - intersection2.getPixel().x));
    //         const y_offset: f32 = @floatFromInt(@abs(intersection1.getPixel().y - intersection2.getPixel().y));
    //         const point_offset = PointF32{
    //             .x = x_offset,
    //             .y = y_offset,
    //         };
    //         std.debug.assert(x_offset <= 1.0 and x_offset >= 0.0);
    //         std.debug.assert(y_offset <= 1.0 and y_offset >= 0.0);

    //         if (intersection1.getPixel().y > intersection2.getPixel().y) {
    //             std.mem.swap(PathIntersection, &intersection1, &intersection2);
    //             intersection2.intersection.intersection.point = intersection2.intersection.intersection.point.add(point_offset);
    //         } else if (intersection1.getPixel().y == intersection2.getPixel().y and intersection1.getPixel().x > intersection2.getPixel().x) {
    //             std.mem.swap(PathIntersection, &intersection1, &intersection2);
    //             intersection2.intersection.intersection.point = intersection2.intersection.intersection.point.add(point_offset);
    //         }

    //         const pixel = intersection1.getPixel();

    //         // const horizontal_mask = self.half_planes.getHorizontalMask(Line.create(
    //         //     intersection1.getPoint(),
    //         //     intersection2.getPoint(),
    //         // ));
    //         // var vertical_mask: u16 = 0;
    //         // var horizontal_sign: i2 = 0;
    //         // var vertical_sign: i2 = 0;
    //         // if (intersection1.getPoint().x == 0.0) {
    //         //     vertical_mask = self.half_planes.getVerticalMask(intersection1.getPoint().y);

    //         //     if (intersection1.getPoint().y > 0.5) {
    //         //         vertical_sign = -1;
    //         //     } else {
    //         //         vertical_sign = 1;
    //         //     }
    //         // } else if (intersection2.getPoint().x == 0.0) {
    //         //     vertical_mask = self.half_planes.getVerticalMask(intersection2.getPoint().y);

    //         //     if (intersection2.getPoint().y > 0.5) {
    //         //         vertical_sign = -1;
    //         //     } else {
    //         //         vertical_sign = 1;
    //         //     }
    //         // }

    //         // if (intersection1.getPoint().y > intersection2.getPoint().y) {
    //         //     horizontal_sign = 1;
    //         // } else if (intersection1.getPoint().y < intersection2.getPoint().y) {
    //         //     horizontal_sign = -1;
    //         // }

    //         // if (intersection1.getT() > intersection2.getT()) {
    //         //     horizontal_sign *= -1;
    //         //     vertical_sign *= -1;
    //         // }

    //         const ao = fragment_intersections.addOneAssumeCapacity();
    //         ao.* = FragmentIntersection{
    //             .shape_index = intersection1.shape_index,
    //             .curve_index = intersection1.curve_index,
    //             .pixel = pixel,
    //             .intersection1 = intersection1.getIntersection(),
    //             .intersection2 = intersection2.getIntersection(),
    //             .horizontal_mask = 0,
    //             .horizontal_sign = 0,
    //             .vertical_mask = 0,
    //             .vertical_sign = 0,
    //         };
    //     }

    //     // sort by path_id, y, x
    //     std.mem.sort(
    //         FragmentIntersection,
    //         fragment_intersections.items,
    //         @as(u32, 0),
    //         fragmentIntersectionLessThan,
    //     );

    //     return fragment_intersections;
    // }

    // fn fragmentIntersectionLessThan(_: u32, left: FragmentIntersection, right: FragmentIntersection) bool {
    //     if (left.shape_index < right.shape_index) {
    //         return true;
    //     } else if (left.shape_index > right.shape_index) {
    //         return false;
    //     } else if (left.pixel.y < right.pixel.y) {
    //         return true;
    //     } else if (left.pixel.y > right.pixel.y) {
    //         return false;
    //     } else if (left.pixel.x < right.pixel.x) {
    //         return true;
    //     } else {
    //         return false;
    //     }
    // }

    // pub fn unwindFragmentIntersectionsAlloc(allocator: Allocator, fragment_intersections: []FragmentIntersection) !BoundaryFragmentList {
    //     var boundary_fragments = BoundaryFragmentList.init(allocator);
    //     var index: usize = 0;

    //     while (index < fragment_intersections.len) {
    //         var fragment_intersection = &fragment_intersections[index];
    //         var previous_boundary_fragment: ?BoundaryFragment = null;
    //         const y = fragment_intersection.pixel.y;
    //         const start_index = fragment_intersections.len;
    //         var end_index = start_index;

    //         while (index < fragment_intersections.len and fragment_intersection.pixel.y == y) {
    //             var boundary_fragment: *BoundaryFragment = try boundary_fragments.addOne();
    //             boundary_fragment.* = BoundaryFragment{
    //                 .pixel = fragment_intersection.pixel,
    //                 .winding = 0.0,
    //             };
    //             const x = fragment_intersection.pixel.x;

    //             std.debug.print("Start new boundary fragment @ {}x{}\n", .{ x, y });

    //             while (index < fragment_intersections.len and fragment_intersection.pixel.x == x) {
    //                 if (previous_boundary_fragment) |previous| {
    //                     // set both winding values to the previous end winding value
    //                     // we haven't intersected the ray yet, so it is just
    //                     // continuous with the previous winding
    //                     boundary_fragment.winding = previous.winding;
    //                 }

    //                 const ray_y: f32 = @as(f32, @floatFromInt(fragment_intersection.pixel.y)) + 0.5;
    //                 const ray_line = Line.create(
    //                     PointF32{
    //                         .x = @floatFromInt(fragment_intersection.pixel.x),
    //                         .y = ray_y,
    //                     },
    //                     PointF32{
    //                         .x = @as(f32, @floatFromInt(fragment_intersection.pixel.x)) + 1.0,
    //                         .y = ray_y,
    //                     },
    //                 );
    //                 const fragment_intersection_line = fragment_intersection.getLine();

    //                 if (ray_line.intersectHorizontalLine(fragment_intersection_line) != null) {
    //                     if (fragment_intersection_line.start.y < ray_y) {
    //                         // curve passing top to bottom
    //                         boundary_fragment.winding -= 1;
    //                     } else if (fragment_intersection_line.start.y > ray_y) {
    //                         // curve passing bottom to top
    //                         boundary_fragment.winding += 1;
    //                     } else if (fragment_intersection_line.end.y < ray_y) {
    //                         // curve passing top to bottom, starting on ray
    //                         boundary_fragment.winding -= 0.5;
    //                     } else if (fragment_intersection_line.end.y > ray_y) {
    //                         // curve passing bottom to top, starting on ray
    //                         boundary_fragment.winding += 0.5;
    //                     } else {
    //                         // shouldn't happend, parallel lines
    //                         unreachable;
    //                     }
    //                 }
    //                 index += 1;

    //                 if (index < fragment_intersections.len) {
    //                     fragment_intersection = &fragment_intersections[index];
    //                     end_index = index;
    //                 }
    //                 previous_boundary_fragment = boundary_fragment.*;
    //             }

    //             // // for each fragment intersection, you can
    //             // // - calculalate the bitmask for Mv and Mh and store it in the FragmentIntersection

    //             // // var bitmask: u16 = 0;
    //             // var samples: [16]i8 = [_]i8{0} ** 16;
    //             // if (end_index > start_index) {
    //             //     for (fragment_intersections[start_index .. end_index - 1]) |fi| {
    //             //         for (0..16) |sample_index| {
    //             //             const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(sample_index));
    //             //             const main_ray: i8 = @intFromFloat(boundary_fragment.winding);
    //             //             const horizontal_ray: i8 = fi.horizontal_sign * @intFromBool((fi.horizontal_mask & bit_index) != 0);
    //             //             const vertical_ray: i8 = fi.vertical_sign * @intFromBool((fi.vertical_mask & bit_index) != 0);
    //             //             samples[sample_index] += main_ray + horizontal_ray + vertical_ray;
    //             //         }
    //             //     }
    //             // }

    //             // var mask: u16 = 0;
    //             // for (0..16) |sample_index| {
    //             //     const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(sample_index));
    //             //     if (samples[sample_index] != 0) {
    //             //         mask |= bit_index;
    //             //     }
    //             // }

    //             // boundary_fragment.bitmask = mask;
    //         }
    //     }

    //     return boundary_fragments;
    // }

    fn scanX(
        raster_data: *RasterData,
        grid_x: f32,
        curve: Curve,
        scaled_curve_bounds: RectF32,
    ) !void {
        var scaled_intersections_result: [3]Intersection = [_]Intersection{undefined} ** 3;
        const line = Line.create(
            PointF32{
                .x = grid_x,
                .y = scaled_curve_bounds.min.y - 1.0,
            },
            PointF32{
                .x = grid_x,
                .y = scaled_curve_bounds.max.y + 1.0,
            },
        );
        const scaled_intersections = curve.intersectVerticalLine(line, &scaled_intersections_result);

        for (scaled_intersections) |intersection| {
            const ao = try raster_data.addPixelIntersection();
            ao.* = PixelIntersection.create(intersection);
        }
    }

    fn scanY(
        raster_data: *RasterData,
        grid_y: f32,
        curve: Curve,
        scaled_curve_bounds: RectF32,
    ) !void {
        var scaled_intersections_result: [3]Intersection = [_]Intersection{undefined} ** 3;
        const line = Line.create(
            PointF32{
                .x = scaled_curve_bounds.min.x - 1.0,
                .y = grid_y,
            },
            PointF32{
                .x = scaled_curve_bounds.max.x + 1.0,
                .y = grid_y,
            },
        );
        const scaled_intersections = curve.intersectHorizontalLine(line, &scaled_intersections_result);

        for (scaled_intersections) |intersection| {
            const ao = try raster_data.addPixelIntersection();
            ao.* = PixelIntersection.create(intersection);
        }
    }
};

// test "raster intersections" {
//     const test_util = @import("./test_util.zig");
//     const pen_module = @import("./pen.zig");
//     const UnmanagedTextureRgba = texture_module.UnmanagedTextureRgba;

//     var pen = try pen_module.Pen.init(std.testing.allocator);
//     defer pen.deinit();

//     try pen.moveTo(PointF32{
//         .x = 0.2,
//         .y = 0.2,
//     });
//     try pen.lineTo(PointF32{
//         .x = 0.2,
//         .y = 0.8,
//     });
//     try pen.quadTo(PointF32{
//         .x = 0.2,
//         .y = 0.2,
//     }, PointF32{
//         .x = 0.6,
//         .y = 0.5,
//     });

//     var path = try pen.createPathAlloc(std.testing.allocator);
//     defer path.deinit();

//     const size: u32 = 5;
//     const dimensions = core.DimensionsU32{
//         .width = size,
//         .height = size,
//     };

//     var texture = try UnmanagedTextureRgba.create(std.testing.allocator, dimensions);
//     defer texture.deinit(std.testing.allocator);
//     var texture_view = texture.createView(core.RectU32{
//         .min = core.PointU32{
//             .x = 0,
//             .y = 0,
//         },
//         .max = core.PointU32{
//             .x = dimensions.width,
//             .y = dimensions.height,
//         },
//     }).?;

//     const path_intersections = try Raster.createIntersections(std.testing.allocator, path, &texture_view);
//     defer path_intersections.deinit();

//     // std.debug.print("Intersections:\n", .{});
//     // for (path_intersections.items) |intersection| {
//     //     std.debug.print("{}\n", .{intersection});
//     // }

//     try test_util.expectPathIntersectionsContains(PathIntersection{
//         .shape_index = 0,
//         .curve_index = 0,
//         .is_end = false,
//         .intersection = Intersection{
//             .t = 0.0,
//             .point = PointF32{
//                 .x = 1.0,
//                 .y = 4.0,
//             },
//         },
//     }, path_intersections.items, 0.0);

//     try test_util.expectPathIntersectionsContains(PathIntersection{
//         .shape_index = 0,
//         .curve_index = 0,
//         .is_end = false,
//         .intersection = Intersection{
//             .t = 0.3333333,
//             .point = PointF32{
//                 .x = 1.0,
//                 .y = 3.0,
//             },
//         },
//     }, path_intersections.items, test_util.DEFAULT_TOLERANCE);

//     try test_util.expectPathIntersectionsContains(PathIntersection{
//         .shape_index = 0,
//         .curve_index = 0,
//         .is_end = false,
//         .intersection = Intersection{
//             .t = 0.6666666,
//             .point = PointF32{
//                 .x = 1.0,
//                 .y = 2.0,
//             },
//         },
//     }, path_intersections.items, test_util.DEFAULT_TOLERANCE);

//     try test_util.expectPathIntersectionsContains(PathIntersection{
//         .shape_index = 0,
//         .curve_index = 0,
//         .is_end = false,
//         .intersection = Intersection{
//             .t = 1.0,
//             .point = PointF32{
//                 .x = 1.0,
//                 .y = 1.0,
//             },
//         },
//     }, path_intersections.items, 0.0);
// }
