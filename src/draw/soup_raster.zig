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
const RectI32 = core.RectI32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const RangeI32 = core.RangeI32;
const RangeUsize = core.RangeUsize;
const Line = curve_module.Line;
const Intersection = curve_module.Intersection;
const HalfPlanesU16 = msaa.HalfPlanesU16;
const Soup = soup_module.Soup;

const PathRecord = struct {
    subpath_offsets: RangeU32 = RangeU32{},
    boundary_offsets: RangeU32 = RangeU32{},
    merge_offsets: RangeU32 = RangeU32{},
    span_offsets: RangeU32 = RangeU32{},
};

const SubpathRecord = struct {
    intersection_offsets: RangeU32 = RangeU32{},
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
        const pixel = grid_intersections[0].pixel.min(grid_intersections[1].pixel);

        // can move diagonally, but cannot move by more than 1 pixel in both directions
        std.debug.assert(@abs(pixel.sub(grid_intersections[0].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[0].pixel).y) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[1].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[1].pixel).y) <= 1);

        const intersections: [2]Intersection = [2]Intersection{
            Intersection{
                // retain t
                .t = grid_intersections[0].intersection.t,
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = std.math.clamp(@abs(grid_intersections[0].intersection.point.x - @as(f32, @floatFromInt(pixel.x))), 0.0, 1.0),
                    .y = std.math.clamp(@abs(grid_intersections[0].intersection.point.y - @as(f32, @floatFromInt(pixel.y))), 0.0, 1.0),
                },
            },
            Intersection{
                // retain t
                .t = grid_intersections[1].intersection.t,
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = std.math.clamp(@abs(grid_intersections[1].intersection.point.x - @as(f32, @floatFromInt(pixel.x))), 0.0, 1.0),
                    .y = std.math.clamp(@abs(grid_intersections[1].intersection.point.y - @as(f32, @floatFromInt(pixel.y))), 0.0, 1.0),
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

    pub fn calculateMasks(self: @This(), half_planes: *const HalfPlanesU16) Masks {
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
    intersection: Intersection,
    pixel: PointI32,

    pub fn create(intersection: Intersection) @This() {
        return @This(){
            .intersection = intersection,
            .pixel = PointI32{
                .x = @intFromFloat(intersection.point.x),
                .y = @intFromFloat(intersection.point.y),
            },
        };
    }
};

pub fn RasterData(comptime T: type) type {
    const S = Soup(T);

    return struct {
        const PathRecordList = std.ArrayListUnmanaged(PathRecord);
        const SubpathRecordList = std.ArrayListUnmanaged(SubpathRecord);
        const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
        const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);
        const MergeFragmentList = std.ArrayListUnmanaged(MergeFragment);
        const SpanList = std.ArrayListUnmanaged(Span);

        allocator: Allocator,
        soup: *const S,
        path_records: PathRecordList = PathRecordList{},
        subpath_records: SubpathRecordList = SubpathRecordList{},
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
            self.subpath_records.deinit(self.allocator);
            self.grid_intersections.deinit(self.allocator);
            self.boundary_fragments.deinit(self.allocator);
            self.merge_fragments.deinit(self.allocator);
            self.spans.deinit(self.allocator);
        }

        pub fn addPathRecord(self: *@This()) !*PathRecord {
            const path_record = try self.path_records.addOne(self.allocator);
            path_record.* = PathRecord{};
            return path_record;
        }

        pub fn addSubpathRecord(self: *@This()) !*SubpathRecord {
            const subpath_record = try self.subpath_records.addOne(self.allocator);
            subpath_record.* = SubpathRecord{};
            return subpath_record;
        }

        pub fn openPathRecordSubpaths(self: *@This(), path_record: *PathRecord) void {
            path_record.subpath_offsets.start = @intCast(self.subpath_records.items.len);
        }

        pub fn openPathRecordBoundaries(self: *@This(), path_record: *PathRecord) void {
            path_record.boundary_offsets.start = @intCast(self.boundary_fragments.items.len);
        }

        pub fn openPathRecordMerges(self: *@This(), path_record: *PathRecord) void {
            path_record.merge_offsets.start = @intCast(self.merge_fragments.items.len);
        }

        pub fn openPathRecordSpans(self: *@This(), path_record: *PathRecord) void {
            path_record.span_offsets.start = @intCast(self.spans.items.len);
        }

        pub fn closePathRecordSubpaths(self: *@This(), path_record: *PathRecord) void {
            path_record.subpath_offsets.end = @intCast(self.subpath_records.items.len);
        }

        pub fn closePathRecordBoundaries(self: *@This(), path_record: *PathRecord) void {
            path_record.boundary_offsets.end = @intCast(self.boundary_fragments.items.len);
        }

        pub fn closePathRecordMerges(self: *@This(), path_record: *PathRecord) void {
            path_record.merge_offsets.end = @intCast(self.merge_fragments.items.len);
        }

        pub fn closePathRecordSpans(self: *@This(), path_record: *PathRecord) void {
            path_record.span_offsets.end = @intCast(self.spans.items.len);
        }

        pub fn openSubpathRecordIntersections(self: *@This(), subpath_record: *SubpathRecord) void {
            subpath_record.intersection_offsets.start = @intCast(self.grid_intersections.items.len);
        }

        pub fn closeSubpathRecordIntersections(self: *@This(), subpath_record: *SubpathRecord) void {
            subpath_record.intersection_offsets.end = @intCast(self.grid_intersections.items.len);
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

pub const LineRasterData = RasterData(Line);

pub fn SoupRasterizer(comptime T: type) type {
    const GRID_POINT_TOLERANCE: f32 = 1e-6;

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

            for (raster_data.soup.path_records.items) |soup_path_record| {
                const path_record = try raster_data.addPathRecord();
                raster_data.openPathRecordSubpaths(path_record);

                const soup_subpath_records = raster_data.soup.subpath_records.items[soup_path_record.subpath_offsets.start..soup_path_record.subpath_offsets.end];
                for (soup_subpath_records) |soup_subpath_record| {
                    const subpath_record = try raster_data.addSubpathRecord();
                    try self.populateGridIntersections(
                        &raster_data,
                        subpath_record,
                        soup_subpath_record,
                    );
                }

                raster_data.closePathRecordSubpaths(path_record);

                try self.populateBoundaryFragments(
                    &raster_data,
                    path_record,
                );

                try self.populateMergeFragments(
                    &raster_data,
                    path_record,
                );

                try self.populateSpans(
                    &raster_data,
                    path_record,
                );

                raster_data.closePathRecordMerges(path_record);
            }

            return raster_data;
        }

        // TODO: this can be made more efficient by getting rid of the sort
        //       in order to do this, need preallocation of buffers though
        pub fn populateGridIntersections(
            self: @This(),
            raster_data: *RD,
            subpath_record: *SubpathRecord,
            soup_subpath_record: S.SubpathRecord,
        ) !void {
            _ = self;

            raster_data.openSubpathRecordIntersections(subpath_record);

            const soup_curve_records = raster_data.soup.curve_records.items[soup_subpath_record.curve_offsets.start..soup_subpath_record.curve_offsets.end];
            for (soup_curve_records) |soup_curve_record| {
                const soup_items = raster_data.soup.items.items[soup_curve_record.item_offsets.start..soup_curve_record.item_offsets.end];
                for (soup_items) |item| {
                    const start_intersection_index = raster_data.grid_intersections.items.len;
                    const start_point: PointF32 = item.applyT(0.0);
                    const end_point: PointF32 = item.applyT(1.0);
                    const bounds_f32: RectF32 = RectF32.create(start_point, end_point);
                    const bounds: RectI32 = RectI32.create(PointI32{
                        .x = @intFromFloat(@ceil(bounds_f32.min.x)),
                        .y = @intFromFloat(@ceil(bounds_f32.min.y)),
                    }, PointI32{
                        .x = @intFromFloat(@floor(bounds_f32.max.x)),
                        .y = @intFromFloat(@floor(bounds_f32.max.y)),
                    });
                    const scan_bounds = RectF32.create(PointF32{
                        .x = @floatFromInt(bounds.min.x - 1),
                        .y = @floatFromInt(bounds.min.y - 1),
                    }, PointF32{
                        .x = @floatFromInt(bounds.max.x + 1),
                        .y = @floatFromInt(bounds.max.y + 1),
                    });
                    
                    (try raster_data.addGridIntersection()).* = GridIntersection.create((Intersection{
                        .t = 0.0,
                        .point = start_point,
                    }).fitToGrid());

                    for (0..@as(usize, @intCast(bounds.getWidth())) + 1) |x_offset| {
                        const grid_x: f32 = @floatFromInt(bounds.min.x + @as(i32, @intCast(x_offset)));
                        try scanX(raster_data, grid_x, item, scan_bounds);
                    }

                    for (0..@as(usize, @intCast(bounds.getHeight())) + 1) |y_offset| {
                        const grid_y: f32 = @floatFromInt(bounds.min.y + @as(i32, @intCast(y_offset)));
                        try scanY(raster_data, grid_y, item, scan_bounds);
                    }

                    (try raster_data.addGridIntersection()).* = GridIntersection.create((Intersection{
                        .t = 1.0,
                        .point = end_point,
                    }).fitToGrid());

                    const end_intersection_index = raster_data.grid_intersections.items.len;
                    const grid_intersections = raster_data.grid_intersections.items[start_intersection_index..end_intersection_index];

                    // need to sort by T for each curve, in order
                    std.mem.sort(
                        GridIntersection,
                        grid_intersections,
                        @as(u32, 0),
                        gridIntersectionLessThan,
                    );
                }
            }

            raster_data.closeSubpathRecordIntersections(subpath_record);
        }

        fn gridIntersectionLessThan(_: u32, left: GridIntersection, right: GridIntersection) bool {
            if (left.intersection.t < right.intersection.t) {
                return true;
            }

            return false;
        }

        pub fn populateBoundaryFragments(self: @This(), raster_data: *RD, path_record: *PathRecord) !void {
            _ = self;

            raster_data.openPathRecordBoundaries(path_record);

            const subpath_records = raster_data.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
            for (subpath_records) |subpath_record| {
                const grid_intersections = raster_data.grid_intersections.items[subpath_record.intersection_offsets.start..subpath_record.intersection_offsets.end];
                if (grid_intersections.len == 0) {
                    continue;
                }
                
                std.debug.assert(grid_intersections.len > 0);
                for (grid_intersections, 0..) |*grid_intersection, index| {
                    const next_grid_intersection = &grid_intersections[(index + 1) % grid_intersections.len];

                    if (grid_intersection.intersection.point.approxEqAbs(next_grid_intersection.intersection.point, GRID_POINT_TOLERANCE)) {
                        // skip if exactly the same point
                        continue;
                    }

                    {
                        const ao = try raster_data.addBoundaryFragment();
                        ao.* = BoundaryFragment.create([_]*const GridIntersection{ grid_intersection, next_grid_intersection });
                        // std.debug.assert(ao.intersections[0].t < ao.intersections[1].t);
                    }
                }
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
            }

            return false;
        }

        pub fn populateMergeFragments(self: @This(), raster_data: *RD, path_record: *PathRecord) !void {
            raster_data.openPathRecordMerges(path_record);
            {
                const first_boundary_fragment = &raster_data.boundary_fragments.items[path_record.boundary_offsets.start];
                var merge_fragment: *MergeFragment = try raster_data.addMergeFragment();
                merge_fragment.* = MergeFragment{
                    .pixel = first_boundary_fragment.pixel,
                };
                var boundary_offsets = RangeU32{
                    .start = path_record.boundary_offsets.start,
                    .end = path_record.boundary_offsets.start,
                };
                var main_ray_winding: f32 = 0.0;

                const boundary_fragments = raster_data.boundary_fragments.items[path_record.boundary_offsets.start..path_record.boundary_offsets.end];
                for (boundary_fragments, 0..) |*boundary_fragment, boundary_fragment_index| {
                    const y_changing = boundary_fragment.pixel.y != merge_fragment.pixel.y;
                    if (boundary_fragment.pixel.x != merge_fragment.pixel.x or boundary_fragment.pixel.y != merge_fragment.pixel.y) {
                        boundary_offsets.end = path_record.boundary_offsets.start + @as(u32, @intCast(boundary_fragment_index));
                        merge_fragment.boundary_offsets = boundary_offsets;
                        merge_fragment = try raster_data.addMergeFragment();
                        boundary_offsets.start = boundary_offsets.end;
                        merge_fragment.* = MergeFragment{
                            .pixel = boundary_fragment.pixel,
                        };
                        merge_fragment.main_ray_winding = main_ray_winding;

                        if (y_changing) {
                            main_ray_winding = 0.0;
                        }
                    }

                    main_ray_winding += boundary_fragment.calculateMainRayWinding();
                }
            }
            raster_data.closePathRecordMerges(path_record);

            {
                const merge_fragments = raster_data.merge_fragments.items[path_record.merge_offsets.start..path_record.merge_offsets.end];
                for (merge_fragments) |*merge_fragment| {
                    const boundary_fragments = raster_data.boundary_fragments.items[merge_fragment.boundary_offsets.start..merge_fragment.boundary_offsets.end];

                    for (0..16) |index| {
                        merge_fragment.winding[index] += merge_fragment.main_ray_winding;
                    }

                    for (boundary_fragments) |boundary_fragment| {
                        // if (curve_fragment.pixel.x == 193 and curve_fragment.pixel.y == 167) {
                        //     std.debug.print("\nHEY MainRay({})\n", .{boundary_fragment.main_ray_winding});
                        // }
                        const masks = boundary_fragment.calculateMasks(self.half_planes);
                        for (0..16) |index| {
                            const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
                            const vertical_winding0 = masks.vertical_sign0 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask0 & bit_index != 0)));
                            const vertical_winding1 = masks.vertical_sign1 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask1 & bit_index != 0)));
                            const horizontal_winding = masks.horizontal_sign * @as(f32, @floatFromInt(@intFromBool(masks.horizontal_mask & bit_index != 0)));
                            merge_fragment.winding[index] += vertical_winding0 + vertical_winding1 + horizontal_winding;
                        }
                    }

                    for (0..16) |index| {
                        const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
                        merge_fragment.stencil_mask = merge_fragment.stencil_mask | (@as(u16, @intFromBool(merge_fragment.winding[index] != 0.0)) * bit_index);
                    }
                }
            }
        }

        pub fn populateSpans(self: @This(), raster_data: *RD, path_record: *PathRecord) !void {
            _ = self;

            raster_data.openPathRecordSpans(path_record);

            const merge_fragments = raster_data.merge_fragments.items[path_record.merge_offsets.start..path_record.merge_offsets.end];
            var previous_merge_fragment: ?*MergeFragment = null;

            for (merge_fragments) |*merge_fragment| {
                if (previous_merge_fragment) |pmf| {
                    if (pmf.pixel.y == merge_fragment.pixel.y and pmf.pixel.x != merge_fragment.pixel.x - 1 and merge_fragment.main_ray_winding != 0) {
                        const ao = try raster_data.addSpan();
                        ao.* = Span{
                            .y = merge_fragment.pixel.y,
                            .x_range = RangeI32{
                                .start = pmf.pixel.x + 1,
                                .end = merge_fragment.pixel.x,
                            },
                        };
                    }
                }

                previous_merge_fragment = merge_fragment;
            }
            raster_data.closePathRecordSpans(path_record);
        }

        fn scanX(
            raster_data: *RD,
            grid_x: f32,
            curve: T,
            scan_bounds: RectF32,
        ) !void {
            const line = Line.create(
                PointF32{
                    .x = grid_x,
                    .y = scan_bounds.min.y,
                },
                PointF32{
                    .x = grid_x,
                    .y = scan_bounds.max.y,
                },
            );

            if (curve.intersectVerticalLine(line)) |intersection| {
                const ao = try raster_data.addGridIntersection();
                ao.* = GridIntersection.create(intersection.fitToGrid());
            }
        }

        fn scanY(
            raster_data: *RD,
            grid_y: f32,
            curve: T,
            scan_bounds: RectF32,
        ) !void {
            const line = Line.create(
                PointF32{
                    .x = scan_bounds.min.x,
                    .y = grid_y,
                },
                PointF32{
                    .x = scan_bounds.max.x,
                    .y = grid_y,
                },
            );

            if (curve.intersectHorizontalLine(line)) |intersection| {
                const ao = try raster_data.addGridIntersection();
                ao.* = GridIntersection.create(intersection.fitToGrid());
            }
        }
    };
}

pub const LineSoupRasterizer = SoupRasterizer(Line);
