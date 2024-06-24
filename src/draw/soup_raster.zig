const std = @import("std");
const path_module = @import("./path.zig");
const curve_module = @import("./curve.zig");
const core = @import("../core/root.zig");
const msaa = @import("./msaa.zig");
const soup_module = @import("./soup.zig");
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
const Line = curve_module.Line;
const Intersection = curve_module.Intersection;
const HalfPlanesU16 = msaa.HalfPlanesU16;
const Soup = soup_module.Soup;

const PathRecord = struct {
    intersection_offsets: RangeU32 = RangeU32{},
    boundary_offsets: RangeU32 = RangeU32{},
    merge_offsets: RangeU32 = RangeU32{},
};

pub const Masks = struct {
    vertical_mask0: u16 = 0,
    vertical_sign0: f32 = 0.0,
    vertical_mask1: u16 = 0,
    vertical_sign1: f32 = 0.0,
    horizontal_mask: u16 = 0,
    horizontal_sign: f32 = 0.0,

    pub fn debugPrint(self: @This()) void {
        std.debug.print("-----------\n", .{});
        std.debug.print("V0: {b:0>16}\n", .{self.vertical_mask0});
        std.debug.print("V0: {b:0>16}\n", .{self.vertical_mask1});
        std.debug.print(" H: {b:0>16}\n", .{self.horizontal_mask});
        std.debug.print("-----------\n", .{});
    }
};

