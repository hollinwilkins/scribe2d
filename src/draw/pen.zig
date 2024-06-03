const std = @import("std");
const path_module = @import("./path.zig");
const curve_module = @import("./curve.zig");
const core = @import("../core/root.zig");
const texture_module = @import("./texture.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TextureViewRgba = texture_module.TextureViewRgba;
const Path = path_module.Path;
const PointF32 = core.PointF32;
const PointU32 = core.PointU32;
const PointI32 = core.PointI32;
const DimensionsF32 = core.DimensionsF32;
const RectU32 = core.RectU32;
const RectF32 = core.RectF32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const RangeI32 = core.RangeI32;
const RangeUsize = core.RangeUsize;
const Curve = curve_module.Curve;
const Line = curve_module.Line;
const Intersection = curve_module.Intersection;

pub const PathIntersection = struct {
    path_id: u32,
    curve_index: u32,
    intersection: Intersection,

    pub fn getPixel(self: PathIntersection) PointI32 {
        return PointI32{
            .x = @intFromFloat(self.intersection.point.x),
            .y = @intFromFloat(self.intersection.point.y),
        };
    }
};
pub const PathIntersectionList = std.ArrayList(PathIntersection);

pub const BoundaryFragment = struct {
    path_id: u32,
    curve_index: u32,
    pixel: PointI32,
    intersection1: Intersection,
    intersection2: Intersection,
};
pub const BoundaryFragmentList = std.ArrayList(BoundaryFragment);

pub const Pen = struct {
    pub fn drawToTextureViewRgba(self: *Pen, allocator: Allocator, path: Path, view: *TextureViewRgba) !void {
        _ = self;
        _ = allocator;
        _ = path;
        _ = view;
        return;
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

        for (path.getCurves(), 0..) |curve, curve_index_usize| {
            const curve_index: u32 = @intCast(curve_index_usize);
            var curve_intersection_range = RangeUsize{
                .start = intersections.items.len,
                .end = intersections.items.len,
            };
            const scaled_curve = curve.invertY().scale(scaled_pixel_dimensions);
            const scaled_curve_bounds = scaled_curve.getBounds();

            // scan x lines within bounds
            try scanX(
                path.getId(),
                curve_index,
                scaled_curve_bounds.min.x,
                scaled_curve,
                scaled_curve_bounds,
                &intersections,
            );
            const grid_x_size: usize = @intFromFloat(scaled_curve_bounds.getWidth());
            const grid_x_start: i32 = @intFromFloat(scaled_curve_bounds.min.x);
            for (0..grid_x_size + 1) |x_offset| {
                const grid_x = grid_x_start + @as(i32, @intCast(x_offset));
                try scanX(
                    path.getId(),
                    curve_index,
                    @as(f32, @floatFromInt(grid_x)),
                    scaled_curve,
                    scaled_curve_bounds,
                    &intersections,
                );
            }
            try scanX(
                path.getId(),
                curve_index,
                scaled_curve_bounds.max.x,
                scaled_curve,
                scaled_curve_bounds,
                &intersections,
            );

            // insert monotonic cuts, which ensure there are segmented montonic curves
            for (scaled_curve.monotonicCuts(&monotonic_cuts)) |intersection| {
                const ao = try intersections.addOne();
                ao.* = PathIntersection{
                    .path_id = path.getId(),
                    .curve_index = curve_index,
                    .intersection = intersection,
                };
            }

            // scan y lines within bounds
            try scanY(
                path.getId(),
                curve_index,
                scaled_curve_bounds.min.y,
                scaled_curve,
                scaled_curve_bounds,
                &intersections,
            );
            const grid_y_size: usize = @intFromFloat(scaled_curve_bounds.getHeight());
            const grid_y_start: i32 = @intFromFloat(scaled_curve_bounds.min.y);
            for (0..grid_y_size + 1) |y_offset| {
                const grid_y = grid_y_start + @as(i32, @intCast(y_offset));
                try scanY(
                    path.getId(),
                    curve_index,
                    @as(f32, @floatFromInt(grid_y)),
                    scaled_curve,
                    scaled_curve_bounds,
                    &intersections,
                );
            }
            try scanY(
                path.getId(),
                curve_index,
                scaled_curve_bounds.max.y,
                scaled_curve,
                scaled_curve_bounds,
                &intersections,
            );

            curve_intersection_range.end = intersections.items.len;

            // sort by t
            std.mem.sort(
                PathIntersection,
                intersections.items[curve_intersection_range.start..curve_intersection_range.end],
                @as(u32, 0),
                pathIntersectionLessThan,
            );
        }

        return intersections;
    }

    fn pathIntersectionLessThan(_: u32, left: PathIntersection, right: PathIntersection) bool {
        return left.intersection.t < right.intersection.t;
    }

    // intersections must be sorted by curve_index, t
    pub fn createBoundaryFragmentsAlloc(allocator: Allocator, intersections: []const PathIntersection) !BoundaryFragmentList {
        var boundary_fragments = try BoundaryFragmentList.initCapacity(allocator, intersections.len - 1);

        for (0..intersections.len) |index| {
            if (index + 1 >= intersections.len) {
                break;
            }

            const intersection1 = intersections[index];
            const intersection2 = intersections[index + 1];
            if (std.meta.eql(intersection1.intersection.point, intersection2.intersection.point)) {
                continue;
            }

            const pixel = intersection1.getPixel().min(intersection2.getPixel());

            const ao = boundary_fragments.addOneAssumeCapacity();
            ao.* = BoundaryFragment{
                .path_id = intersection1.path_id,
                .curve_index = intersection1.curve_index,
                .pixel = pixel,
                .intersection1 = intersection1.intersection,
                .intersection2 = intersection2.intersection,
            };
        }

        // sort by path_id, y, x
        std.mem.sort(
            BoundaryFragment,
            boundary_fragments.items,
            @as(u32, 0),
            boundaryFragmentLessThan,
        );

        return boundary_fragments;
    }

    fn boundaryFragmentLessThan(_: u32, left: BoundaryFragment, right: BoundaryFragment) bool {
        if (left.path_id < right.path_id) {
            return true;
        } else if (left.path_id == right.path_id) {
            if (left.pixel.y < right.pixel.y) {
                return true;
            } else if (left.pixel.y == right.pixel.y) {
                return left.pixel.x < right.pixel.x;
            }
        }

        return false;
    }

    fn scanX(
        path_id: u32,
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
        const scaled_intersections = curve.intersectLine(line, &scaled_intersections_result);

        for (scaled_intersections) |intersection| {
            const ao = try intersections.addOne();
            ao.* = PathIntersection{
                .path_id = path_id,
                .curve_index = curve_index,
                .intersection = intersection,
            };
        }
    }

    fn scanY(
        path_id: u32,
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
        const scaled_intersections = curve.intersectLine(line, &scaled_intersections_result);

        for (scaled_intersections) |intersection| {
            const ao = try intersections.addOne();
            ao.* = PathIntersection{
                .path_id = path_id,
                .curve_index = curve_index,
                .intersection = intersection,
            };
        }
    }
};

test "scan for intersections" {
    const UnmanagedTextureRgba = texture_module.UnmanagedTextureRgba;
    const DimensionsU32 = core.DimensionsU32;
    const PathOutliner = path_module.PathOutliner;

    const dimensions = DimensionsU32{
        .width = 64,
        .height = 64,
    };

    var texture = try UnmanagedTextureRgba.create(std.testing.allocator, dimensions);
    defer texture.deinit(std.testing.allocator);
    var texture_view = texture.createView(RectU32.create(
        PointU32{
            .x = 0,
            .y = 0,
        },
        PointU32{
            .x = @intCast(dimensions.width),
            .y = @intCast(dimensions.height),
        },
    )).?;

    var path_outliner = try PathOutliner.init(std.testing.allocator);
    defer path_outliner.deinit();

    try path_outliner.moveTo(PointF32{
        .x = 0.25,
        .y = 0.25,
    });
    try path_outliner.quadTo(PointF32{
        .x = 0.75,
        .y = 0.25,
    }, PointF32{
        .x = 0.50,
        .y = 0.50,
    });
    try path_outliner.close();

    var path = try path_outliner.createPathAlloc(std.testing.allocator);
    defer path.deinit();

    const intersections = try Pen.createIntersections(std.testing.allocator, path, &texture_view);
    defer intersections.deinit();

    std.debug.print("\n============== Intersections\n", .{});
    for (intersections.items) |intersection| {
        std.debug.print("Intersection: t({}), ({} @ {})\n", .{
            intersection.intersection.t,
            intersection.intersection.point.x,
            intersection.intersection.point.y,
        });
    }
    std.debug.print("==============\n", .{});

    const boundary_fragments = try Pen.createBoundaryFragmentsAlloc(std.testing.allocator, intersections.items);
    defer boundary_fragments.deinit();

    std.debug.print("\n============== Boundary Fragments\n", .{});
    for (boundary_fragments.items) |fragment| {
        std.debug.print("Fragment: {}\n", .{fragment});
    }
    std.debug.print("==============\n", .{});

    std.debug.print("\n============== Boundary Fragments Map\n", .{});
    var bf_index: usize = 0;
    for (0..dimensions.height) |y| {
        while (bf_index < boundary_fragments.items.len and boundary_fragments.items[bf_index].pixel.y < y) {
            bf_index += 1;
        }

        for (0..dimensions.width) |x| {
            while (bf_index < boundary_fragments.items.len and boundary_fragments.items[bf_index].pixel.y == y and boundary_fragments.items[bf_index].pixel.x < x) {
                bf_index += 1;
            }

            if (bf_index < boundary_fragments.items.len) {
                const pixel = boundary_fragments.items[bf_index].pixel;
                if (pixel.y == y and pixel.x == x) {
                    std.debug.print("X", .{});
                } else {
                    std.debug.print(";", .{});
                }
            } else {
                std.debug.print(";", .{});
            }
        }

        std.debug.print("\n", .{});
    }
    std.debug.print("==============\n", .{});
}
