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
const Curve = curve_module.Curve;
const Line = curve_module.Line;
const Intersection = curve_module.Intersection;
const UnmanagedTexture = texture_module.UnmanagedTexture;
const HalfPlanesU16 = msaa.HalfPlanesU16;

pub const PathIntersection = struct {
    shape_index: u32,
    curve_index: u32,
    is_end: bool,
    intersection: Intersection,

    pub fn getPixel(self: PathIntersection) PointI32 {
        return PointI32{
            .x = @intFromFloat(self.intersection.point.x),
            .y = @intFromFloat(self.intersection.point.y),
        };
    }
};
pub const PathIntersectionList = std.ArrayList(PathIntersection);

pub const FragmentIntersection = struct {
    shape_index: u32,
    curve_index: u32,
    pixel: PointI32,
    intersection1: Intersection,
    intersection2: Intersection,
    horizontal_mask: u16,
    horizontal_sign: i2,
    vertical_mask: u16,
    vertical_sign: i2,

    pub fn getLine(self: FragmentIntersection) Line {
        return Line.create(self.intersection1.point, self.intersection2.point);
    }
};
pub const FragmentIntersectionList = std.ArrayList(FragmentIntersection);

pub const BoundaryFragment = struct {
    pixel: PointI32,
    winding: f32,
    bitmask: u16 = 0,
};
pub const BoundaryFragmentList = std.ArrayList(BoundaryFragment);

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

    pub fn createIntersections(allocator: Allocator, path: Path, view: *TextureViewRgba) !PathIntersectionList {
        var intersections = PathIntersectionList.init(allocator);
        errdefer intersections.deinit();

        var monotonic_cuts: [2]Intersection = [_]Intersection{undefined} ** 2;

        const pixel_view_dimensions = view.getDimensions();
        const scaled_pixel_dimensions = DimensionsF32{
            .width = @floatFromInt(pixel_view_dimensions.width),
            .height = @floatFromInt(pixel_view_dimensions.height),
        };

        for (path.getShapes(), 0..) |shape, shape_index_usize| {
            const shape_index: u32 = @intCast(shape_index_usize);
            var shape_intersection_range = RangeUsize{
                .start = intersections.items.len,
                .end = intersections.items.len,
            };

            for (path.getCurvesRange(shape.curve_offsets), 0..) |curve, curve_index_usize| {
                const curve_index: u32 = @intCast(curve_index_usize);
                const scaled_curve = curve.invertY().scale(scaled_pixel_dimensions);
                const scaled_curve_bounds = scaled_curve.getBounds();

                // scan x lines within bounds
                (try intersections.addOne()).* = PathIntersection{
                    .shape_index = shape_index,
                    .curve_index = curve_index,
                    .intersection = Intersection{
                        .t = 0.0,
                        .point = scaled_curve.applyT(0.0),
                    },
                    .is_end = false,
                };
                const grid_x_size: usize = @intFromFloat(scaled_curve_bounds.getWidth());
                const grid_x_start: i32 = @intFromFloat(scaled_curve_bounds.min.x);
                for (0..grid_x_size + 1) |x_offset| {
                    const grid_x = grid_x_start + @as(i32, @intCast(x_offset));
                    try scanX(
                        shape_index,
                        curve_index,
                        @as(f32, @floatFromInt(grid_x)),
                        scaled_curve,
                        scaled_curve_bounds,
                        &intersections,
                    );
                }

                // scan y lines within bounds
                const grid_y_size: usize = @intFromFloat(scaled_curve_bounds.getHeight());
                const grid_y_start: i32 = @intFromFloat(scaled_curve_bounds.min.y);
                for (0..grid_y_size + 1) |y_offset| {
                    const grid_y = grid_y_start + @as(i32, @intCast(y_offset));
                    try scanY(
                        shape_index,
                        curve_index,
                        @as(f32, @floatFromInt(grid_y)),
                        scaled_curve,
                        scaled_curve_bounds,
                        &intersections,
                    );
                }

                // insert monotonic cuts, which ensure there are segmented montonic curves
                for (scaled_curve.monotonicCuts(&monotonic_cuts)) |intersection| {
                    const ao = try intersections.addOne();
                    ao.* = PathIntersection{
                        .shape_index = shape_index,
                        .curve_index = curve_index,
                        .intersection = intersection,
                        .is_end = false,
                    };
                }

                // last virtual intersection
                (try intersections.addOne()).* = PathIntersection{
                    .shape_index = shape_index,
                    .curve_index = curve_index,
                    .intersection = Intersection{
                        .t = 1.0,
                        .point = scaled_curve.applyT(1.0),
                    },
                    .is_end = scaled_curve.isEndCurve(),
                };
            }

            shape_intersection_range.end = intersections.items.len;

            // sort by t
            std.mem.sort(
                PathIntersection,
                intersections.items[shape_intersection_range.start..shape_intersection_range.end],
                @as(u32, 0),
                pathIntersectionLessThan,
            );
        }

        return intersections;
    }

    fn pathIntersectionLessThan(_: u32, left: PathIntersection, right: PathIntersection) bool {
        if (left.shape_index < right.shape_index) {
            return true;
        } else if (left.shape_index > right.shape_index) {
            return false;
        } else if (left.curve_index < right.curve_index) {
            return true;
        } else if (left.curve_index > right.curve_index) {
            return false;
        } else if (left.intersection.t < right.intersection.t) {
            return true;
        } else if (left.intersection.t > right.intersection.t) {
            return false;
        } else if (right.is_end) {
            return true;
        } else {
            return false;
        }
    }

    // intersections must be sorted by curve_index, t
    pub fn createFragmentIntersectionsAlloc(self: *@This(), allocator: Allocator, intersections: []const PathIntersection) !FragmentIntersectionList {
        var fragment_intersections = try FragmentIntersectionList.initCapacity(allocator, intersections.len - 1);

        for (0..intersections.len) |index| {
            if (index + 1 >= intersections.len) {
                break;
            }

            const intersection1 = intersections[index];
            const intersection2 = intersections[index + 1];
            if (std.meta.eql(intersection1.intersection.point, intersection2.intersection.point)) {
                continue;
            }

            if (intersection1.is_end or intersection1.shape_index != intersection2.shape_index or intersection1.curve_index != intersection2.curve_index) {
                continue;
            }

            const pixel = intersection1.getPixel().min(intersection2.getPixel());

            const horizontal_mask = self.half_planes.getHorizontalMask(Line.create(
                intersection1.intersection.point,
                intersection2.intersection.point,
            ));
            var vertical_mask: u16 = 0;
            var horizontal_sign: i2 = 0;
            var vertical_sign: i2 = 0;
            if (intersection1.intersection.point.x == 0.0) {
                vertical_mask = self.half_planes.getVerticalMask(intersection1.intersection.point.y);

                if (intersection1.intersection.point.y > 0.5) {
                    vertical_sign = -1;
                } else {
                    vertical_sign = 1;
                }
            } else if (intersection2.intersection.point.x == 0.0) {
                vertical_mask = self.half_planes.getVerticalMask(intersection2.intersection.point.y);

                if (intersection2.intersection.point.y > 0.5) {
                    vertical_sign = -1;
                } else {
                    vertical_sign = 1;
                }
            }

            if (intersection1.intersection.point.y > intersection2.intersection.point.y) {
                horizontal_sign = 1;
            } else if (intersection1.intersection.point.y < intersection2.intersection.point.y) {
                horizontal_sign = -1;
            }

            if (intersection1.intersection.t > intersection2.intersection.t) {
                horizontal_sign *= -1;
                vertical_sign *= -1;
            }

            const ao = fragment_intersections.addOneAssumeCapacity();
            ao.* = FragmentIntersection{
                .shape_index = intersection1.shape_index,
                .curve_index = intersection1.curve_index,
                .pixel = pixel,
                .intersection1 = intersection1.intersection,
                .intersection2 = intersection2.intersection,
                .horizontal_mask = horizontal_mask,
                .horizontal_sign = horizontal_sign,
                .vertical_mask = vertical_mask,
                .vertical_sign = vertical_sign,
            };
        }

        // sort by path_id, y, x
        std.mem.sort(
            FragmentIntersection,
            fragment_intersections.items,
            @as(u32, 0),
            fragmentIntersectionLessThan,
        );

        return fragment_intersections;
    }

    fn fragmentIntersectionLessThan(_: u32, left: FragmentIntersection, right: FragmentIntersection) bool {
        if (left.shape_index < right.shape_index) {
            return true;
        } else if (left.shape_index > right.shape_index) {
            return false;
        } else if (left.pixel.y < right.pixel.y) {
            return true;
        } else if (left.pixel.y > right.pixel.y) {
            return false;
        } else if (left.pixel.x < right.pixel.x) {
            return true;
        } else {
            return false;
        }
    }

    pub fn unwindFragmentIntersectionsAlloc(allocator: Allocator, fragment_intersections: []FragmentIntersection) !BoundaryFragmentList {
        var boundary_fragments = BoundaryFragmentList.init(allocator);
        var index: usize = 0;

        while (index < fragment_intersections.len) {
            var fragment_intersection = &fragment_intersections[index];
            var previous_boundary_fragment: ?BoundaryFragment = null;
            const y = fragment_intersection.pixel.y;
            const start_index = fragment_intersections.len;
            var end_index = start_index;

            while (index < fragment_intersections.len and fragment_intersection.pixel.y == y) {
                var boundary_fragment: *BoundaryFragment = try boundary_fragments.addOne();
                boundary_fragment.* = BoundaryFragment{
                    .pixel = fragment_intersection.pixel,
                    .winding = 0.0,
                };
                const x = fragment_intersection.pixel.x;

                std.debug.print("Start new boundary fragment @ {}x{}\n", .{ x, y });

                while (index < fragment_intersections.len and fragment_intersection.pixel.x == x) {
                    if (previous_boundary_fragment) |previous| {
                        // set both winding values to the previous end winding value
                        // we haven't intersected the ray yet, so it is just
                        // continuous with the previous winding
                        boundary_fragment.winding = previous.winding;
                    }

                    const ray_y: f32 = @as(f32, @floatFromInt(fragment_intersection.pixel.y)) + 0.5;
                    const ray_line = Line.create(
                        PointF32{
                            .x = @floatFromInt(fragment_intersection.pixel.x),
                            .y = ray_y,
                        },
                        PointF32{
                            .x = @as(f32, @floatFromInt(fragment_intersection.pixel.x)) + 1.0,
                            .y = ray_y,
                        },
                    );
                    const fragment_intersection_line = fragment_intersection.getLine();

                    if (ray_line.intersectHorizontalLine(fragment_intersection_line) != null) {
                        if (fragment_intersection_line.start.y < ray_y) {
                            // curve passing top to bottom
                            boundary_fragment.winding -= 1;
                        } else if (fragment_intersection_line.start.y > ray_y) {
                            // curve passing bottom to top
                            boundary_fragment.winding += 1;
                        } else if (fragment_intersection_line.end.y < ray_y) {
                            // curve passing top to bottom, starting on ray
                            boundary_fragment.winding -= 0.5;
                        } else if (fragment_intersection_line.end.y > ray_y) {
                            // curve passing bottom to top, starting on ray
                            boundary_fragment.winding += 0.5;
                        } else {
                            // shouldn't happend, parallel lines
                            unreachable;
                        }
                    }
                    index += 1;

                    if (index < fragment_intersections.len) {
                        fragment_intersection = &fragment_intersections[index];
                        end_index = index;
                    }
                    previous_boundary_fragment = boundary_fragment.*;
                }

                // for each fragment intersection, you can
                // - calculalate the bitmask for Mv and Mh and store it in the FragmentIntersection

                // var bitmask: u16 = 0;
                var samples: [16]i8 = [_]i8{0} ** 16;
                if (end_index > start_index) {
                    for (fragment_intersections[start_index .. end_index - 1]) |fi| {
                        for (0..16) |sample_index| {
                            const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(sample_index));
                            const main_ray: i8 = @intFromFloat(boundary_fragment.winding);
                            const horizontal_ray: i8 = fi.horizontal_sign * @intFromBool((fi.horizontal_mask & bit_index) != 0);
                            const vertical_ray: i8 = fi.vertical_sign * @intFromBool((fi.vertical_mask & bit_index) != 0);
                            samples[sample_index] += main_ray + horizontal_ray + vertical_ray;
                        }
                    }
                }

                var mask: u16 = 0;
                for (0..16) |sample_index| {
                    const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(sample_index));
                    if (samples[sample_index] != 0) {
                        mask |= bit_index;
                    }
                }

                boundary_fragment.bitmask = mask;
            }
        }

        return boundary_fragments;
    }

    fn scanX(
        shape_index: u32,
        curve_index: u32,
        grid_x: f32,
        curve: Curve,
        scaled_curve_bounds: RectF32,
        intersections: *PathIntersectionList,
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
            const ao = try intersections.addOne();
            ao.* = PathIntersection{
                .shape_index = shape_index,
                .curve_index = curve_index,
                .intersection = intersection,
                .is_end = false,
            };
        }
    }

    fn scanY(
        shape_index: u32,
        curve_index: u32,
        grid_y: f32,
        curve: Curve,
        scaled_curve_bounds: RectF32,
        intersections: *PathIntersectionList,
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
            const ao = try intersections.addOne();
            ao.* = PathIntersection{
                .shape_index = shape_index,
                .curve_index = curve_index,
                .intersection = intersection,
                .is_end = false,
            };
        }
    }
};

