const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const core = @import("../core/root.zig");
const DimensionsU32 = core.DimensionsU32;
const RectU32 = core.RectU32;
const PointU32 = core.PointU32;
const RangeU32 = core.RangeU32;
const color = @import("./color.zig");

pub fn TextureView(comptime T: type) type {
    const Self = @This();

    return struct {
        view: RectU32,
        texture: UnmanagedTexture(T),

        pub fn getDimensions(self: *const @This()) DimensionsU32 {
            return self.view.getDimensions();
        }

        pub fn getRow(self: *@This(), row: u32) ?[]T {
            if (row >= self.view.getHeight()) {
                return null;
            }

            if (self.texture.getRow(self.view.min.y + row)) |pixels| {
                return pixels[self.view.min.x..self.view.max.x];
            }

            return null;
        }

        pub fn getPixel(self: *@This(), point: PointU32) ?*T {
            if (point.x >= self.view.getHeight() or point.y >= self.view.getWidth()) {
                return null;
            }

            return self.getPixelUnsafe(point);
        }

        pub fn getPixelUnsafe(self: *@This(), point: PointU32) *T {
            return self.texture.getPixelUnsafe(self.view.min.add(point));
        }

        pub fn createView(self: *@This(), view: RectU32) ?@This() {
            if (!view.fitsInside(self.view)) {
                return null;
            }

            return @This(){
                .view = RectU32{
                    .min = PointU32{
                        .x = self.view.min.x + view.min.x,
                        .y = self.view.min.y + view.min.y,
                    },
                    .max = PointU32{
                        .x = self.view.min.x + view.max.x,
                        .y = self.view.min.y + view.max.y,
                    },
                },
                .texture = self.texture,
            };
        }

        pub fn rowIterator(self: *@This()) RowIterator {
            return RowIterator{
                .texture_view = self,
                .row = 0,
                .end_row = self.view.getHeight() -| 1,
            };
        }

        pub const RowIterator = struct {
            texture_view: *Self,
            row: u32,
            end_row: u32,

            pub fn next(self: *@This()) ?[]T {
                if (self.row > self.end_row) {
                    return null;
                }

                if (self.texture_view.getRow(self.row)) |row| {
                    self.row += 1;
                    return row;
                }

                return null;
            }
        };
    };
}

pub fn UnmanagedTexture(comptime T: type) type {
    return struct {
        dimensions: DimensionsU32,
        pixels: []T,

        pub fn create(allocator: Allocator, dimensions: DimensionsU32) !@This() {
            return @This(){
                .dimensions = dimensions,
                .pixels = try allocator.alloc(T, dimensions.size()),
            };
        }

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            allocator.free(self.pixels);
        }

        pub fn clear(self: *@This(), clear_pixel: T) void {
            for (self.pixels) |*pixel| {
                pixel.* = clear_pixel;
            }
        }

        pub fn getDimensions(self: *const @This()) DimensionsU32 {
            return self.dimensions;
        }

        pub fn getPixels(self: *@This()) []T {
            return self.pixels;
        }

        pub fn getPixel(self: *@This(), point: PointU32) ?*T {
            if (point.x >= self.dimensions.width or point.y >= self.dimensions.height) {
                return null;
            }

            return self.getPixelUnsafe(point);
        }

        pub fn getPixelUnsafe(self: *@This(), point: PointU32) *T {
            return &self.pixels[point.y * self.dimensions.width + point.x];
        }

        pub fn getRow(self: *@This(), row: u32) ?[]T {
            if (row > self.dimensions.height) {
                return null;
            }

            const start = row * self.dimensions.width;
            const end = start + self.dimensions.width;

            return self.pixels[start..end];
        }

        pub fn createView(self: *@This(), view: RectU32) ?TextureView(T) {
            if (view.max.x > self.dimensions.width or view.max.y > self.dimensions.height) {
                return null;
            }

            return TextureView(T){
                .view = view,
                .texture = self.*,
            };
        }
    };
}

pub const TextureViewRgba = TextureView(color.Rgba);
pub const TextureViewMonotone = TextureView(color.Monotone);

pub const UnmanagedTextureRgba = UnmanagedTexture(color.Rgba);
pub const UnmanagedTextureMonotone = UnmanagedTexture(color.Monotone);
