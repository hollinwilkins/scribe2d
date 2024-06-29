const std = @import("std");
const path_module = @import("./path.zig");
const curve_module = @import("./curve.zig");
const core = @import("../core/root.zig");
const msaa = @import("./msaa.zig");
const soup_module = @import("./soup.zig");
const soup_estimate_module = @import("./soup_estimate.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Shape = path_module.Shape;
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
const PathRecord = soup_module.FlatPath;
const SubpathRecord = soup_module.FlatSubpath;
const GridIntersection = soup_module.GridIntersection;
const BoundaryFragment = soup_module.BoundaryFragment;
const MergeFragment = soup_module.MergeFragment;
const Span = soup_module.Span;
const LineSoupEstimator = soup_estimate_module.LineSoupEstimator;

pub fn Writer(comptime T: type) type {
    return struct {
        slice: []T,
        index: usize = 0,

        pub fn create(slice: []T) @This() {
            return @This(){
                .slice = slice,
            };
        }

        pub fn addOne(self: *@This()) *T {
            const item = &self.slice[self.index];
            self.index += 1;
            return item;
        }

        pub fn toSlice(self: @This()) []T {
            return self.slice[0..self.index];
        }
    };
}

const IntersectionWriter = Writer(GridIntersection);
const BoundaryFragmentWriter = Writer(BoundaryFragment);
const MergeFragmentWriter = Writer(MergeFragment);
const SpanWriter = Writer(Span);

pub fn SoupRasterizer(comptime T: type, comptime Estimator: type) type {
    const GRID_POINT_TOLERANCE: f32 = 1e-6;

    const S = Soup(T);

    return struct {
        half_planes: *const HalfPlanesU16,

        pub fn create(half_planes: *const HalfPlanesU16) @This() {
            return @This(){
                .half_planes = half_planes,
            };
        }

        pub fn rasterize(self: @This(), soup: *S) !void {
            try Estimator.estimateRaster(soup);

            for (soup.flat_paths.items) |*path| {
                const subpaths = soup.flat_subpaths.items[path.flat_subpath_offsets.start..path.flat_subpath_offsets.end];
                for (subpaths) |*subpath| {
                    try self.populateGridIntersections(
                        soup,
                        subpath,
                    );
                }

                try self.populateBoundaryFragments(
                    soup,
                    path,
                );

                try self.populateMergeFragments(
                    soup,
                    path,
                );

                try self.populateSpans(
                    soup,
                    path,
                );
            }
        }

        // TODO: this can be made more efficient by getting rid of the sort
        //       in order to do this, need preallocation of buffers though
        pub fn populateGridIntersections(
            self: @This(),
            soup: *S,
            subpath: *SubpathRecord,
        ) !void {
            _ = self;

            const curves = soup.flat_curves.items[subpath.flat_curve_offsets.start..subpath.flat_curve_offsets.end];
            for (curves) |*curve| {
                const intersections = soup.grid_intersections.items[curve.intersection_offsets.start..curve.intersection_offsets.end];
                var intersection_writer = IntersectionWriter.create(intersections);

                const soup_items = soup.items.items[curve.item_offsets.start..curve.item_offsets.end];
                for (soup_items) |item| {
                    const start_intersection_index = intersection_writer.index;
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

                    intersection_writer.addOne().* = GridIntersection.create((Intersection{
                        .t = 0.0,
                        .point = start_point,
                    }).fitToGrid());

                    for (0..@as(usize, @intCast(bounds.getWidth())) + 1) |x_offset| {
                        const grid_x: f32 = @floatFromInt(bounds.min.x + @as(i32, @intCast(x_offset)));
                        try scanX(grid_x, item, scan_bounds, &intersection_writer);
                    }

                    for (0..@as(usize, @intCast(bounds.getHeight())) + 1) |y_offset| {
                        const grid_y: f32 = @floatFromInt(bounds.min.y + @as(i32, @intCast(y_offset)));
                        try scanY(grid_y, item, scan_bounds, &intersection_writer);
                    }

                    intersection_writer.addOne().* = GridIntersection.create((Intersection{
                        .t = 1.0,
                        .point = end_point,
                    }).fitToGrid());

                    const end_intersection_index = intersection_writer.index;
                    const grid_intersections = intersection_writer.slice[start_intersection_index..end_intersection_index];

                    // need to sort by T for each curve, in order
                    std.mem.sort(
                        GridIntersection,
                        grid_intersections,
                        @as(u32, 0),
                        gridIntersectionLessThan,
                    );
                }

                curve.intersection_offsets.end = curve.intersection_offsets.start + @as(u32, @intCast(intersection_writer.index));
            }
        }

        fn gridIntersectionLessThan(_: u32, left: GridIntersection, right: GridIntersection) bool {
            if (left.intersection.t < right.intersection.t) {
                return true;
            }

            return false;
        }

        pub fn populateBoundaryFragments(self: @This(), soup: *S, path: *PathRecord) !void {
            _ = self;

            const boundary_fragments = soup.boundary_fragments.items[path.boundary_offsets.start..path.boundary_offsets.end];
            var boundary_fragment_writer = BoundaryFragmentWriter.create(boundary_fragments);

            const subpaths = soup.flat_subpaths.items[path.flat_subpath_offsets.start..path.flat_subpath_offsets.end];
            for (subpaths) |subpath| {
                const curves = soup.flat_curves.items[subpath.flat_curve_offsets.start..subpath.flat_curve_offsets.end];
                for (curves, 0..) |curve, curve_index| {
                    const grid_intersections = soup.grid_intersections.items[curve.intersection_offsets.start..curve.intersection_offsets.end];
                    if (grid_intersections.len == 0) {
                        continue;
                    }

                    std.debug.assert(grid_intersections.len > 0);
                    for (grid_intersections, 0..) |*grid_intersection, index| {
                        var next_grid_intersection: *GridIntersection = undefined;
                        const next_index = index + 1;

                        if (next_index >= grid_intersections.len) {
                            const next_curve = curves[(curve_index + 1) % curves.len];
                            next_grid_intersection = &soup.grid_intersections.items[next_curve.intersection_offsets.start];
                        } else {
                            next_grid_intersection = &grid_intersections[next_index];
                        }

                        if (grid_intersection.intersection.point.approxEqAbs(next_grid_intersection.intersection.point, GRID_POINT_TOLERANCE)) {
                            // skip if exactly the same point
                            continue;
                        }

                        {
                            boundary_fragment_writer.addOne().* = BoundaryFragment.create([_]*const GridIntersection{ grid_intersection, next_grid_intersection });
                        }
                    }
                }
            }

            path.boundary_offsets.end = path.boundary_offsets.start + @as(u32, @intCast(boundary_fragment_writer.index));

            // sort all curve fragments of all the subpaths by y ascending, x ascending
            std.mem.sort(
                BoundaryFragment,
                boundary_fragment_writer.toSlice(),
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

        pub fn populateMergeFragments(self: @This(), soup: *S, path: *PathRecord) !void {
            {
                const merge_fragments = soup.merge_fragments.items[path.merge_offsets.start..path.merge_offsets.end];
                var merge_fragment_writer = MergeFragmentWriter.create(merge_fragments);
                const first_boundary_fragment = &soup.boundary_fragments.items[path.boundary_offsets.start];
                var merge_fragment: *MergeFragment = merge_fragment_writer.addOne();
                merge_fragment.* = MergeFragment{
                    .pixel = first_boundary_fragment.pixel,
                };
                var boundary_offsets = RangeU32{
                    .start = path.boundary_offsets.start,
                    .end = path.boundary_offsets.start,
                };
                var main_ray_winding: f32 = 0.0;

                const boundary_fragments = soup.boundary_fragments.items[path.boundary_offsets.start..path.boundary_offsets.end];
                for (boundary_fragments, 0..) |*boundary_fragment, boundary_fragment_index| {
                    const y_changing = boundary_fragment.pixel.y != merge_fragment.pixel.y;
                    if (boundary_fragment.pixel.x != merge_fragment.pixel.x or boundary_fragment.pixel.y != merge_fragment.pixel.y) {
                        boundary_offsets.end = path.boundary_offsets.start + @as(u32, @intCast(boundary_fragment_index));
                        merge_fragment.boundary_offsets = boundary_offsets;
                        merge_fragment = merge_fragment_writer.addOne();
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

                path.merge_offsets.end = path.merge_offsets.start + @as(u32, @intCast(merge_fragment_writer.index));
            }

            {
                const merge_fragments = soup.merge_fragments.items[path.merge_offsets.start..path.merge_offsets.end];
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

        pub fn populateSpans(self: @This(), soup: *S, path: *PathRecord) !void {
            _ = self;

            const spans = soup.spans.items[path.span_offsets.start..path.span_offsets.end];
            var span_writer = SpanWriter.create(spans);

            const merge_fragments = soup.merge_fragments.items[path.merge_offsets.start..path.merge_offsets.end];
            var previous_merge_fragment: ?*MergeFragment = null;

            for (merge_fragments) |*merge_fragment| {
                if (previous_merge_fragment) |pmf| {
                    if (pmf.pixel.y == merge_fragment.pixel.y and pmf.pixel.x != merge_fragment.pixel.x - 1 and merge_fragment.main_ray_winding != 0) {
                        span_writer.addOne().* = Span{
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

            path.span_offsets.end = path.span_offsets.start + @as(u32, @intCast(span_writer.index));
        }

        fn scanX(
            grid_x: f32,
            curve: T,
            scan_bounds: RectF32,
            intersection_writer: *IntersectionWriter,
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
                intersection_writer.addOne().* = GridIntersection.create(intersection.fitToGrid());
            }
        }

        fn scanY(
            grid_y: f32,
            curve: T,
            scan_bounds: RectF32,
            intersection_writer: *IntersectionWriter,
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
                intersection_writer.addOne().* = GridIntersection.create(intersection.fitToGrid());
            }
        }
    };
}

pub const LineSoupRasterizer = SoupRasterizer(Line, LineSoupEstimator);
