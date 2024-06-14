const std = @import("std");
const path_module = @import("./path.zig");
const raster = @import("./raster.zig");
const texture_module = @import("./texture.zig");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Rasterizer = raster.Rasterizer;
const Color = texture_module.Color;
const ColorBlend = texture_module.ColorBlend;
const AlphaColorBlend = texture_module.AlphaColorBlend;
const Paths = path_module.Paths;
const TextureUnmanaged = texture_module.TextureUnmanaged;
const PointU32 = core.PointU32;
const RasterData = raster.RasterData;

pub const Style = struct {
    pub const Stroke = struct {
        color: Color,
        width: f32,
};

    fill_color: ?Color = null,
    stroke: ?Stroke = null,
    blend: ?ColorBlend = null,
};

pub const Pen = struct {
    pub const DEFAULT_BLEND: ColorBlend = ColorBlend.Alpha;

    rasterizer: *const Rasterizer,
    style: Style = Style{},

    pub fn create(rasterizer: *const Rasterizer) Pen {
        return Pen{
            .rasterizer = rasterizer,
        };
    }

    pub fn setFillColor(self: *Pen, color: ?Color) void {
        self.style.fill_color = color;
    }

    pub fn draw(self: @This(), paths: Paths, path_index: u32, texture: *TextureUnmanaged) !void {
        if (self.style.fill_color) |color| {
            try self.drawFill( paths, path_index, texture, color);
        }

        if (self.style.stroke) |stroke| {
            try self.drawStroke(paths, path_index, texture, stroke);
        }
    }

    fn drawFill(self: @This(), paths: Paths, path_index: u32, texture: *TextureUnmanaged, color: Color) !void {
        var raster_data = try self.rasterizer.rasterize(paths, path_index);
        defer raster_data.deinit();

        const blend = self.style.blend orelse DEFAULT_BLEND;
        for (raster_data.getBoundaryFragments()) |boundary_fragment| {
            const pixel = boundary_fragment.pixel;
            if (pixel.x >= 0 and pixel.y >= 0) {
                const intensity = boundary_fragment.getIntensity();
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

        for (raster_data.getSpans()) |span| {
            for (0..span.x_range.size()) |x_offset| {
                const x = @as(u32, @intCast(span.x_range.start)) + @as(u32, @intCast(x_offset));
                texture.setPixelUnsafe(core.PointU32{
                    .x = @intCast(x),
                    .y = @intCast(span.y),
                }, color);
            }
        }
    }

    pub fn drawStroke(self: @This(), paths: Paths, path_index: u32, texture: *TextureUnmanaged, stroke: Style.Stroke) !void {
        _ = self;
        _ = paths;
        _ = path_index;
        _ = texture;
        _ = stroke;
    }
};
