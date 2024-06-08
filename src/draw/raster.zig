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

pub const ShapeRecord = struct {
    curve_fragment_offsets: RangeU32 = RangeU32{},
    boundary_fragment_offsets: RangeU32 = RangeU32{},
};

pub const CurveRecord = struct {
    pixel_intersection_offests: RangeU32 = RangeU32{},
};

pub const RasterData = struct {
    const ShapeRecordList = std.ArrayListUnmanaged(ShapeRecord);
    const CurveRecordList = std.ArrayListUnmanaged(CurveRecord);
    const PixelIntersectionList = std.ArrayListUnmanaged(PixelIntersection);
    const CurveFragmentList = std.ArrayListUnmanaged(CurveFragment);
    const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);

    allocator: Allocator,
    path: *const Path,
    view: *TextureViewRgba,
    shape_records: ShapeRecordList = ShapeRecordList{},
    curve_records: CurveRecordList = CurveRecordList{},
    pixel_intersections: PixelIntersectionList = PixelIntersectionList{},
    curve_fragments: CurveFragmentList = CurveFragmentList{},
    boundary_fragments: BoundaryFragmentList = BoundaryFragmentList{},

    pub fn init(allocator: Allocator, path: *const Path, view: *TextureViewRgba) RasterData {
        return RasterData{
            .allocator = allocator,
            .path = path,
            .view = view,
        };
    }

    pub fn deinit(self: *RasterData) void {
        self.shape_records.deinit(self.allocator);
        self.curve_records.deinit(self.allocator);
        self.pixel_intersections.deinit(self.allocator);
        self.curve_fragments.deinit(self.allocator);
        self.boundary_fragments.deinit(self.allocator);
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

    pub fn getShapeRecords(self: *RasterData) []ShapeRecord {
        return self.shape_records.items;
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

    pub fn getCurveFragments(self: *RasterData) []CurveFragment {
        return self.curve_fragments.items;
    }

    pub fn getBoundaryFragments(self: *RasterData) []BoundaryFragment {
        return self.boundary_fragments.items;
    }

    pub fn addShapeRecord(self: *RasterData) !*ShapeRecord {
        return try self.shape_records.addOne(self.allocator);
    }

    pub fn addCurveRecord(self: *RasterData) !*CurveRecord {
        return try self.curve_records.addOne(self.allocator);
    }

    pub fn addPixelIntersection(self: *RasterData) !*PixelIntersection {
        return try self.pixel_intersections.addOne(self.allocator);
    }

    pub fn addCurveFragment(self: *RasterData) !*CurveFragment {
        return try self.curve_fragments.addOne(self.allocator);
    }

    pub fn addBoundaryFragment(self: *RasterData) !*BoundaryFragment {
        return try self.boundary_fragments.addOne(self.allocator);
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

pub const CurveFragment = struct {
    pub const Masks = struct {
        vertical_mask: u16 = 0,
        vertical_sign: i2 = 0,
        horizontal_mask: u16 = 0,
        horizontal_sign: i2 = 0,
    };

    pixel: PointI32,
    intersections: [2]Intersection,

    pub fn create(pixel_intersections: [2]*const PixelIntersection) CurveFragment {
        const pixel = pixel_intersections[0].getPixel().min(pixel_intersections[1].getPixel());

        // can move diagonally, but cannot move by more than 1 pixel in both directions
        std.debug.assert(@abs(pixel.sub(pixel_intersections[0].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(pixel_intersections[0].pixel).y) <= 1);
        std.debug.assert(@abs(pixel.sub(pixel_intersections[1].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(pixel_intersections[1].pixel).y) <= 1);

        const intersections: [2]Intersection = [2]Intersection{
            Intersection{
                // retain t
                .t = pixel_intersections[0].getT(),
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = @abs(pixel_intersections[0].getPoint().x - @as(f32, @floatFromInt(pixel.x))),
                    .y = @abs(pixel_intersections[0].getPoint().y - @as(f32, @floatFromInt(pixel.y))),
                },
            },
            Intersection{
                // retain t
                .t = pixel_intersections[1].getT(),
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = @abs(pixel_intersections[1].getPoint().x - @as(f32, @floatFromInt(pixel.x))),
                    .y = @abs(pixel_intersections[1].getPoint().y - @as(f32, @floatFromInt(pixel.y))),
                },
            },
        };

        std.debug.assert(intersections[0].point.x <= 1.0);
        std.debug.assert(intersections[0].point.y <= 1.0);
        std.debug.assert(intersections[1].point.x <= 1.0);
        std.debug.assert(intersections[1].point.y <= 1.0);
        return CurveFragment{
            .pixel = pixel,
            .intersections = intersections,
        };
    }

    pub fn calculateMasks(self: CurveFragment, half_planes: HalfPlanesU16) Masks {
        var masks = Masks{};
        if (self.intersections[0].point.x == 0.0 and self.intersections[1].point.x != 0.0) {
            masks.vertical_mask = half_planes.getVerticalMask(self.intersections[0].point.y);

            if (self.intersections[0].point.y < 0.5) {
                masks.vertical_sign = -1;
            } else {
                masks.vertical_sign = 1;
            }
        } else if (self.intersections[1].point.x == 0.0 and self.intersections[0].point.x != 0.0) {
            masks.vertical_mask = half_planes.getVerticalMask(self.intersections[1].point.y);

            if (self.intersections[1].point.y < 0.5) {
                masks.vertical_sign = 1;
            } else {
                masks.vertical_sign = -1;
            }
        }

        masks.horizontal_mask = half_planes.getHorizontalMask(self.getLine());
        if (self.intersections[0].point.y > self.intersections[1].point.y) {
            // crossing top to bottom
            masks.horizontal_sign = 1;
        } else if (self.intersections[0].point.y < self.intersections[1].point.y) {
            masks.horizontal_sign = -1;
        }

        return masks;
    }

    pub fn getLine(self: CurveFragment) Line {
        return Line.create(self.intersections[0].point, self.intersections[1].point);
    }
};

pub const BoundaryFragment = struct {
    pixel: PointI32,
    main_ray_winding: i8 = 0,
    winding: [16]i8 = [_]i8{0} ** 16,
    stencil_mask: u16 = 0,
    curve_fragment_offsets: RangeU32 = RangeU32{},
};

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
        try self.populateCurveFragments(&raster_data);
        // try self.populateBoundaryFragments(&raster_data);

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

    pub fn populateCurveFragments(self: *@This(), raster_data: *RasterData) !void {
        _ = self;

        for (raster_data.getShapes(), 0..) |shape, shape_index| {
            var curve_fragment_offsets = RangeU32{
                .start = @intCast(raster_data.getCurveFragments().len),
            };
            // curve fragments are unique to curve
            for (raster_data.getCurveRecords()[shape.curve_offsets.start..shape.curve_offsets.end], 0..) |curve_record, curve_index| {
                std.debug.print("{}{}\n", .{shape_index, curve_index});
                const pixel_intersections = raster_data.getPixelIntersections()[curve_record.pixel_intersection_offests.start..curve_record.pixel_intersection_offests.end];
                std.debug.assert(pixel_intersections.len > 0);

                var previous_pixel_intersection: *PixelIntersection = &pixel_intersections[0];
                for (pixel_intersections) |*pixel_intersection| {
                    if (std.meta.eql(previous_pixel_intersection.getPoint(), pixel_intersection.getPoint())) {
                        // skip if exactly the same point
                        continue;
                    }

                    const ao = try raster_data.addCurveFragment();
                    ao.* = CurveFragment.create([_]*const PixelIntersection{ previous_pixel_intersection, pixel_intersection });
                    std.debug.assert(ao.intersections[0].t < ao.intersections[1].t);

                    previous_pixel_intersection = pixel_intersection;
                }
            }

            curve_fragment_offsets.end = @intCast(raster_data.getCurveFragments().len);
            (try raster_data.addShapeRecord()).* = ShapeRecord{
                .curve_fragment_offsets = curve_fragment_offsets,
            };

            // for each shape, sort the curve fragments by pixel y, x
            std.mem.sort(
                CurveFragment,
                raster_data.getCurveFragments()[curve_fragment_offsets.start..curve_fragment_offsets.end],
                @as(u32, 0),
                curveFragmentLessThan,
            );
        }
    }

    fn curveFragmentLessThan(_: u32, left: CurveFragment, right: CurveFragment) bool {
        if (left.pixel.y < right.pixel.y) {
            return true;
        } else if (left.pixel.y > right.pixel.y) {
            return false;
        } else if (left.pixel.x < right.pixel.x) {
            return true;
        } else {
            return false;
        }
    }

    pub fn populateBoundaryFragments(self: *Raster, raster_data: *RasterData) !void {
        for (raster_data.getShapeRecords()) |*shape_record| {
            const first_curve_fragment = &raster_data.getCurveFragments()[shape_record.curve_fragment_offsets.start];
            var boundary_fragment: *BoundaryFragment = try raster_data.addBoundaryFragment();
            boundary_fragment.* = BoundaryFragment{
                .pixel = first_curve_fragment.pixel,
            };
            var boundary_fragment_offsets = RangeU32{
                .start = @intCast(raster_data.getBoundaryFragments().len),
                .end = @intCast(raster_data.getBoundaryFragments().len),
            };
            var curve_fragment_offsets = RangeU32{
                .start = shape_record.curve_fragment_offsets.start,
            };
            const main_ray = Line.create(PointF32{
                .x = 0.0,
                .y = 0.5,
            }, PointF32{
                .x = 1.0,
                .y = 0.5,
            });
            var main_ray_winding: f32 = 0.0;

            const curve_fragments = raster_data.getCurveFragments()[shape_record.curve_fragment_offsets.start..shape_record.curve_fragment_offsets.end];
            for (curve_fragments, 0..) |curve_fragment, curve_fragment_index| {
                if (curve_fragment.pixel.x != boundary_fragment.pixel.x or curve_fragment.pixel.y != boundary_fragment.pixel.y) {
                    std.debug.assert(std.math.modf(main_ray_winding).fpart == 0.0);
                    curve_fragment_offsets.end = @intCast(shape_record.curve_fragment_offsets.start + curve_fragment_index);
                    boundary_fragment.curve_fragment_offsets = curve_fragment_offsets;
                    boundary_fragment.main_ray_winding = @intFromFloat(main_ray_winding);
                    boundary_fragment = try raster_data.addBoundaryFragment();
                    curve_fragment_offsets.start = curve_fragment_offsets.end;
                    main_ray_winding = 0.0;
                    boundary_fragment.* = BoundaryFragment{
                        .pixel = curve_fragment.pixel,
                    };
                }

                if (curve_fragment.getLine().intersectHorizontalLine(main_ray) != null) {
                    // curve fragment line cannot be horizontal, so intersection1.y != intersection2.y

                    var winding: f32 = 0.0;

                    if (curve_fragment.intersections[0].point.y > curve_fragment.intersections[1].point.y) {
                        winding = 1.0;
                    } else if (curve_fragment.intersections[0].point.y < curve_fragment.intersections[1].point.y) {
                        winding = -1.0;
                    }

                    if (curve_fragment.intersections[0].point.y == 0.5 or curve_fragment.intersections[1].point.y == 0.5) {
                        winding *= 0.5;
                    }

                    main_ray_winding += winding;
                }
            }

            boundary_fragment_offsets.end = @intCast(raster_data.getBoundaryFragments().len);
            shape_record.boundary_fragment_offsets = boundary_fragment_offsets;
        }

        for (raster_data.getShapeRecords()) |shape_record| {
            const boundary_fragments = raster_data.getBoundaryFragments()[shape_record.boundary_fragment_offsets.start..shape_record.boundary_fragment_offsets.end];
            for (boundary_fragments) |*boundary_fragment| {
                const curve_fragments = raster_data.getCurveFragments()[boundary_fragment.curve_fragment_offsets.start..boundary_fragment.curve_fragment_offsets.end];
                for (curve_fragments) |curve_fragment| {
                    const masks = curve_fragment.calculateMasks(self.half_planes);
                    const vertical_sign: i8 = @intCast(masks.vertical_sign);
                    const horizontal_sign: i8 = @intCast(masks.horizontal_sign);
                    for (0..16) |index| {
                        const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
                        const vertical_winding: i8 = vertical_sign * @as(i8, @intFromBool(masks.vertical_mask & bit_index != 0));
                        const horizontal_winding: i8 = horizontal_sign * @as(i8, @intFromBool(masks.horizontal_mask & bit_index != 0));
                        boundary_fragment.winding[index] = boundary_fragment.main_ray_winding + vertical_winding + horizontal_winding;
                    }
                }

                for (0..16) |index| {
                    const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
                    boundary_fragment.stencil_mask = boundary_fragment.stencil_mask | (@as(u16, @intFromBool(boundary_fragment.winding[index] != 0.0)) * bit_index);
                }
            }
        }
    }

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
