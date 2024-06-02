const std = @import("std");
const path_module = @import("./path.zig");
const core = @import("../core/root.zig");
const texture = @import("./texture.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const UnmanagedTexture = texture.UnmanagedTexture;
const TextureViewRgba = texture.TextureViewRgba;
const Path = path_module.Path;
const PointF32 = core.PointF32;
const PointU32 = core.PointU32;
const RectU32 = core.RectU32;

const BoundaryFragment = struct {};
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
        _ = allocator;
        _ = view;

        const pixel_view_dimensions = view.getDimensions();
        const scaled_pixel_height = 1.0 / @as(f32, @floatFromInt(pixel_view_dimensions.height()));
        var boundary_fragments = try BoundaryFragmentsList.init(allocator);
        var intersections_result: [3]PointF32 = [_]PointF32{undefined} ** 3;

        for (path.getSegments()) |segment| {
            const scaled_bounds = segment.getBounds();
            const pixel_y_start: u32 = @intFromFloat(@floor(scaled_bounds.min.y / scaled_pixel_height));
            const pixel_y_end: u32 = @intFromFloat(@ceil(scaled_bounds.max.y / scaled_pixel_height));

            // pixel_y is the scanline pixel
            for (pixel_y_start..pixel_y_end + 1) |pixel_y| {
                const scaled_y = @as(f32, @floatFromInt(pixel_y)) * scaled_pixel_height;
            }
        }
    }
};
