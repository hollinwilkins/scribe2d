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

const OutlinePoint = struct {
    point: PointF32 = PointF32{},
    num_segments: u16 = 0,
    distance: f32 = 0.0,
};

const UnmanagedOutlinePointTexture = UnmanagedTexture(OutlinePoint);

pub const Pen = struct {
    pub fn drawToTextureViewRgba(self: *Pen, allocator: Allocator, path: Path, view: *TextureViewRgba) !void {
        _ = self;
        const view_dimensions = view.getDimensions();
        const view_scale_width: f32 = @floatFromInt(view_dimensions.width);
        const view_scale_height: f32 = @floatFromInt(view_dimensions.height);

        var points_outline = try UnmanagedOutlinePointTexture.create(allocator, view.getDimensions());
        defer points_outline.deinit(allocator);
        points_outline.clear(OutlinePoint{});

        for (path.segments()) |segment| {
            const segment_bounds = segment.getBounds();
            const scaled_segment_bounds = RectU32{
                .min = PointU32{
                    .x = @intFromFloat(@floor(segment_bounds.min.x * view_scale_width)),
                    .y = @intFromFloat(@floor(segment_bounds.min.y * view_scale_height)),
                },
                .max = PointU32{
                    .x = @intFromFloat(@ceil(segment_bounds.max.x * view_scale_width)),
                    .y = @intFromFloat(@ceil(segment_bounds.max.y * view_scale_height)),
                },
            };

            if (view.createView(scaled_segment_bounds)) |segment_view| {
                // outline all segments in the outline point texture
                // this will be used to:
                //   1. determine if a point is inside or outside of the path
                //   2. calculate distance field from pixels to closest segment
                if (points_outline.createView(scaled_segment_bounds)) |pov| {
                    var points_outline_view = pov;

                    // move along the x-axis of the segment pixels, calculating y
                    // save data into the points_outline_view

                    const segment_view_dimensions = segment_view.getDimensions();
                    const scale_segment_view_x: f32 = @floatFromInt(segment_view_dimensions.width);
                    const scale_segment_view_y: f32 = @floatFromInt(segment_view_dimensions.height);
                    for (0..segment_view_dimensions.width) |x| {
                        // calculate at the middle of the pixel
                        // check_x is in range [0.0,1.0]
                        const check_x: f32 = (@as(f32, @floatFromInt(x)) + 0.5) / scale_segment_view_x;

                        // y is in range [0.0,1.0]
                        const y = segment.applyX(check_x);

                        const scaled_x = check_x * scale_segment_view_x;
                        const scaled_y = y * scale_segment_view_y;

                        const pixel_x: u32 = @min(@as(u32, @intFromFloat(@round(scaled_x))), segment_view_dimensions.width);
                        const pixel_y: u32 = @min(@as(u32, @intFromFloat(@round(scaled_y))), segment_view_dimensions.height);

                        // we have already bounded x,y to the view dimensions
                        var pixel = points_outline_view.getPixelUnsafe(PointU32{
                            .x = pixel_x,
                            .y = pixel_y,
                        });

                        // write texture coordinates, not view coordinates
                        pixel.point = PointF32{
                            .x = scaled_x + @as(f32, @floatFromInt(scaled_segment_bounds.min.x)),
                            .y = scaled_y + @as(f32, @floatFromInt(scaled_segment_bounds.min.x)),
                        };
                        pixel.num_segments += 1;
                    }
                }
            }

            std.debug.print("Done!\n", .{});
        }

        // for (path.segments()) |segment| {

        // }
    }
};
