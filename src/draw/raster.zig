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
const Subpath = curve_module.Subpath;
const Curve = curve_module.Curve;
const Line = curve_module.Line;
const Intersection = curve_module.Intersection;
const UnmanagedTexture = texture_module.UnmanagedTexture;
const HalfPlanesU16 = msaa.HalfPlanesU16;

pub const CurveRecord = struct {
    grid_intersection_offests: RangeU32 = RangeU32{},
};

pub const RasterData = struct {
    const CurveRecordList = std.ArrayListUnmanaged(CurveRecord);
    const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
    const CurveFragmentList = std.ArrayListUnmanaged(CurveFragment);
    const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);
    const SpanList = std.ArrayListUnmanaged(Span);

    allocator: Allocator,
    path: *const Path,
    view: *TextureViewRgba,
    curve_records: CurveRecordList = CurveRecordList{},
    grid_intersections: GridIntersectionList = GridIntersectionList{},
    curve_fragments: CurveFragmentList = CurveFragmentList{},
    boundary_fragments: BoundaryFragmentList = BoundaryFragmentList{},
    spans: SpanList = SpanList{},

    pub fn init(allocator: Allocator, path: *const Path, view: *TextureViewRgba) RasterData {
        return RasterData{
            .allocator = allocator,
            .path = path,
            .view = view,
        };
    }

    pub fn deinit(self: *RasterData) void {
        self.curve_records.deinit(self.allocator);
        self.grid_intersections.deinit(self.allocator);
        self.curve_fragments.deinit(self.allocator);
        self.boundary_fragments.deinit(self.allocator);
        self.spans.deinit(self.allocator);
    }

    pub fn getPath(self: RasterData) *const Path {
        return self.path;
    }

    pub fn getView(self: *RasterData) *TextureViewRgba {
        return self.view;
    }

    pub fn getSubpaths(self: RasterData) []const Subpath {
        return self.path.getSubpaths();
    }

    pub fn getCurves(self: RasterData) []const Curve {
        return self.path.getCurves();
    }

    pub fn getCurveRecords(self: *RasterData) []CurveRecord {
        return self.curve_records.items;
    }

    pub fn getGridIntersections(self: *RasterData) []GridIntersection {
        return self.grid_intersections.items;
    }

    pub fn getCurveFragments(self: *RasterData) []CurveFragment {
        return self.curve_fragments.items;
    }

    pub fn getBoundaryFragments(self: *RasterData) []BoundaryFragment {
        return self.boundary_fragments.items;
    }

    pub fn getSpans(self: *RasterData) []Span {
        return self.spans.items;
    }

    pub fn addCurveRecord(self: *RasterData) !*CurveRecord {
        return try self.curve_records.addOne(self.allocator);
    }

    pub fn addGridIntersection(self: *RasterData) !*GridIntersection {
        return try self.grid_intersections.addOne(self.allocator);
    }

    pub fn addCurveFragment(self: *RasterData) !*CurveFragment {
        return try self.curve_fragments.addOne(self.allocator);
    }

    pub fn addBoundaryFragment(self: *RasterData) !*BoundaryFragment {
        return try self.boundary_fragments.addOne(self.allocator);
    }

    pub fn addSpan(self: *RasterData) !*Span {
        return try self.spans.addOne(self.allocator);
    }
};

pub const GridIntersection = struct {
    intersection: Intersection,
    pixel: PointI32,

    pub fn create(intersection: Intersection) GridIntersection {
        return GridIntersection{ .intersection = intersection, .pixel = PointI32{
            .x = @intFromFloat(intersection.point.x),
            .y = @intFromFloat(intersection.point.y),
        } };
    }

    pub fn getT(self: GridIntersection) f32 {
        return self.intersection.t;
    }

    pub fn getPoint(self: GridIntersection) PointF32 {
        return self.intersection.point;
    }

    pub fn getPixel(self: GridIntersection) PointI32 {
        return self.pixel;
    }
};

