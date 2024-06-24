const std = @import("std");
const path_module = @import("./path.zig");
const soup = @import("./soup.zig");
const soup_raster = @import("./soup_raster.zig");
const texture_module = @import("./texture.zig");
const pen_module = @import("./pen.zig");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Color = texture_module.Color;
const ColorBlend = texture_module.ColorBlend;
const AlphaColorBlend = texture_module.AlphaColorBlend;
const Paths = path_module.Paths;
const TextureUnmanaged = texture_module.TextureUnmanaged;
const PointU32 = core.PointU32;
const LineSoup = soup.LineSoup;
const LineSoupRasterizer = soup_raster.LineSoupRasterizer;
const Style = pen_module.Style;
const PathMetadata = path_module.PathMetadata;

pub const SoupPen = struct {
    pub const DEFAULT_BLEND: ColorBlend = ColorBlend.Alpha;

    allocator: Allocator,
    rasterizer: *const LineSoupRasterizer,

    pub fn init(allocator: Allocator, rasterizer: *const LineSoupRasterizer) @This() {
        return @This(){
            .allocator = allocator,
            .rasterizer = rasterizer,
        };
    }

    pub fn deinit(self: *@This()) void {
        _ = self; // nothing needed for now
    }

    pub fn draw(
        self: @This(),
        line_soup: LineSoup,
        metadatas: []const PathMetadata,
        texture: *TextureUnmanaged,
    ) !void {
        var raster_data = try self.rasterizer.rasterizeAlloc(self.allocator, line_soup);
        defer raster_data.deinit();

        for (metadatas) |metadata| {
            const blend = DEFAULT_BLEND;
            const path_records = raster_data.path_records.items[metadata.path_offsets.start..metadata.path_offsets.end];

            for (path_records, 0..) |path_record, path_record_index| {
                const soup_path_record = line_soup.path_records.items[path_record_index];
                const color = soup_path_record.fill.color;
                const merge_fragments = raster_data.merge_fragments.items[path_record.merge_offsets.start..path_record.merge_offsets.end];
                const spans = raster_data.spans.items[path_record.span_offsets.start..path_record.span_offsets.end];

                for (merge_fragments) |merge_fragment| {
                    const pixel = merge_fragment.pixel;
                    if (pixel.x >= 0 and pixel.y >= 0) {
                        const intensity = merge_fragment.getIntensity();
                        const texture_pixel = PointU32{
                            .x = @intCast(pixel.x),
                            .y = @intCast(pixel.y),
                        };
                        const fragment_color = Color{
                            .r = color.r,
                            .g = color.g,
                            .b = color.b,
                            .a = color.a * intensity,
                        };
                        const texture_color = texture.getPixelUnsafe(texture_pixel);
                        const blend_color = blend.blend(fragment_color, texture_color);
                        texture.setPixelUnsafe(texture_pixel, blend_color);
                    }
                }

                for (spans) |span| {
                    for (0..span.x_range.size()) |x_offset| {
                        const x = @as(u32, @intCast(span.x_range.start)) + @as(u32, @intCast(x_offset));
                        texture.setPixelUnsafe(core.PointU32{
                            .x = @intCast(x),
                            .y = @intCast(span.y),
                        }, color);
                    }
                }
            }
        }
    }
};
