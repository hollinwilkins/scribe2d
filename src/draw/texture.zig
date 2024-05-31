const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const geometry = @import("./geometry.zig");
const DimensionsU32 = geometry.DimensionsU32;
const color = @import("./color.zig");

pub const RawTexture = Unmanaged;
pub const Unmanaged = struct {
    dimensions: DimensionsU32,
    data: []u8,

    pub fn create(allocator: Allocator, dimensions: DimensionsU32) !RawTexture {
        return RawTexture{ .dimensions = dimensions, .data = try allocator.alloc(
            u8,
        ) };
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.data);
    }
};

pub fn Texture(comptime T: type) type {
    return struct {
        allocator: Allocator,
        raw: RawTexture,

        pub fn init(allocator: Allocator, dimensions: DimensionsU32) !@This() {
            return @This(){
                .allocator = allocator,
                .raw = try RawTexture.create(allocator, dimensions),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.unmanaged.deinit(self.allocator);
        }

        pub fn getDimensions(self: *const @This()) DimensionsU32 {
            return self.raw.dimensions;
        }

        pub fn getData(self: *@This()) []T {
            return @alignCast(std.mem.bytesAsSlice(T, self.raw.data));
        }
    };
}

pub const TextureRgba = Texture(color.Rgba);
pub const TextureMonotone = Texture(color.Monotone);