test "raster intersections" {
    const test_util = @import("./test_util.zig");
    const pen_module = @import("./pen.zig");
    const UnmanagedTextureRgba = texture_module.UnmanagedTextureRgba;

    var pen = try pen_module.Pen.init(std.testing.allocator);
    defer pen.deinit();

    try pen.moveTo(PointF32{
        .x = 0.2,
        .y = 0.2,
    });
    try pen.lineTo(PointF32{
        .x = 0.2,
        .y = 0.8,
    });
    try pen.quadTo(PointF32{
        .x = 0.2,
        .y = 0.2,
    }, PointF32{
        .x = 0.6,
        .y = 0.5,
    });

    var path = try pen.createPathAlloc(std.testing.allocator);
    defer path.deinit();

    const size: u32 = 5;
    const dimensions = core.DimensionsU32{
        .width = size,
        .height = size,
    };

    var texture = try UnmanagedTextureRgba.create(std.testing.allocator, dimensions);
    defer texture.deinit(std.testing.allocator);
    var texture_view = texture.createView(core.RectU32{
        .min = core.PointU32{
            .x = 0,
            .y = 0,
        },
        .max = core.PointU32{
            .x = dimensions.width,
            .y = dimensions.height,
        },
    }).?;

    const path_intersections = try Raster.createIntersections(std.testing.allocator, path, &texture_view);
    defer path_intersections.deinit();

    // std.debug.print("Intersections:\n", .{});
    // for (path_intersections.items) |intersection| {
    //     std.debug.print("{}\n", .{intersection});
    // }

    try test_util.expectPathIntersectionsContains(PathIntersection{
        .shape_index = 0,
        .curve_index = 0,
        .is_end = false,
        .intersection = Intersection{
            .t = 0.0,
            .point = PointF32{
                .x = 1.0,
                .y = 4.0,
            },
        },
    }, path_intersections.items, 0.0);

    try test_util.expectPathIntersectionsContains(PathIntersection{
        .shape_index = 0,
        .curve_index = 0,
        .is_end = false,
        .intersection = Intersection{
            .t = 0.3333333,
            .point = PointF32{
                .x = 1.0,
                .y = 3.0,
            },
        },
    }, path_intersections.items, test_util.DEFAULT_TOLERANCE);

    try test_util.expectPathIntersectionsContains(PathIntersection{
        .shape_index = 0,
        .curve_index = 0,
        .is_end = false,
        .intersection = Intersection{
            .t = 0.6666666,
            .point = PointF32{
                .x = 1.0,
                .y = 2.0,
            },
        },
    }, path_intersections.items, test_util.DEFAULT_TOLERANCE);

    try test_util.expectPathIntersectionsContains(PathIntersection{
        .shape_index = 0,
        .curve_index = 0,
        .is_end = false,
        .intersection = Intersection{
            .t = 1.0,
            .point = PointF32{
                .x = 1.0,
                .y = 1.0,
            },
        },
    }, path_intersections.items, 0.0);
}
