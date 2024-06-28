const std = @import("std");
const path_module = @import("./path.zig");
const soup_module = @import("./soup.zig");
const soup_raster = @import("./soup_raster.zig");
const texture_module = @import("./texture.zig");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Color = texture_module.Color;
const ColorBlend = texture_module.ColorBlend;
const AlphaColorBlend = texture_module.AlphaColorBlend;
const Paths = path_module.Paths;
const TextureUnmanaged = texture_module.TextureUnmanaged;
const PointU32 = core.PointU32;
const LineSoup = soup_module.LineSoup;
const LineSoupRasterizer = soup_raster.LineSoupRasterizer;
const PathMetadata = path_module.PathMetadata;

pub const Style = struct {
    pub const Cap = enum(u8) {
        butt = 0,
        square = 1,
        round = 2,
    };

    pub const Join = enum(u8) {
        bevel = 0,
        miter = 1,
        round = 2,
    };

    pub const Fill = struct {
        color: Color = Color.BLACK,
    };

    pub const Stroke = struct {
        color: Color = Color.BLACK,
        width: f32 = 1.0,
        start_cap: Cap = .butt,
        end_cap: Cap = .butt,
        join: Join = .round,
        miter_limit: f32 = 4.0,

        pub fn toFill(self: @This()) Fill {
            return Fill{
                .color = self.color,
            };
        }
    };

    fill: ?Fill = null,
    stroke: ?Stroke = null,
    blend: ?ColorBlend = null,

    pub fn isFilled(self: @This()) bool {
        return self.fill != null;
    }

    pub fn isStroked(self: @This()) bool {
        return self.stroke != null;
    }
};

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
        line_soup: *LineSoup,
        texture: *TextureUnmanaged,
    ) !void {
        try self.rasterizer.rasterize(line_soup);

        const blend = DEFAULT_BLEND;

        for (line_soup.path_records.items) |path_record| {
            const color = path_record.fill.color;
            const merge_fragments = line_soup.merge_fragments.items[path_record.merge_offsets.start..path_record.merge_offsets.end];

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

            const spans = line_soup.spans.items[path_record.span_offsets.start..path_record.span_offsets.end];
            for (spans) |span| {
                for (0..span.x_range.size()) |x_offset| {
                    const x = @as(i32, @intCast(span.x_range.start)) + @as(i32, @intCast(x_offset));

                    if (x >= 0 and span.y >= 0) {
                        const texture_pixel = core.PointU32{
                            .x = @intCast(x),
                            .y = @intCast(span.y),
                        };
                        const texture_color = texture.getPixelUnsafe(texture_pixel);
                        const blend_color = blend.blend(color, texture_color);
                        texture.setPixelUnsafe(texture_pixel, blend_color);
                    }
                }
            }
        }
    }
};