pub const CurveFragment = struct {
    pub const Masks = struct {
        vertical_mask: u16 = 0,
        vertical_sign: i8 = 0,
        horizontal_mask: u16 = 0,
        horizontal_sign: i8 = 0,

        pub fn debugPrint(self: Masks) void {
            std.debug.print("-----------\n", .{});
            std.debug.print("V: {b:0>16}\n", .{self.vertical_mask});
            std.debug.print("H: {b:0>16}\n", .{self.horizontal_mask});
            std.debug.print("-----------\n", .{});
        }
    };

    pixel: PointI32,
    intersections: [2]Intersection,

    pub fn create(grid_intersections: [2]*const GridIntersection) CurveFragment {
        const pixel = grid_intersections[0].getPixel().min(grid_intersections[1].getPixel());

        // can move diagonally, but cannot move by more than 1 pixel in both directions
        std.debug.assert(@abs(pixel.sub(grid_intersections[0].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[0].pixel).y) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[1].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[1].pixel).y) <= 1);

        const intersections: [2]Intersection = [2]Intersection{
            Intersection{
                // retain t
                .t = grid_intersections[0].getT(),
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = @abs(grid_intersections[0].getPoint().x - @as(f32, @floatFromInt(pixel.x))),
                    .y = @abs(grid_intersections[0].getPoint().y - @as(f32, @floatFromInt(pixel.y))),
                },
            },
            Intersection{
                // retain t
                .t = grid_intersections[1].getT(),
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = @abs(grid_intersections[1].getPoint().x - @as(f32, @floatFromInt(pixel.x))),
                    .y = @abs(grid_intersections[1].getPoint().y - @as(f32, @floatFromInt(pixel.y))),
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
                masks.vertical_sign = 1;
            } else {
                masks.vertical_sign = -1;
            }
        } else if (self.intersections[1].point.x == 0.0 and self.intersections[0].point.x != 0.0) {
            masks.vertical_mask = half_planes.getVerticalMask(self.intersections[1].point.y);

            if (self.intersections[1].point.y < 0.5) {
                masks.vertical_sign = -1;
            } else {
                masks.vertical_sign = 1;
            }
        }

        if (self.intersections[0].point.y > self.intersections[1].point.y) {
            // crossing top to bottom
            masks.horizontal_sign = -1;
        } else if (self.intersections[0].point.y < self.intersections[1].point.y) {
            masks.horizontal_sign = 1;
        }

        if (self.intersections[0].t > self.intersections[1].t) {
            masks.horizontal_sign *= -1;
            masks.vertical_sign *= -1;
        }

        masks.horizontal_mask = half_planes.getHorizontalMask(self.getLine());
        std.debug.print("VerticalSign({}), HorizontalSign({}), VMask({b:0>16}), HMask({b:0>16})\n", .{
            masks.vertical_sign,
            masks.horizontal_sign,
            masks.vertical_mask,
            masks.horizontal_mask,
        });

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

    pub fn getIntensity(self: BoundaryFragment) f32 {
        return @as(f32, @floatFromInt(@popCount(self.stencil_mask))) / 16.0;
    }
};

