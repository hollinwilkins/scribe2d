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
const Curve = curve_module.Curve;
const Line = curve_module.Line;
const Intersection = curve_module.Intersection;

const PIXEL_TOLERANCE: f32 = 1e-6;
pub const IntersectionList = std.ArrayList(Intersection);

pub const Pen = struct {
    pub fn drawToTextureViewRgba(self: *Pen, allocator: Allocator, path: Path, view: *TextureViewRgba) !void {
        _ = self;
        _ = allocator;
        _ = path;
        _ = view;
        return;
    }

    pub fn createBoundaryFragments(allocator: Allocator, path: Path, view: *TextureViewRgba) !IntersectionList {
        var intersections = IntersectionList.init(allocator);
        errdefer intersections.deinit();

        const pixel_view_dimensions = view.getDimensions();
        const scaled_pixel_dimensions = DimensionsF32{
            .width = @floatFromInt(pixel_view_dimensions.width),
            .height = @floatFromInt(pixel_view_dimensions.height),
        };

        for (path.getCurves()) |curve| {
            const scaled_curve = curve.scale(scaled_pixel_dimensions);
            const scaled_curve_bounds = scaled_curve.getBounds();

            try scanX(
                scaled_curve_bounds.min.x,
                scaled_curve,
                scaled_curve_bounds,
                &intersections,
            );
            const grid_x_size: usize = @intFromFloat(scaled_curve_bounds.getWidth());
            const grid_x_start: i32 = @intFromFloat(scaled_curve_bounds.min.x);
            for (1..grid_x_size) |x_offset| {
                const grid_x = grid_x_start + @as(i32, @intCast(x_offset));
                try scanX(
                    @as(f32, @floatFromInt(grid_x)),
                    scaled_curve,
                    scaled_curve_bounds,
                    &intersections,
                );
            }
            try scanX(
                scaled_curve_bounds.max.x,
                scaled_curve,
                scaled_curve_bounds,
                &intersections,
            );

            try scanY(
                scaled_curve_bounds.min.y,
                scaled_curve,
                scaled_curve_bounds,
                &intersections,
            );
            const grid_y_size: usize = @intFromFloat(scaled_curve_bounds.getHeight());
            const grid_y_start: i32 = @intFromFloat(scaled_curve_bounds.min.y);
            for (1..grid_y_size) |y_offset| {
                const grid_y = grid_y_start + @as(i32, @intCast(y_offset));
                try scanY(
                    @as(f32, @floatFromInt(grid_y)),
                    scaled_curve,
                    scaled_curve_bounds,
                    &intersections,
                );
            }
            try scanY(
                scaled_curve_bounds.max.y,
                scaled_curve,
                scaled_curve_bounds,
                &intersections,
            );

            //     // build pixel fragments
        }

        return intersections;
    }

    fn scanX(
        grid_x: f32,
        curve: Curve,
        scaled_curve_bounds: RectF32,
        intersections: *IntersectionList,
    ) !void {
        var scaled_intersections_result: [3]Intersection = [_]Intersection{undefined} ** 3;
        const line = Line.create(
            PointF32{
                .x = grid_x,
                .y = scaled_curve_bounds.min.y,
            },
            PointF32{
                .x = grid_x,
                .y = scaled_curve_bounds.max.y,
            },
        );
        const scaled_intersections = curve.intersectLine(line, &scaled_intersections_result);

        for (scaled_intersections) |intersection| {
            const ao = try intersections.addOne();
            ao.* = intersection;
        }
    }

    fn scanY(
        grid_y: f32,
        curve: Curve,
        scaled_curve_bounds: RectF32,
        intersections: *IntersectionList,
    ) !void {
        var scaled_intersections_result: [3]Intersection = [_]Intersection{undefined} ** 3;
        const line = Line.create(
            PointF32{
                .x = scaled_curve_bounds.min.x,
                .y = grid_y,
            },
            PointF32{
                .x = scaled_curve_bounds.max.x,
                .y = grid_y,
            },
        );
        const scaled_intersections = curve.intersectLine(line, &scaled_intersections_result);

        for (scaled_intersections) |intersection| {
            const ao = try intersections.addOne();
            ao.* = intersection;
        }
    }
};

test "scan for intersections" {
    const UnmanagedTextureRgba = texture_module.UnmanagedTextureRgba;
    const DimensionsU32 = core.DimensionsU32;
    const PathOutliner = path_module.PathOutliner;

    var texture = try UnmanagedTextureRgba.create(std.testing.allocator, DimensionsU32{
        .width = 64,
        .height = 64,
    });
    defer texture.deinit(std.testing.allocator);
    var texture_view = texture.createView(RectU32.create(
        PointU32{
            .x = 0,
            .y = 0,
        },
        PointU32{
            .x = 64,
            .y = 64,
        },
    )).?;

    var path_outliner = try PathOutliner.init(std.testing.allocator);
    defer path_outliner.deinit();

    try path_outliner.moveTo(PointF32{
        .x = 0.0,
        .y = 0.0,
    });
    try path_outliner.lineTo(PointF32{
        .x = 1.0,
        .y = 1.0,
    });

    var path = try path_outliner.createPathAlloc(std.testing.allocator);
    defer path.deinit();

    var intersections = try Pen.createBoundaryFragments(std.testing.allocator, path, &texture_view);
    defer intersections.deinit();

    std.debug.print("\n============== Intersections\n", .{});
    for (intersections.items) |intersection| {
        std.debug.print("Intersection: {}\n", .{intersection});
    }
    std.debug.print("==============\n", .{});
}
