const std = @import("std");
const path_module = @import("./path.zig");
const curve_module = @import("./curve.zig");
const core = @import("../core/root.zig");
const msaa = @import("./msaa.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Paths = path_module.Paths;
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
const HalfPlanesU16 = msaa.HalfPlanesU16;

pub const GridIntersectionsRecord = struct {
    offsets: RangeU32 = RangeU32{},
};

pub const RasterData = struct {
    const GridIntersectionsRecordList = std.ArrayListUnmanaged(GridIntersectionsRecord);
    const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
    const CurveFragmentList = std.ArrayListUnmanaged(CurveFragment);
    const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);
    const SpanList = std.ArrayListUnmanaged(Span);

    allocator: Allocator,
    paths: *const Paths,
    path_index: u32,
    grid_intersections_records: GridIntersectionsRecordList = GridIntersectionsRecordList{},
    grid_intersections: GridIntersectionList = GridIntersectionList{},
    curve_fragments: CurveFragmentList = CurveFragmentList{},
    boundary_fragments: BoundaryFragmentList = BoundaryFragmentList{},
    spans: SpanList = SpanList{},

    pub fn init(allocator: Allocator, paths: *const Paths, path_index: u32) RasterData {
        return RasterData{
            .allocator = allocator,
            .paths = paths,
            .path_index = path_index,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.grid_intersections_records.deinit(self.allocator);
        self.grid_intersections.deinit(self.allocator);
        self.curve_fragments.deinit(self.allocator);
        self.boundary_fragments.deinit(self.allocator);
        self.spans.deinit(self.allocator);
    }

    pub fn getPaths(self: RasterData) *const Paths {
        return self.paths;
    }

    pub fn getPathIndex(self: RasterData) u32 {
        return self.path_index;
    }

    pub fn getGridIntersectionsRecords(self: *RasterData) []GridIntersectionsRecord {
        return self.grid_intersections_records.items;
    }

    pub fn getGridIntersections(self: *RasterData) []GridIntersection {
        return self.grid_intersections.items;
    }

    pub fn getCurveFragments(self: *RasterData) []CurveFragment {
        return self.curve_fragments.items;
    }

    pub fn getBoundaryFragments(self: @This()) []BoundaryFragment {
        return self.boundary_fragments.items;
    }

    pub fn getSpans(self: @This()) []Span {
        return self.spans.items;
    }

    pub fn addGridIntersectionsRecords(self: *RasterData) !*GridIntersectionsRecord {
        return try self.grid_intersections_records.addOne(self.allocator);
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
    pub const GridLine = enum {
        x,
        y,
        virtual,
    };

    curve_index: u32,
    intersection: Intersection,
    pixel: PointI32,
    grid_line: GridLine,

    pub fn create(curve_index: u32, intersection: Intersection, grid_line: GridLine) GridIntersection {
        return GridIntersection{
            .curve_index = curve_index,
            .intersection = intersection,
            .pixel = PointI32{
                .x = @intFromFloat(intersection.point.x),
                .y = @intFromFloat(intersection.point.y),
            },
            .grid_line = grid_line,
        };
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
    pub const MAIN_RAY: Line = Line.create(PointF32{
        .x = 0.0,
        .y = 0.5,
    }, PointF32{
        .x = 1.0,
        .y = 0.5,
    });

    pub const Masks = struct {
        vertical_mask0: u16 = 0,
        vertical_sign0: f32 = 0.0,
        vertical_mask1: u16 = 0,
        vertical_sign1: f32 = 0.0,
        horizontal_mask: u16 = 0,
        horizontal_sign: f32 = 0.0,

        pub fn debugPrint(self: Masks) void {
            std.debug.print("-----------\n", .{});
            std.debug.print("V0: {b:0>16}\n", .{self.vertical_mask0});
            std.debug.print("V0: {b:0>16}\n", .{self.vertical_mask1});
            std.debug.print(" H: {b:0>16}\n", .{self.horizontal_mask});
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
                    .x = std.math.clamp(@abs(grid_intersections[0].getPoint().x - @as(f32, @floatFromInt(pixel.x))), 0.0, 1.0),
                    .y = std.math.clamp(@abs(grid_intersections[0].getPoint().y - @as(f32, @floatFromInt(pixel.y))), 0.0, 1.0),
                },
            },
            Intersection{
                // retain t
                .t = grid_intersections[1].getT(),
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = std.math.clamp(@abs(grid_intersections[1].getPoint().x - @as(f32, @floatFromInt(pixel.x))), 0.0, 1.0),
                    .y = std.math.clamp(@abs(grid_intersections[1].getPoint().y - @as(f32, @floatFromInt(pixel.y))), 0.0, 1.0),
                },
            },
        };

        std.debug.assert(intersections[0].point.x <= 1.0);
        std.debug.assert(intersections[0].point.y <= 1.0);
        std.debug.assert(intersections[1].point.x <= 1.0);
        std.debug.assert(intersections[1].point.y <= 1.0);
        std.debug.assert(grid_intersections[0].curve_index <= grid_intersections[1].curve_index);
        return CurveFragment{
            .pixel = pixel,
            .intersections = intersections,
        };
    }

    pub fn calculateMasks(self: CurveFragment, half_planes: HalfPlanesU16) Masks {
        var masks = Masks{};
        if (self.intersections[0].point.x == 0.0 and self.intersections[1].point.x != 0.0) {
            const vertical_mask = half_planes.getVerticalMask(self.intersections[0].point.y);

            if (self.intersections[0].point.y < 0.5) {
                masks.vertical_mask0 = ~vertical_mask;
                masks.vertical_sign0 = -1;
            } else if (self.intersections[0].point.y > 0.5) {
                masks.vertical_mask0 = vertical_mask;
                masks.vertical_sign0 = 1;
            } else {
                // need two masks and two signs...
                masks.vertical_mask0 = vertical_mask; // > 0.5
                masks.vertical_sign0 = 0.5;
                masks.vertical_mask1 = ~vertical_mask; // < 0.5
                masks.vertical_sign1 = -0.5;
            }
        } else if (self.intersections[1].point.x == 0.0 and self.intersections[0].point.x != 0.0) {
            const vertical_mask = half_planes.getVerticalMask(self.intersections[1].point.y);

            if (self.intersections[1].point.y < 0.5) {
                masks.vertical_mask0 = ~vertical_mask;
                masks.vertical_sign0 = 1;
            } else if (self.intersections[1].point.y > 0.5) {
                masks.vertical_mask0 = vertical_mask;
                masks.vertical_sign0 = -1;
            } else {
                // need two masks and two signs...
                masks.vertical_mask0 = vertical_mask; // > 0.5
                masks.vertical_sign0 = -0.5;
                masks.vertical_mask1 = ~vertical_mask; // < 0.5
                masks.vertical_sign1 = 0.5;
            }
        }

        if (self.intersections[0].point.y > self.intersections[1].point.y) {
            // crossing top to bottom
            masks.horizontal_sign = 1;
        } else if (self.intersections[0].point.y < self.intersections[1].point.y) {
            masks.horizontal_sign = -1;
        }

        if (self.intersections[0].t > self.intersections[1].t) {
            masks.horizontal_sign *= -1;
            masks.vertical_sign0 *= -1;
            masks.vertical_sign1 *= -1;
        }

        masks.horizontal_mask = half_planes.getHorizontalMask(self.getLine());
        // std.debug.print("VerticalSign0({}), VerticalSign1({}), HorizontalSign({}), VMask0({b:0>16}), VMask1({b:0>16}), HMask({b:0>16})\n", .{
        //     masks.vertical_sign0,
        //     masks.vertical_sign1,
        //     masks.horizontal_sign,
        //     masks.vertical_mask0,
        //     masks.vertical_mask1,
        //     masks.horizontal_mask,
        // });

        return masks;
    }

    pub fn getLine(self: CurveFragment) Line {
        return Line.create(self.intersections[0].point, self.intersections[1].point);
    }

    pub fn calculateMainRayWinding(self: CurveFragment) f32 {
        if (self.getLine().intersectHorizontalLine(MAIN_RAY) != null) {
            // curve fragment line cannot be horizontal, so intersection1.y != intersection2.y

            var winding: f32 = 0.0;

            if (self.intersections[0].point.y > self.intersections[1].point.y) {
                winding = 1.0;
            } else if (self.intersections[0].point.y < self.intersections[1].point.y) {
                winding = -1.0;
            }

            if (self.intersections[0].point.y == 0.5 or self.intersections[1].point.y == 0.5) {
                winding *= 0.5;
            }

            return winding;
        }

        return 0.0;
    }
};