pub const Span = struct {
    y: i32 = 0,
    x_range: RangeI32 = RangeI32{},
    winding: i8 = 0,
    filled: bool = false,
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

        try self.populateGridIntersections(&raster_data);
        try self.populateCurveFragments(&raster_data);
        try self.populateBoundaryFragments(&raster_data);

        return raster_data;
    }

    pub fn populateGridIntersections(self: *Raster, raster_data: *RasterData) !void {
        _ = self;
        var monotonic_cuts: [2]Intersection = [_]Intersection{undefined} ** 2;

        const pixel_view_dimensions = raster_data.getView().getDimensions();
        const scaled_pixel_dimensions = DimensionsF32{
            .width = @floatFromInt(pixel_view_dimensions.width),
            .height = @floatFromInt(pixel_view_dimensions.height),
        };

        for (raster_data.getSubpaths()) |subpath| {
            for (raster_data.getCurves()[subpath.curve_offsets.start..subpath.curve_offsets.end]) |curve| {
                var grid_intersection_offsets = RangeU32{
                    .start = @intCast(raster_data.getGridIntersections().len),
                    .end = @intCast(raster_data.getGridIntersections().len),
                };
                const scaled_curve = curve.invertY().scale(scaled_pixel_dimensions);
                const scaled_curve_bounds = scaled_curve.getBounds();

                // first virtual intersection
                (try raster_data.addGridIntersection()).* = GridIntersection.create(
                    Intersection{
                        .t = 0.0,
                        .point = scaled_curve.applyT(0.0),
                    },
                );

                // scan x lines within bounds
                const grid_x_size: usize = @intFromFloat(@ceil(scaled_curve_bounds.getWidth()));
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
                const grid_y_size: usize = @intFromFloat(@ceil(scaled_curve_bounds.getHeight()));
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
                    const ao = try raster_data.addGridIntersection();
                    ao.* = GridIntersection.create(intersection);
                }

                // last virtual intersection
                (try raster_data.addGridIntersection()).* = GridIntersection.create(Intersection{
                    .t = 1.0,
                    .point = scaled_curve.applyT(1.0),
                });

                grid_intersection_offsets.end = @intCast(raster_data.getGridIntersections().len);

                // sort by t within a curve
                std.mem.sort(
                    GridIntersection,
                    raster_data.getGridIntersections()[grid_intersection_offsets.start..grid_intersection_offsets.end],
                    @as(u32, 0),
                    pixelIntersectionLessThan,
                );

                // add curve record with offsets
                (try raster_data.addCurveRecord()).* = CurveRecord{
                    .grid_intersection_offests = grid_intersection_offsets,
                };
            }
        }
    }

    fn pixelIntersectionLessThan(_: u32, left: GridIntersection, right: GridIntersection) bool {
        if (left.getT() < right.getT()) {
            return true;
        }

        return false;
    }

    pub fn populateCurveFragments(self: *@This(), raster_data: *RasterData) !void {
        _ = self;

        for (raster_data.getSubpaths(), 0..) |subpath, subpath_index| {
            // curve fragments are unique to curve
            for (raster_data.getCurveRecords()[subpath.curve_offsets.start..subpath.curve_offsets.end], 0..) |curve_record, curve_index| {
                std.debug.print("{}{}\n", .{ subpath_index, curve_index });
                const grid_intersections = raster_data.getGridIntersections()[curve_record.grid_intersection_offests.start..curve_record.grid_intersection_offests.end];
                std.debug.assert(grid_intersections.len > 0);

                var previous_grid_intersection: *GridIntersection = &grid_intersections[0];
                for (grid_intersections) |*grid_intersection| {
                    if (std.meta.eql(previous_grid_intersection.getPoint(), grid_intersection.getPoint())) {
                        // skip if exactly the same point
                        previous_grid_intersection = grid_intersection;
                        continue;
                    }

                    {
                        const ao = try raster_data.addCurveFragment();
                        ao.* = CurveFragment.create([_]*const GridIntersection{ previous_grid_intersection, grid_intersection });
                        std.debug.assert(ao.intersections[0].t < ao.intersections[1].t);
                    }

                    previous_grid_intersection = grid_intersection;
                }
            }
        }

        // sort all curve fragments of all the subpaths by y ascending, x ascending
        std.mem.sort(
            CurveFragment,
            raster_data.getCurveFragments(),
            @as(u32, 0),
            curveFragmentLessThan,
        );
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
        {
            const first_curve_fragment = &raster_data.getCurveFragments()[0];
            var boundary_fragment: *BoundaryFragment = try raster_data.addBoundaryFragment();
            boundary_fragment.* = BoundaryFragment{
                .pixel = first_curve_fragment.pixel,
            };
            var curve_fragment_offsets = RangeU32{};
            const main_ray = Line.create(PointF32{
                .x = 0.0,
                .y = 0.5,
            }, PointF32{
                .x = 1.0,
                .y = 0.5,
            });
            var main_ray_winding: f32 = 0.0;

            const curve_fragments = raster_data.getCurveFragments();
            for (curve_fragments, 0..) |curve_fragment, curve_fragment_index| {
                if (curve_fragment.pixel.x != boundary_fragment.pixel.x or curve_fragment.pixel.y != boundary_fragment.pixel.y) {
                    std.debug.assert(std.math.modf(main_ray_winding).fpart == 0.0);
                    curve_fragment_offsets.end = @intCast(curve_fragment_index);
                    boundary_fragment.curve_fragment_offsets = curve_fragment_offsets;
                    boundary_fragment = try raster_data.addBoundaryFragment();
                    curve_fragment_offsets.start = curve_fragment_offsets.end;
                    boundary_fragment.* = BoundaryFragment{
                        .pixel = curve_fragment.pixel,
                    };

                    if (curve_fragment.pixel.y != boundary_fragment.pixel.y) {
                        main_ray_winding = 0.0;
                    } else {
                        boundary_fragment.main_ray_winding = @intFromFloat(main_ray_winding);
                    }
                }

                if (curve_fragment.getLine().intersectHorizontalLine(main_ray) != null) {
                    // curve fragment line cannot be horizontal, so intersection1.y != intersection2.y

                    var winding: f32 = 0.0;

                    if (curve_fragment.intersections[0].point.y > curve_fragment.intersections[1].point.y) {
                        winding = -1.0;
                    } else if (curve_fragment.intersections[0].point.y < curve_fragment.intersections[1].point.y) {
                        winding = 1.0;
                    }

                    if (curve_fragment.intersections[0].point.y == 0.5 or curve_fragment.intersections[1].point.y == 0.5) {
                        winding *= 0.5;
                    }

                    main_ray_winding += winding;
                }
            }
        }

        {
            const boundary_fragments = raster_data.getBoundaryFragments();
            var previous_boundary_fragment: ?*BoundaryFragment = null;
            for (boundary_fragments) |*boundary_fragment| {
                const curve_fragments = raster_data.getCurveFragments()[boundary_fragment.curve_fragment_offsets.start..boundary_fragment.curve_fragment_offsets.end];
                for (curve_fragments) |curve_fragment| {
                    if (curve_fragment.pixel.x == 136 and curve_fragment.pixel.y == 4) {
                        std.debug.print("HEY\n", .{});
                        std.debug.print("MainRay({}), PreviousMainRay({})\n", .{
                            boundary_fragment.main_ray_winding,
                            previous_boundary_fragment.?.main_ray_winding,
                        });
                    }
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

                if (previous_boundary_fragment) |pbf| {
                    if (pbf.pixel.y == boundary_fragment.pixel.y and pbf.pixel.x != boundary_fragment.pixel.x - 1) {
                        (try raster_data.addSpan()).* = Span{
                            .y = boundary_fragment.pixel.y,
                            .x_range = RangeI32{
                                .start = pbf.pixel.x + 1,
                                .end = boundary_fragment.pixel.x,
                            },
                            .winding = boundary_fragment.main_ray_winding,
                            .filled = boundary_fragment.main_ray_winding != 0,
                        };
                    }
                }

                previous_boundary_fragment = boundary_fragment;
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
            const ao = try raster_data.addGridIntersection();
            ao.* = GridIntersection.create(intersection);
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
            const ao = try raster_data.addGridIntersection();
            ao.* = GridIntersection.create(intersection);
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
//         .subpath_index = 0,
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
//         .subpath_index = 0,
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
//         .subpath_index = 0,
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
//         .subpath_index = 0,
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
