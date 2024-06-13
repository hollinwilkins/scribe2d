const std = @import("std");
const path_module = @import("./path.zig");
const raster = @import("./raster.zig");
const texture_module = @import("./texture.zig");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Rasterizer = raster.Rasterizer;
const Color = texture_module.Color;
const Path = path_module.Path;
const TextureUnmanaged = texture_module.TextureUnmanaged;
const PointU32 = core.PointU32;

pub const Style = struct {
    fill_color: ?Color = null,
};

pub const Pen = struct {
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

    pub fn draw(self: @This(), path: Path, texture: *TextureUnmanaged) !void {
        const options = self.rasterizerOptions();
        var raster_data = try self.rasterizer.rasterize(path, options);
        defer raster_data.deinit();

        if (options.fill) {
            const color = self.style.fill_color.?;
            for (raster_data.getBoundaryFragments()) |boundary_fragment| {
                const pixel = boundary_fragment.pixel;
                if (pixel.x >= 0 and pixel.y >= 0) {
                    // const intensity = 1.0 - boundary_fragment.getIntensity();
                    const is_set = texture.setPixel(PointU32{
                        .x = @intCast(pixel.x),
                        .y = @intCast(pixel.y),
                    }, color);
                    std.debug.assert(is_set);
                }
            }

            for (raster_data.getSpans()) |span| {
                for (0..span.x_range.size()) |x_offset| {
                    if (span.filled) {
                        const x = @as(u32, @intCast(span.x_range.start)) + @as(u32, @intCast(x_offset));
                        const is_set = texture.setPixel(core.PointU32{
                            .x = @intCast(x),
                            .y = @intCast(span.y),
                        }, color);
                        std.debug.assert(is_set);
                    }
                }
            }
        }
    }

    fn rasterizerOptions(self: @This()) Rasterizer.Options {
        return Rasterizer.Options{
            .fill = self.style.fill_color != null,
        };
    }
};