pub const BoundaryFragment = struct {
    pub const MAIN_RAY: Line = Line.create(PointF32{
        .x = 0.0,
        .y = 0.5,
    }, PointF32{
        .x = 1.0,
        .y = 0.5,
    });

    pixel: PointI32,
    intersections: [2]Intersection,

    pub fn create(grid_intersections: [2]*const GridIntersection) @This() {
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
        return @This(){
            .pixel = pixel,
            .intersections = intersections,
        };
    }

    pub fn calculateMasks(self: @This(), half_planes: HalfPlanesU16) Masks {
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

    pub fn getLine(self: @This()) Line {
        return Line.create(self.intersections[0].point, self.intersections[1].point);
    }

    pub fn calculateMainRayWinding(self: @This()) f32 {
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

pub const MergeFragment = struct {
    pixel: PointI32,
    main_ray_winding: f32 = 0.0,
    winding: [16]f32 = [_]f32{0.0} ** 16,
    stencil_mask: u16 = 0,
    boundary_offsets: RangeU32 = RangeU32{},

    pub fn getIntensity(self: @This()) f32 {
        return @as(f32, @floatFromInt(@popCount(self.stencil_mask))) / 16.0;
    }
};

pub const Span = struct {
    y: i32 = 0,
    x_range: RangeI32 = RangeI32{},
};

pub const GridIntersection = struct {
    pub const GridLine = enum {
        x,
        y,
        virtual,
    };

    intersection: Intersection,
    pixel: PointI32,
    grid_line: GridLine,

    pub fn create(intersection: Intersection, grid_line: GridLine) @This() {
        return @This(){
            .intersection = intersection,
            .pixel = PointI32{
                .x = @intFromFloat(intersection.point.x),
                .y = @intFromFloat(intersection.point.y),
            },
            .grid_line = grid_line,
        };
    }

    pub fn getT(self: @This()) f32 {
        return self.intersection.t;
    }

    pub fn getPoint(self: @This()) PointF32 {
        return self.intersection.point;
    }

    pub fn getPixel(self: @This()) PointI32 {
        return self.pixel;
    }
};

pub fn RasterData(comptime T: type) type {
    const S = Soup(T);

    return struct {
        const PathRecordList = std.ArrayListUnmanaged(PathRecord);
        const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
        const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);
        const MergeFragmentList = std.ArrayListUnmanaged(MergeFragment);
        const SpanList = std.ArrayListUnmanaged(Span);

        allocator: Allocator,
        soup: *const S,
        path_records: PathRecordList = PathRecordList{},
        grid_intersections: GridIntersectionList = GridIntersectionList{},
        boundary_fragments: BoundaryFragmentList = BoundaryFragmentList{},
        merge_fragments: MergeFragmentList = MergeFragmentList{},
        spans: SpanList = SpanList{},

        pub fn init(allocator: Allocator, soup: *const S) @This() {
            return @This(){
                .allocator = allocator,
                .soup = soup,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.path_records.deinit(self.allocator);
            self.grid_intersections.deinit(self.allocator);
            self.boundary_fragments.deinit(self.allocator);
            self.merge_fragments.deinit(self.allocator);
            self.spans.deinit(self.allocator);
        }

        pub fn getPathRecords(self: @This()) []const PathRecord {
            return self.path_records.items;
        }

        pub fn getGridIntersections(self: @This()) []const GridIntersection {
            return self.grid_intersections.items;
        }

        pub fn getBoundaryFragments(self: @This()) []const BoundaryFragment {
            return self.boundary_fragments.items;
        }

        pub fn getMergeFragments(self: @This()) []const MergeFragment {
            return self.merge_fragments.items;
        }

        pub fn getSpans(self: @This()) []Span {
            return self.spans.items;
        }

        pub fn getPathRecordUnsafe(self: *@This(), index: u32) *PathRecord {
            return self.path_records.items[index];
        }

        pub fn addPathRecord(self: *@This()) !*PathRecord {
            const path_record = try self.path_records.addOne(self.allocator);
            path_record.* = PathRecord{};
            return path_record;
        }

        pub fn openPathRecordIntersections(self: *@This(), path_record: *PathRecord) void {
            path_record.intersection_offsets.start = @intCast(self.grid_intersections.items.len);
        }

        pub fn openPathRecordBoundaries(self: *@This(), path_record: *PathRecord) void {
            path_record.boundary_offsets.start = @intCast(self.boundary_fragments.items.len);
        }

        pub fn openPathRecordMerges(self: *@This(), path_record: *PathRecord) void {
            path_record.merge_offsets.start = @intCast(self.merge_fragments.items.len);
        }

        pub fn closePathRecordIntersections(self: *@This(), path_record: *PathRecord) void {
            path_record.intersection_offsets.end = @intCast(self.grid_intersections.items.len);
        }

        pub fn closePathRecordBoundaries(self: *@This(), path_record: *PathRecord) void {
            path_record.boundary_offsets.end = @intCast(self.boundary_fragments.items.len);
        }

        pub fn closePathRecordMerges(self: *@This(), path_record: *PathRecord) void {
            path_record.merge_offsets.end = @intCast(self.merge_fragments.items.len);
        }

        pub fn addGridIntersection(self: *@This()) !*GridIntersection {
            return try self.grid_intersections.addOne(self.allocator);
        }

        pub fn addBoundaryFragment(self: *@This()) !*BoundaryFragment {
            return try self.boundary_fragments.addOne(self.allocator);
        }

        pub fn addMergeFragment(self: *@This()) !*MergeFragment {
            return try self.merge_fragments.addOne(self.allocator);
        }

        pub fn addSpan(self: *@This()) !*Span {
            return try self.spans.addOne(self.allocator);
        }
    };
}

pub fn SoupRasterizer(comptime T: type) type {
    const S = Soup(T);
    const RD = RasterData(T);

    return struct {
        half_planes: *const HalfPlanesU16,

        pub fn create(half_planes: *const HalfPlanesU16) @This() {
            return @This(){
                .half_planes = half_planes,
            };
        }

        pub fn rasterizeAlloc(self: @This(), allocator: Allocator, soup: S) !RD {
            var raster_data = RD.init(allocator, &soup);
            errdefer raster_data.deinit();

            for (raster_data.soup.getPathRecords()) |soup_path_record| {
                const path_record = try raster_data.addPathRecord();
                try self.populateGridIntersections(&raster_data, path_record, soup_path_record);
                try self.populateBoundaryFragments(&raster_data, path_record);
            }

            // try self.populateBoundaryFragments(&raster_data);
            // try self.populateCurveFragments(&raster_data);
            // try self.populateSpans(&raster_data);

            return raster_data;
        }

        pub fn populateGridIntersections(self: @This(), raster_data: *RD, path_record: *PathRecord, soup_path_record: S.PathRecord) !void {
            _ = self;

            raster_data.openPathRecordIntersections(path_record);

            const soup_subpath_records = raster_data.soup.getSubpathRecords()[soup_path_record.subpath_offsets.start..soup_path_record.subpath_offsets.end];
            for (soup_subpath_records) |soup_subpath_record| {
                const soup_items = raster_data.soup.getItems()[soup_subpath_record.item_offsets.start..soup_subpath_record.item_offsets.end];
                for (soup_items) |curve| {
                    const curve_bounds = curve.getBounds();
                    const start_intersection_index = raster_data.grid_intersections.items.len;

                    // first virtual intersection
                    (try raster_data.addGridIntersection()).* = GridIntersection.create(
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
                            raster_data,
                            @as(f32, @floatFromInt(grid_y)),
                            curve,
                            curve_bounds,
                        );
                    }

                    // last virtual intersection
                    (try raster_data.addGridIntersection()).* = GridIntersection.create(
                        Intersection{
                            .t = 1.0,
                            .point = curve.applyT(1.0),
                        },
                        .virtual,
                    );
                    const end_intersection_index = raster_data.grid_intersections.items.len;

                    const grid_intersections = raster_data.grid_intersections.items[start_intersection_index..end_intersection_index];

                    // need to sort by T unfortunately, maybe we can fix this to generate in order in the future
                    // TODO: can probably sort this as part of fragment generation
                    std.mem.sort(
                        GridIntersection,
                        grid_intersections,
                        @as(u32, 0),
                        gridIntersectionLessThan,
                    );
                }
            }

            raster_data.closePathRecordIntersections(path_record);
        }

        fn gridIntersectionLessThan(_: u32, left: GridIntersection, right: GridIntersection) bool {
            if (left.getT() < right.getT()) {
                return true;
            } else if (left.getT() > right.getT()) {
                return false;
            } else if (left.grid_line != .virtual and right.grid_line == .virtual) {
                return true;
            }

            return false;
        }

        pub fn populateBoundaryFragments(self: @This(), raster_data: *RD, path_record: *PathRecord) !void {
            _ = self;

            raster_data.openPathRecordBoundaries(path_record);

            const grid_intersections = raster_data.grid_intersections.items[path_record.intersection_offsets.start..path_record.intersection_offsets.end];
            std.debug.assert(grid_intersections.len > 0);

            var previous_grid_intersection: *GridIntersection = &grid_intersections[0];
            for (grid_intersections[1..]) |*grid_intersection| {
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
                    const ao = try raster_data.addBoundaryFragment();
                    ao.* = BoundaryFragment.create([_]*const GridIntersection{ previous_grid_intersection, grid_intersection });
                    std.debug.assert(ao.intersections[0].t < ao.intersections[1].t);
                }

                previous_grid_intersection = grid_intersection;
            }

            raster_data.closePathRecordBoundaries(path_record);

            const boundary_fragments = raster_data.boundary_fragments.items[path_record.boundary_offsets.start..path_record.boundary_offsets.end];
            // sort all curve fragments of all the subpaths by y ascending, x ascending
            std.mem.sort(
                BoundaryFragment,
                boundary_fragments,
                @as(u32, 0),
                boundaryFragmentLessThan,
            );
        }

        fn boundaryFragmentLessThan(_: u32, left: BoundaryFragment, right: BoundaryFragment) bool {
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

        // pub fn populateBoundaryFragments(self: @This(), raster_data: *RasterData) !void {
        //     {
        //         const first_curve_fragment = &raster_data.getCurveFragments()[0];
        //         var boundary_fragment: *BoundaryFragment = try raster_data.addBoundaryFragment();
        //         boundary_fragment.* = BoundaryFragment{
        //             .pixel = first_curve_fragment.pixel,
        //         };
        //         var curve_fragment_offsets = RangeU32{};
        //         var main_ray_winding: f32 = 0.0;

        //         const curve_fragments = raster_data.getCurveFragments();
        //         for (curve_fragments, 0..) |*curve_fragment, curve_fragment_index| {
        //             const y_changing = curve_fragment.pixel.y != boundary_fragment.pixel.y;
        //             if (curve_fragment.pixel.x != boundary_fragment.pixel.x or curve_fragment.pixel.y != boundary_fragment.pixel.y) {
        //                 curve_fragment_offsets.end = @intCast(curve_fragment_index);
        //                 boundary_fragment.curve_fragment_offsets = curve_fragment_offsets;
        //                 boundary_fragment = try raster_data.addBoundaryFragment();
        //                 curve_fragment_offsets.start = curve_fragment_offsets.end;
        //                 boundary_fragment.* = BoundaryFragment{
        //                     .pixel = curve_fragment.pixel,
        //                 };
        //                 std.debug.assert(boundary_fragment.pixel.x >= 0);
        //                 std.debug.assert(boundary_fragment.pixel.y >= 0);
        //                 boundary_fragment.main_ray_winding = main_ray_winding;

        //                 if (y_changing) {
        //                     main_ray_winding = 0.0;
        //                 }
        //             }

        //             main_ray_winding += curve_fragment.calculateMainRayWinding();
        //         }
        //     }

        //     {
        //         const boundary_fragments = raster_data.getBoundaryFragments();
        //         for (boundary_fragments) |*boundary_fragment| {
        //             const curve_fragments = raster_data.getCurveFragments()[boundary_fragment.curve_fragment_offsets.start..boundary_fragment.curve_fragment_offsets.end];

        //             for (0..16) |index| {
        //                 boundary_fragment.winding[index] += boundary_fragment.main_ray_winding;
        //             }

        //             for (curve_fragments) |curve_fragment| {
        //                 // if (curve_fragment.pixel.x == 193 and curve_fragment.pixel.y == 167) {
        //                 //     std.debug.print("\nHEY MainRay({})\n", .{boundary_fragment.main_ray_winding});
        //                 // }
        //                 const masks = curve_fragment.calculateMasks(self.half_planes);
        //                 for (0..16) |index| {
        //                     const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
        //                     const vertical_winding0 = masks.vertical_sign0 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask0 & bit_index != 0)));
        //                     const vertical_winding1 = masks.vertical_sign1 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask1 & bit_index != 0)));
        //                     const horizontal_winding = masks.horizontal_sign * @as(f32, @floatFromInt(@intFromBool(masks.horizontal_mask & bit_index != 0)));
        //                     boundary_fragment.winding[index] += vertical_winding0 + vertical_winding1 + horizontal_winding;
        //                 }
        //             }

        //             for (0..16) |index| {
        //                 const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
        //                 boundary_fragment.stencil_mask = boundary_fragment.stencil_mask | (@as(u16, @intFromBool(boundary_fragment.winding[index] != 0.0)) * bit_index);
        //             }

        //             // std.debug.print("BoundaryFragment({},{}), StencilMask({b:0>16})", .{
        //             //     boundary_fragment.pixel.x,
        //             //     boundary_fragment.pixel.y,
        //             //     boundary_fragment.stencil_mask,
        //             // });
        //         }
        //     }
        // }

        // pub fn populateSpans(self: @This(), raster_data: *RasterData) !void {
        //     _ = self;
        //     const boundary_fragments = raster_data.getBoundaryFragments();
        //     var previous_boundary_fragment: ?*BoundaryFragment = null;

        //     for (boundary_fragments) |*boundary_fragment| {
        //         if (previous_boundary_fragment) |pbf| {
        //             if (pbf.pixel.y == boundary_fragment.pixel.y and pbf.pixel.x != boundary_fragment.pixel.x - 1 and boundary_fragment.main_ray_winding != 0) {
        //                 const ao = try raster_data.addSpan();
        //                 ao.* = Span{
        //                     .y = boundary_fragment.pixel.y,
        //                     .x_range = RangeI32{
        //                         .start = pbf.pixel.x + 1,
        //                         .end = boundary_fragment.pixel.x,
        //                     },
        //                 };

        //                 std.debug.assert(ao.y >= 0);
        //             }
        //         }

        //         previous_boundary_fragment = boundary_fragment;
        //     }
        // }

        fn scanX(
            raster_data: *RD,
            grid_x: f32,
            curve: T,
            curve_bounds: RectF32,
        ) !void {
            var intersections_result: [3]Intersection = [_]Intersection{undefined} ** 3;
            const line = Line.create(
                PointF32{
                    .x = grid_x,
                    .y = curve_bounds.min.y - 1.0,
                },
                PointF32{
                    .x = grid_x,
                    .y = curve_bounds.max.y + 1.0,
                },
            );
            const intersections = curve.intersectVerticalLineGeneric(line, &intersections_result);

            for (intersections) |intersection| {
                const ao = try raster_data.addGridIntersection();
                ao.* = GridIntersection.create(intersection, .x);
            }
        }

        fn scanY(
            raster_data: *RD,
            grid_y: f32,
            curve: T,
            curve_bounds: RectF32,
        ) !void {
            var intersections_result: [3]Intersection = [_]Intersection{undefined} ** 3;
            const line = Line.create(
                PointF32{
                    .x = curve_bounds.min.x - 1.0,
                    .y = grid_y,
                },
                PointF32{
                    .x = curve_bounds.max.x + 1.0,
                    .y = grid_y,
                },
            );
            const intersections = curve.intersectHorizontalLineGeneric(line, &intersections_result);

            for (intersections) |intersection| {
                const ao = try raster_data.addGridIntersection();
                ao.* = GridIntersection.create(intersection, .y);
            }
        }
    };
}

pub const LineSoupRasterizer = SoupRasterizer(Line);
