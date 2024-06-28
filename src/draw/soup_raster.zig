const std = @import("std");
const path_module = @import("./path.zig");
const curve_module = @import("./curve.zig");
const core = @import("../core/root.zig");
const msaa = @import("./msaa.zig");
const soup_module = @import("./soup.zig");
const soup_estimate_module = @import("./soup_estimate.zig");
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
const PathRecord = soup_module.PathRecord;
const SubpathRecord = soup_module.SubpathRecord;
const GridIntersection = soup_module.GridIntersection;
const BoundaryFragment = soup_module.BoundaryFragment;
const MergeFragment = soup_module.MergeFragment;
const Span = soup_module.Span;
const LineSoupEstimator = soup_estimate_module.LineSoupEstimator;

pub fn SoupRasterizer(comptime T: type, comptime Estimator: T) type {
    const GRID_POINT_TOLERANCE: f32 = 1e-6;

    const S = Soup(T);

    return struct {
        estimator: Estimator,
        half_planes: *const HalfPlanesU16,

        pub fn create(estimator: Estimator, half_planes: *const HalfPlanesU16) @This() {
            return @This(){
                .estimator = estimator,
                .half_planes = half_planes,
            };
        }

        pub fn rasterize(self: @This(), soup: *S) !void {
            try self.estimator.estimateRaster(soup);

            for (soup.path_records.items) |*path_record| {
                const subpath_records = soup.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                for (subpath_records) |*subpath_record| {
                    try self.populateGridIntersections(
                        soup,
                        subpath_record,
                    );
                }

                try self.populateBoundaryFragments(
                    soup,
                    path_record,
                );

                try self.populateMergeFragments(
                    soup,
                    path_record,
                );

                try self.populateSpans(
                    soup,
                    path_record,
                );

                soup.closePathMerges(path_record);
            }
        }

        // TODO: this can be made more efficient by getting rid of the sort
        //       in order to do this, need preallocation of buffers though
        pub fn populateGridIntersections(
            self: @This(),
            soup: *S,
            subpath_record: *SubpathRecord,
        ) !void {
            _ = self;

            soup.openSubpathIntersections(subpath_record);

            const curve_records = soup.curve_records.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
            for (curve_records) |curve_record| {
                const soup_items = soup.items.items[curve_record.item_offsets.start..curve_record.item_offsets.end];
                for (soup_items) |item| {
                    const start_intersection_index = soup.grid_intersections.items.len;
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

                    (try soup.addGridIntersection()).* = GridIntersection.create((Intersection{
                        .t = 0.0,
                        .point = start_point,
                    }).fitToGrid());

                    for (0..@as(usize, @intCast(bounds.getWidth())) + 1) |x_offset| {
                        const grid_x: f32 = @floatFromInt(bounds.min.x + @as(i32, @intCast(x_offset)));
                        try scanX(soup, grid_x, item, scan_bounds);
                    }

                    for (0..@as(usize, @intCast(bounds.getHeight())) + 1) |y_offset| {
                        const grid_y: f32 = @floatFromInt(bounds.min.y + @as(i32, @intCast(y_offset)));
                        try scanY(soup, grid_y, item, scan_bounds);
                    }

                    (try soup.addGridIntersection()).* = GridIntersection.create((Intersection{
                        .t = 1.0,
                        .point = end_point,
                    }).fitToGrid());

                    const end_intersection_index = soup.grid_intersections.items.len;
                    const grid_intersections = soup.grid_intersections.items[start_intersection_index..end_intersection_index];

                    // need to sort by T for each curve, in order
                    std.mem.sort(
                        GridIntersection,
                        grid_intersections,
                        @as(u32, 0),
                        gridIntersectionLessThan,
                    );
                }
            }

            soup.closeSubpathIntersections(subpath_record);
        }

        fn gridIntersectionLessThan(_: u32, left: GridIntersection, right: GridIntersection) bool {
            if (left.intersection.t < right.intersection.t) {
                return true;
            }

            return false;
        }

        pub fn populateBoundaryFragments(self: @This(), soup: *S, path_record: *PathRecord) !void {
            _ = self;

            soup.openPathBoundaries(path_record);

            const subpath_records = soup.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
            for (subpath_records) |subpath_record| {
                const grid_intersections = soup.grid_intersections.items[subpath_record.intersection_offsets.start..subpath_record.intersection_offsets.end];
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
                        const ao = try soup.addBoundaryFragment();
                        ao.* = BoundaryFragment.create([_]*const GridIntersection{ grid_intersection, next_grid_intersection });
                        // std.debug.assert(ao.intersections[0].t < ao.intersections[1].t);
                    }
                }
            }

            soup.closePathBoundaries(path_record);
            const boundary_fragments = soup.boundary_fragments.items[path_record.boundary_offsets.start..path_record.boundary_offsets.end];
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

        pub fn populateMergeFragments(self: @This(), soup: *S, path_record: *PathRecord) !void {
            soup.openPathMerges(path_record);

            {
                const first_boundary_fragment = &soup.boundary_fragments.items[path_record.boundary_offsets.start];
                var merge_fragment: *MergeFragment = try soup.addMergeFragment();
                merge_fragment.* = MergeFragment{
                    .pixel = first_boundary_fragment.pixel,
                };
                var boundary_offsets = RangeU32{
                    .start = path_record.boundary_offsets.start,
                    .end = path_record.boundary_offsets.start,
                };
                var main_ray_winding: f32 = 0.0;

                const boundary_fragments = soup.boundary_fragments.items[path_record.boundary_offsets.start..path_record.boundary_offsets.end];
                for (boundary_fragments, 0..) |*boundary_fragment, boundary_fragment_index| {
                    const y_changing = boundary_fragment.pixel.y != merge_fragment.pixel.y;
                    if (boundary_fragment.pixel.x != merge_fragment.pixel.x or boundary_fragment.pixel.y != merge_fragment.pixel.y) {
                        boundary_offsets.end = path_record.boundary_offsets.start + @as(u32, @intCast(boundary_fragment_index));
                        merge_fragment.boundary_offsets = boundary_offsets;
                        merge_fragment = try soup.addMergeFragment();
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
            soup.closePathMerges(path_record);

            {
                const merge_fragments = soup.merge_fragments.items[path_record.merge_offsets.start..path_record.merge_offsets.end];
                for (merge_fragments) |*merge_fragment| {
                    const boundary_fragments = soup.boundary_fragments.items[merge_fragment.boundary_offsets.start..merge_fragment.boundary_offsets.end];

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

        pub fn populateSpans(self: @This(), soup: *S, path_record: *PathRecord) !void {
            _ = self;

            soup.openPathSpans(path_record);

            const merge_fragments = soup.merge_fragments.items[path_record.merge_offsets.start..path_record.merge_offsets.end];
            var previous_merge_fragment: ?*MergeFragment = null;

            for (merge_fragments) |*merge_fragment| {
                if (previous_merge_fragment) |pmf| {
                    if (pmf.pixel.y == merge_fragment.pixel.y and pmf.pixel.x != merge_fragment.pixel.x - 1 and merge_fragment.main_ray_winding != 0) {
                        const ao = try soup.addSpan();
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
            soup.closePathSpans(path_record);
        }

        fn scanX(
            soup: *S,
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
                const ao = try soup.addGridIntersection();
                ao.* = GridIntersection.create(intersection.fitToGrid());
            }
        }

        fn scanY(
            soup: *S,
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
                const ao = try soup.addGridIntersection();
                ao.* = GridIntersection.create(intersection.fitToGrid());
            }
        }
    };
}

pub const LineSoupRasterizer = SoupRasterizer(Line, LineSoupEstimator);
