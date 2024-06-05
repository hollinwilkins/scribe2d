const std = @import("std");
const core = @import("../core/root.zig");
const texture_module = @import("./texture.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const PointF32 = core.PointF32;
const PointU32 = core.PointU32;
const DimensionsU32 = core.DimensionsU32;
const UnmanagedTexture = texture_module.UnmanagedTexture;

pub fn HalfPlanes(comptime T: type) type {
    const BitmaskTexture = UnmanagedTexture(T);

    return struct {
        allocator: Allocator,
        half_planes: BitmaskTexture,
        vertical_masks: []u16,

        pub fn create(allocator: Allocator, points: []const PointF32) !@This() {
            const size = @sizeOf(T) * 8 * 2;

            return @This(){
                .allocator = allocator,
                .half_planes = try createHalfPlanes(T, allocator, points, DimensionsU32{
                    .width = size,
                    .height = size,
                }),
                .vertical_masks = try createVerticalLookup(T, allocator, size, points),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.half_planes.deinit(self.allocator);
            self.allocator.free(self.vertical_masks);
        }

        pub fn getHalfPlaneMask(self: *@This(), point1: PointF32, point2: PointF32) u16 {
            var p0 = point1;
            var p1 = point2;

            if (p0.y < p1.y) {
                std.mem.swap(PointF32, &p0, &p1);
            }

            const d = p1.sub(p0);
            var n = d.normal();
            var c = n.dot(p0);
            c -= 0.5 * (n.x + n.y);
            var c_sign: f32 = 1.0;
            if (c < 0) {
                n = n.negate();
                c = -c;
                c_sign = -c_sign;
            }

            const n_rev_scale: f32 = @max(0.0, 1.0 - c * c_sign * @as(f32, @floatFromInt(self.half_planes.dimensions.width))) * c_sign;
            const n_rev = n.mul(PointF32{
                .x = n_rev_scale,
                .y = n_rev_scale,
            });
            const uv = n_rev.mul(PointF32{
                .x = 0.5,
                .y = 0.5,
            }).add(PointF32{
                .x = 0.5,
                .y = 0.5,
            });

            return self.half_planes.getPixel(PointU32{
                .x = @intFromFloat(uv.x),
                .y = @intFromFloat(uv.y),
            }).?.*;
        }

        pub fn getVerticalMask(self: *@This(), y: f32) u16 {
            const mod_y = std.math.modf(y);
            const index_f32: f32 = @round(mod_y.fpart * @as(f32, @floatFromInt(self.vertical_masks.len)));
            const index = @min(
                self.vertical_masks.len - 1,
                @max(0, @as(u32, @intFromFloat(index_f32))),
            );
            return self.vertical_masks[index];
        }
    };
}

pub const HalfPlanesU16 = HalfPlanes(u16);

pub fn createHalfPlanes(
    comptime T: type,
    allocator: Allocator,
    points: []const PointF32,
    dimensions: DimensionsU32,
) !UnmanagedTexture(T) {
    var texture = try UnmanagedTexture(T).create(allocator, dimensions);
    const origin = PointF32{
        .x = 0.5,
        .y = 0.5,
    };

    for (0..texture.pixels.len) |index| {
        // x,y in middle of texel
        const x: u32 = @intCast(index % dimensions.width);
        const y: u32 = @intCast(index / dimensions.width);
        const texel_x = (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(dimensions.width));
        const texel_y = (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(dimensions.height));
        const texel = PointF32{
            .x = texel_x,
            .y = texel_y,
        };
        const n = texel.sub(origin).normal();
        const c: f32 = 1.0 - 2.0 * (texel.sub(origin).dot(n));

        // calculate bitmask
        texture.getPixel(PointU32{
            .x = x,
            .y = y,
        }).?.* = calculateHalfPlaneBitmask(T, n, c, points);
    }

    return texture;
}

pub fn calculateHalfPlaneBitmask(comptime T: type, n: PointF32, c: f32, points: []const PointF32) T {
    var mask: T = 0;
    for (points, 0..) |point, i| {
        const v = n.dot(point.sub(PointF32{
            .x = 0.5,
            .y = 0.5,
        }));
        if (v > c) {
            mask = mask & (@as(u16, 1) << @as(u4, @intCast(i)));
        }
    }

    return mask;
}

pub fn createVerticalLookup(comptime T: type, allocator: Allocator, n: u32, points: []const PointF32) ![]T {
    var lookup = try allocator.alloc(T, n);

    for (0..n) |index| {
        var mask: T = 0;
        const y = @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(n));

        for (points, 0..) |point, point_index| {
            if (y <= point.y) {
                const mask_mod = (@as(T, 1) << @intCast(point_index));
                mask = mask | mask_mod;
            }
        }

        lookup[index] = mask;
    }

    return lookup;
}

pub const UV_SAMPLE_COUNT_1: [1]PointF32 = [1]PointF32{
    PointF32.create(0.5, 0.5),
};

pub const UV_SAMPLE_COUNT_2: [2]PointF32 = [2]PointF32{
    PointF32.create(0.75, 0.75),
    PointF32.create(0.25, 0.25),
};

pub const UV_SAMPLE_COUNT_4: [4]PointF32 = [4]PointF32{
    PointF32.create(0.375, 0.125),
    PointF32.create(0.875, 0.375),
    PointF32.create(0.125, 0.625),
    PointF32.create(0.625, 0.875),
};

pub const UV_SAMPLE_COUNT_8: [8]PointF32 = [8]PointF32{
    PointF32.create(0.5625, 0.3125),
    PointF32.create(0.4375, 0.6875),
    PointF32.create(0.8125, 0.5625),
    PointF32.create(0.3125, 0.1875),
    PointF32.create(0.1875, 0.8125),
    PointF32.create(0.0625, 0.4375),
    PointF32.create(0.6875, 0.9375),
    PointF32.create(0.9375, 0.0625),
};

pub const UV_SAMPLE_COUNT_16: [16]PointF32 = [16]PointF32{
    PointF32.create(0.5625, 0.5625),
    PointF32.create(0.4375, 0.3125),
    PointF32.create(0.3125, 0.625),
    PointF32.create(0.75, 0.4375),
    PointF32.create(0.1875, 0.375),
    PointF32.create(0.625, 0.8125),
    PointF32.create(0.8125, 0.6875),
    PointF32.create(0.6875, 0.1875),
    PointF32.create(0.375, 0.875),
    PointF32.create(0.5, 0.0625),
    PointF32.create(0.25, 0.125),
    PointF32.create(0.125, 0.75),
    PointF32.create(0.0, 0.5),
    PointF32.create(0.9375, 0.25),
    PointF32.create(0.875, 0.9375),
    PointF32.create(0.0625, 0.0),
};

test "16 bit msaa" {
    var half_planes = try HalfPlanesU16.create(std.testing.allocator, &UV_SAMPLE_COUNT_16);
    defer half_planes.deinit();

    try std.testing.expectEqual(0b1111111111111111, half_planes.getVerticalMask(0.0));
    try std.testing.expectEqual(0b0000000000000000, half_planes.getVerticalMask(1.9999999));
    try std.testing.expectEqual(0b0101100101100101, half_planes.getVerticalMask(52.5));
    try std.testing.expectEqual(0b0101100101101101, half_planes.getVerticalMask(0.4));
}
