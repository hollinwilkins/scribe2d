const std = @import("std");
const path_module = @import("./path.zig");
const curve_module = @import("./curve.zig");
const core = @import("../core/root.zig");
const texture = @import("./texture.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const UnmanagedTexture = texture.UnmanagedTexture;
const TextureViewRgba = texture.TextureViewRgba;
const Path = path_module.Path;
const PointF32 = core.PointF32;
const PointU32 = core.PointU32;
const PointI32 = core.PointI32;
const DimensionsF32 = core.DimensionsF32;
const RectU32 = core.RectU32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const RangeI32 = core.RangeI32;
const Curve = curve_module.Curve;
const Line = curve_module.Line;

const PIXEL_TOLERANCE: f32 = 1e-6;
const BoundaryFragment = struct {
    pixel: PointI32,
    num_intersections: u8, // 1 or 2
    intersection1: PointF32 = PointF32{},
    intersection2: PointF32 = PointF32{},

    pub fn create(pixel: PointU32, intersection: PointF32) BoundaryFragment {
        return BoundaryFragment{
            .pixel = pixel,
            .num_intersections = 1,
            .intersection1 = intersection,
        };
    }
};
const BoundaryFragmentsList = std.ArrayList(BoundaryFragment);

pub const Pen = struct {
    pub fn drawToTextureViewRgba(self: *Pen, allocator: Allocator, path: Path, view: *TextureViewRgba) !void {
        _ = self;
        _ = allocator;
        _ = path;
        _ = view;
        return;
    }

    pub fn createBoundaryFragments(allocator: Allocator, path: Path, view: *TextureViewRgba) !void {
        const pixel_view_dimensions = view.getDimensions();
        const scaled_pixel_dimensions = DimensionsF32{
            .height = 1.0 / @as(f32, @floatFromInt(pixel_view_dimensions.height())),
            .width = 1.0 / @as(f32, @floatFromInt(pixel_view_dimensions.width())),
        };
        var boundary_fragments = try BoundaryFragmentsList.init(allocator);
        var previous_boundary_fragments: []BoundaryFragment = &.{};

        for (path.getCurves()) |curve| {
            const scaled_bounds = curve.getBounds();
            const pixel_y_range = RangeI32{
                .start = @intFromFloat(@ceil(scaled_bounds.min.y / scaled_pixel_dimensions.height)),
                .end = @intFromFloat(@floor(scaled_bounds.max.y / scaled_pixel_dimensions.height)),
            };

            const scaled_x_range = RangeF32{
                .start = scaled_bounds.min.x,
                .end = scaled_bounds.max.x,
            };

            if (scaled_bounds.min.y != 0.0) {
                // we don't start on the first actual scan line, this is the common case
                previous_boundary_fragments = try scanY(
                    curve,
                    scaled_bounds.min.y,
                    @intFromFloat(@floor(scaled_bounds.min.y / scaled_pixel_dimensions.height)),
                    scaled_pixel_dimensions,
                    scaled_x_range,
                    // disable x scanning for first virtual fragment
                    false,
                    // there are no previous fragments for the first
                    previous_boundary_fragments,
                    &boundary_fragments,
                );
            }

            // pixel_y is the scanline pixel
            for (0..pixel_y_range.size()) |pixel_y_offset| {
                const pixel_y: i32 = pixel_y_range.start + @as(i32, @intCast(pixel_y_offset));
                // scan the current pixel y line
                previous_boundary_fragments = try scanY(
                    curve,
                    @as(f32, @floatFromInt(pixel_y)) * scaled_pixel_dimensions.height,
                    scaled_pixel_dimensions,
                    scaled_x_range,
                    true,
                    previous_boundary_fragments,
                    &boundary_fragments,
                );
            }

            if (scaled_bounds.max.y != 1.0) {
                // we don't end on the last actual scan line, this is the common case
                previous_boundary_fragments = try scanY(
                    curve,
                    scaled_bounds.max.y,
                    pixel_y_range.end,
                    scaled_pixel_dimensions,
                    scaled_x_range,
                    true,
                    previous_boundary_fragments,
                    &boundary_fragments,
                );
            }
        }
    }

    // this will produce intersections on a horizontal pixel row
    // returns the array of new boundary fragments that were added
    fn scanY(
        curve: Curve,
        scaled_y: f32,
        pixel_y: i32,
        scaled_pixel_dimensions: DimensionsF32,
        scaled_x_range: RangeF32,
        enable_x_scanning: bool,
        previous_boundary_fragments: []BoundaryFragment,
        boundary_fragments: *BoundaryFragmentsList,
    ) ![]BoundaryFragment {
        var intersections_result: [3]PointF32 = [_]PointF32{undefined} ** 3;
        const intersections = curve.intersectLine(Line.create(
            PointF32{
                .x = scaled_x_range.start,
                .y = scaled_y,
            },
            PointF32{
                .x = scaled_x_range.end,
                .y = scaled_y,
            },
        ), &intersections_result);

        var new_boundary_fragments = RangeU32{
            .start = boundary_fragments.items.len,
            .end = boundary_fragments.items.len,
        };
        for (intersections) |intersection| {
            // set to true if we add this intersection to an existing boundary fragment
            var added_to_previous_boundary_fragment: bool = false;

            // calculate the current pixel where the intersection occurred
            const current_pixel = PointI32{
                .x = @intFromFloat(intersection.x / scaled_pixel_dimensions.width),
                .y = pixel_y,
            };

            // attempt to add intersection to previous boundary fragment if it occurs on a matching pixel
            for (previous_boundary_fragments) |*previous_boundary_fragment| {
                if (std.mem.eql(previous_boundary_fragment.pixel, current_pixel)) {
                    std.debug.assert(previous_boundary_fragment.num_intersections == 1);
                    previous_boundary_fragment.intersection2 = intersection;
                    added_to_previous_boundary_fragment = true;
                }
            }

            // if we did not add the intersection to a previous boundary fragment
            // then create a new boundary fragment and add it to the list
            // this indicates we need to do some scanning along x
            const ao = try boundary_fragments.addOne();
            ao.* = BoundaryFragment.create(current_pixel, intersection);
            new_boundary_fragments.end += 1;
        }

        // return the array of newly-created boundary fragments
        if (new_boundary_fragments.start < boundary_fragments.items.len) {
            if (enable_x_scanning) {
                var x_previous_boundary_fragments: []BoundaryFragment = &.{};
                // perform x scanning, we added some new fragments and need to
                const pixel_x_range = RangeI32{
                    .start = boundary_fragments.items[new_boundary_fragments.start].pixel.x + 1,
                    .end = boundary_fragments.items[new_boundary_fragments.end].pixel.x + 1,
                };

                std.debug.assert(pixel_x_range.start < pixel_x_range.end);

                for (0..pixel_x_range.size()) |pixel_x_offset| {
                    const pixel_x = pixel_x_range.start + @as(i32, @intCast(pixel_x_offset));
                    const pixel = PointI32{
                        .x = pixel_x,
                        .y = pixel_y,
                    };
                    x_previous_boundary_fragments = try scanPixelX(
                        curve,
                        pixel,
                        x_previous_boundary_fragments,
                        boundary_fragments,
                    );
                }
            }

            return boundary_fragments.items[new_boundary_fragments.start..new_boundary_fragments.end];
        } else {
            return &.{};
        }
    }

    fn scanPixelX(
        curve: Curve,
        pixel: PointU32,
        previous_boundary_fragments: []BoundaryFragment,
        boundary_fragments: *BoundaryFragmentsList,
    ) ![]BoundaryFragment {
        var intersections_result: [3]PointF32 = [_]PointF32{undefined} ** 3;
        const intersections = curve.intersectLine(Line.create(
            PointF32{
                .x = scaled_x_range.start,
                .y = scaled_y,
            },
            PointF32{
                .x = scaled_x_range.end,
                .y = scaled_y,
            },
        ), &intersections_result);
    }
};