pub const BoundaryFragment = struct {
    pixel: PointI32,
    main_ray_winding: f32 = 0.0,
    winding: [16]f32 = [_]f32{0.0} ** 16,
    stencil_mask: u16 = 0,
    curve_fragment_offsets: RangeU32 = RangeU32{},

    pub fn getIntensity(self: BoundaryFragment) f32 {
        return @as(f32, @floatFromInt(@popCount(self.stencil_mask))) / 16.0;
    }
};

pub const Span = struct {
    y: i32 = 0,
    x_range: RangeI32 = RangeI32{},
};

pub const Rasterizer = struct {
    allocator: Allocator,
    half_planes: HalfPlanesU16,

    pub fn init(allocator: Allocator) !Rasterizer {
        return Rasterizer{
            .allocator = allocator,
            .half_planes = try HalfPlanesU16.create(allocator, &msaa.UV_SAMPLE_COUNT_16),
        };
    }

    pub fn deinit(self: *Rasterizer) void {
        self.half_planes.deinit();
    }

    pub fn rasterize(self: @This(), paths: Paths, path_index: u32) !RasterData {
        var raster_data = RasterData.init(self.allocator, &paths, path_index);
        errdefer raster_data.deinit();

        try self.populateGridIntersections(&raster_data);
        try self.populateCurveFragments(&raster_data);
        try self.populateBoundaryFragments(&raster_data);
        try self.populateSpans(&raster_data);

        return raster_data;
    }

    pub fn populateGridIntersections(self: @This(), raster_data: *RasterData) !void {
        _ = self;
        var monotonic_cuts: [2]Intersection = [_]Intersection{undefined} ** 2;

        const path = raster_data.paths.getPathRecords()[raster_data.path_index];
        const subpath_records = raster_data.paths.getSubpathRecords()[path.subpath_offsets.start..path.subpath_offsets.end];
        for (subpath_records) |subpath_record| {
            const curve_records = raster_data.paths.getCurveRecords()[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
            for (curve_records, 0..) |curve_record, curve_index_offset| {
                const curve_index: u32 = @intCast(subpath_record.curve_offsets.start + curve_index_offset);
                var grid_intersection_offsets = RangeU32{
                    .start = @intCast(raster_data.getGridIntersections().len),
                    .end = @intCast(raster_data.getGridIntersections().len),
                };
                const curve = raster_data.paths.getCurve(curve_record);
                const curve_bounds = curve.getBounds();

                // first virtual intersection
                (try raster_data.addGridIntersection()).* = GridIntersection.create(
                    curve_index,
                    Intersection{
                        .t = 0.0,
                        .point = curve.applyT(0.0),
                    },
                    .virtual,
                );

                // scan x lines within bounds
                const grid_x_size: usize = @intFromFloat(@ceil(curve_bounds.getWidth()));
                const grid_x_start: i32 = @intFromFloat(curve_bounds.min.x);
                for (0..grid_x_size + 1) |x_offset| {
                    const grid_x = grid_x_start + @as(i32, @intCast(x_offset));
                    try scanX(
                        curve_index,
                        raster_data,
                        @as(f32, @floatFromInt(grid_x)),
                        curve,
                        curve_bounds,
                    );
                }

                // scan y lines within bounds
                const grid_y_size: usize = @intFromFloat(@ceil(curve_bounds.getHeight()));
                const grid_y_start: i32 = @intFromFloat(curve_bounds.min.y);
                for (0..grid_y_size + 1) |y_offset| {
                    const grid_y = grid_y_start + @as(i32, @intCast(y_offset));
                    try scanY(
                        curve_index,
                        raster_data,
                        @as(f32, @floatFromInt(grid_y)),
                        curve,
                        curve_bounds,
                    );
                }

                // insert monotonic cuts, which ensure curves are monotonic within a pixel
                for (curve.monotonicCuts(&monotonic_cuts)) |intersection| {
                    const ao = try raster_data.addGridIntersection();
                    ao.* = GridIntersection.create(curve_index, intersection, .virtual);
                }

                // last virtual intersection
                (try raster_data.addGridIntersection()).* = GridIntersection.create(
                    curve_index,
                    Intersection{
                        .t = 1.0,
                        .point = curve.applyT(1.0),
                    },
                    .virtual,
                );

                grid_intersection_offsets.end = @intCast(raster_data.getGridIntersections().len);

                // sort by t within a curve
                const grid_intersections = raster_data.getGridIntersections()[grid_intersection_offsets.start..grid_intersection_offsets.end];
                std.mem.sort(
                    GridIntersection,
                    grid_intersections,
                    @as(u32, 0),
                    pixelIntersectionLessThan,
                );

                for (grid_intersections) |grid_intersection| {
                    std.debug.assert(grid_intersection.pixel.x >= 0);
                    std.debug.assert(grid_intersection.pixel.y >= 0);
                }

                // add curve record with offsets
                (try raster_data.addGridIntersectionsRecords()).* = GridIntersectionsRecord{
                    .offsets = grid_intersection_offsets,
                };
            }
        }
    }

    fn pixelIntersectionLessThan(_: u32, left: GridIntersection, right: GridIntersection) bool {
        if (left.curve_index < right.curve_index) {
            return true;
        } else if (left.curve_index > right.curve_index) {
            return false;
        } else if (left.getT() < right.getT()) {
            return true;
        } else if (left.getT() > right.getT()) {
            return false;
        } else if (left.grid_line != .virtual and right.grid_line == .virtual) {
            return true;
        }

        return false;
    }

    pub fn populateCurveFragments(self: @This(), raster_data: *RasterData) !void {
        _ = self;

        const path = raster_data.paths.getPathRecords()[raster_data.path_index];
        const subpath_records = raster_data.paths.getSubpathRecords()[path.subpath_offsets.start..path.subpath_offsets.end];
        for (subpath_records) |subpath_record| {
            // curve fragments are unique to curve
            const grid_intersections_records = raster_data.getGridIntersectionsRecords()[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
            for (grid_intersections_records) |grid_intersections_record| {
                const grid_intersections = raster_data.getGridIntersections()[grid_intersections_record.offsets.start..grid_intersections_record.offsets.end];
                std.debug.assert(grid_intersections.len > 0);

                var previous_grid_intersection: *GridIntersection = &grid_intersections[0];
                for (grid_intersections) |*grid_intersection| {
                    if (previous_grid_intersection.getT() == grid_intersection.getT()) {
                        if (previous_grid_intersection.grid_line == .x) {
                            grid_intersection.intersection.point.x = previous_grid_intersection.intersection.point.x;
                        } else if (previous_grid_intersection.grid_line == .y) {
                            grid_intersection.intersection.point.x = previous_grid_intersection.intersection.point.x;
                        }

                        if (grid_intersection.grid_line == .x) {
                            previous_grid_intersection.intersection.point.x = grid_intersection.intersection.point.x;
                        } else if (grid_intersection.grid_line == .y) {
                            previous_grid_intersection.intersection.point.x = grid_intersection.intersection.point.x;
                        }

                        continue;
                    }

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

        for (raster_data.getCurveFragments()) |curve_fragment| {
            std.debug.assert(curve_fragment.pixel.x >= 0);
            std.debug.assert(curve_fragment.pixel.y >= 0);
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
        } else if (left.pixel.x > right.pixel.x) {
            return false;
        } else {
            return false;
        }
    }

    pub fn populateBoundaryFragments(self: @This(), raster_data: *RasterData) !void {
        {
            const first_curve_fragment = &raster_data.getCurveFragments()[0];
            var boundary_fragment: *BoundaryFragment = try raster_data.addBoundaryFragment();
            boundary_fragment.* = BoundaryFragment{
                .pixel = first_curve_fragment.pixel,
            };
            var curve_fragment_offsets = RangeU32{};
            var main_ray_winding: f32 = 0.0;

            const curve_fragments = raster_data.getCurveFragments();
            for (curve_fragments, 0..) |*curve_fragment, curve_fragment_index| {
                const y_changing = curve_fragment.pixel.y != boundary_fragment.pixel.y;
                if (curve_fragment.pixel.x != boundary_fragment.pixel.x or curve_fragment.pixel.y != boundary_fragment.pixel.y) {
                    curve_fragment_offsets.end = @intCast(curve_fragment_index);
                    boundary_fragment.curve_fragment_offsets = curve_fragment_offsets;
                    boundary_fragment = try raster_data.addBoundaryFragment();
                    curve_fragment_offsets.start = curve_fragment_offsets.end;
                    boundary_fragment.* = BoundaryFragment{
                        .pixel = curve_fragment.pixel,
                    };
                    std.debug.assert(boundary_fragment.pixel.x >= 0);
                    std.debug.assert(boundary_fragment.pixel.y >= 0);
                    boundary_fragment.main_ray_winding = main_ray_winding;

                    if (y_changing) {
                        main_ray_winding = 0.0;
                    }
                }

                main_ray_winding += curve_fragment.calculateMainRayWinding();
            }
        }

        {
            const boundary_fragments = raster_data.getBoundaryFragments();
            for (boundary_fragments) |*boundary_fragment| {
                const curve_fragments = raster_data.getCurveFragments()[boundary_fragment.curve_fragment_offsets.start..boundary_fragment.curve_fragment_offsets.end];

                for (0..16) |index| {
                    boundary_fragment.winding[index] += boundary_fragment.main_ray_winding;
                }

                for (curve_fragments) |curve_fragment| {
                    // if (curve_fragment.pixel.x == 193 and curve_fragment.pixel.y == 167) {
                    //     std.debug.print("\nHEY MainRay({})\n", .{boundary_fragment.main_ray_winding});
                    // }
                    const masks = curve_fragment.calculateMasks(self.half_planes);
                    for (0..16) |index| {
                        const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
                        const vertical_winding0 = masks.vertical_sign0 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask0 & bit_index != 0)));
                        const vertical_winding1 = masks.vertical_sign1 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask1 & bit_index != 0)));
                        const horizontal_winding = masks.horizontal_sign * @as(f32, @floatFromInt(@intFromBool(masks.horizontal_mask & bit_index != 0)));
                        boundary_fragment.winding[index] += vertical_winding0 + vertical_winding1 + horizontal_winding;
                    }
                }

                for (0..16) |index| {
                    const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
                    boundary_fragment.stencil_mask = boundary_fragment.stencil_mask | (@as(u16, @intFromBool(boundary_fragment.winding[index] != 0.0)) * bit_index);
                }

                // std.debug.print("BoundaryFragment({},{}), StencilMask({b:0>16})", .{
                //     boundary_fragment.pixel.x,
                //     boundary_fragment.pixel.y,
                //     boundary_fragment.stencil_mask,
                // });
            }
        }
    }

    pub fn populateSpans(self: @This(), raster_data: *RasterData) !void {
        _ = self;
        const boundary_fragments = raster_data.getBoundaryFragments();
        var previous_boundary_fragment: ?*BoundaryFragment = null;

        for (boundary_fragments) |*boundary_fragment| {
            if (previous_boundary_fragment) |pbf| {
                if (pbf.pixel.y == boundary_fragment.pixel.y and pbf.pixel.x != boundary_fragment.pixel.x - 1 and boundary_fragment.main_ray_winding != 0) {
                    const ao = try raster_data.addSpan();
                    ao.* = Span{
                        .y = boundary_fragment.pixel.y,
                        .x_range = RangeI32{
                            .start = pbf.pixel.x + 1,
                            .end = boundary_fragment.pixel.x,
                        },
                    };

                    std.debug.assert(ao.y >= 0);
                }
            }

            previous_boundary_fragment = boundary_fragment;
        }
    }

    fn scanX(
        curve_index: u32,
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
            ao.* = GridIntersection.create(curve_index, intersection, .x);
        }
    }

    fn scanY(
        curve_index: u32,
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
            ao.* = GridIntersection.create(curve_index, intersection, .y);
        }
    }
};
