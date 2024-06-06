const std = @import("std");
const core = @import("../core/root.zig");
const texture_module = @import("./texture.zig");
const curve = @import("./curve.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const PointF32 = core.PointF32;
const PointU32 = core.PointU32;
const DimensionsU32 = core.DimensionsU32;
const UnmanagedTexture = texture_module.UnmanagedTexture;
const Line = curve.Line;

pub fn HalfPlanes(comptime T: type) type {
    const BitmaskTexture = UnmanagedTexture(T);

    return struct {
        allocator: Allocator,
        half_planes: BitmaskTexture,
        vertical_masks: []u16,

        pub fn create(allocator: Allocator, points: []const PointF32) !@This() {
            const bit_size = @sizeOf(T) * 8;

            return @This(){
                .allocator = allocator,
                .half_planes = try createHalfPlanes(T, allocator, points, DimensionsU32{
                    .width = bit_size * 8,
                    .height = bit_size * 8,
                }),
                .vertical_masks = try createVerticalLookup(T, allocator, bit_size * 2, points),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.half_planes.deinit(self.allocator);
            self.allocator.free(self.vertical_masks);
        }

        pub fn getHalfPlaneMask(self: *@This(), point1: PointF32, point2: PointF32) u16 {
            var p0 = point1;
            var p1 = point2;

            if (p0.y > p1.y) {
                std.mem.swap(PointF32, &p0, &p1);
            }

            if (Line.create(p0, p1).getNormal().normalize()) |n_n| {
                var n = n_n;
                var c = n.dot(p0);
                c -= 0.5 * (n.x + n.y);

                if (c < 0) {
                    c = -c;
                    n = n.negate();
                }

                const uv = n.mul(PointF32{
                    .x = c,
                    .y = c,
                }).add(PointF32{
                    .x = 0.5,
                    .y = 0.5,
                });
                const texel_coord = PointU32{
                    .x = @intFromFloat(@round(uv.x * @as(f32, @floatFromInt(self.half_planes.dimensions.width)))),
                    .y = @intFromFloat(@round(uv.y * @as(f32, @floatFromInt(self.half_planes.dimensions.height)))),
                };

                return self.half_planes.getPixel(texel_coord).?.*;
            } else {
                return 0;
            }
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

        pub fn getTrapezoidMask(self: *@This(), line: Line) u16 {
            const top_y = @min(line.start.y, line.end.y);
            const bottom_y = @max(line.start.y, line.end.y);

            const top_mask = self.getVerticalMask(top_y);
            const bottom_mask = ~self.getVerticalMask(bottom_y);
            const line_mask = self.getHalfPlaneMask(line.start, line.end);

            return top_mask & bottom_mask & line_mask;
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
        const uv = PointF32{
            .x = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(dimensions.width)),
            .y = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(dimensions.height)),
        };

        const t = uv.sub(origin);
        var mask: T = 0;
        if (t.normalize()) |n| {
            const c = n.dot(t);
            mask = calculateHalfPlaneBitmask(T, n, c, points);
        }

        texture.getPixel(PointU32{
            .x = x,
            .y = y,
        }).?.* = mask;
    }

    return texture;
}

pub fn calculateHalfPlaneBitmask(comptime T: type, n: PointF32, c: f32, points: []const PointF32) T {
    var mask: T = 0;
    for (points, 0..) |point, i| {
        const t = point.sub(PointF32{
            .x = 0.5,
            .y = 0.5,
        });
        const v = n.dot(t);
        if (v > c) {
            mask = mask | (@as(u16, 1) << @as(u4, @intCast(i)));
        }
    }

    if (n.x < 0) {
        mask = ~mask;
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

    const hp_top_left = half_planes.getHalfPlaneMask(PointF32{
        .x = 0.0,
        .y = 0.5,
    }, PointF32{
        .x = 0.5,
        .y = 0.0,
    });
    try std.testing.expectEqual(0b0111101111111111, hp_top_left);

    const hp_bottom_left = half_planes.getHalfPlaneMask(PointF32{
        .x = 0.0,
        .y = 0.5,
    }, PointF32{
        .x = 0.5,
        .y = 1.0,
    });
    try std.testing.expectEqual(0b1111011111111111, hp_bottom_left);

    const hp_top_right = half_planes.getHalfPlaneMask(PointF32{
        .x = 0.5,
        .y = 0.0,
    }, PointF32{
        .x = 1.0,
        .y = 0.5,
    });
    try std.testing.expectEqual(0b0010000000000000, hp_top_right);

    const hp_bottom_right = half_planes.getHalfPlaneMask(PointF32{
        .x = 1.0,
        .y = 0.5,
    }, PointF32{
        .x = 0.5,
        .y = 1.0,
    });
    try std.testing.expectEqual(0b0100000000000000, hp_bottom_right);

    const trap1 = half_planes.getTrapezoidMask(Line.create(PointF32{
        .x = 0.1,
        .y = 0.9,
    }, PointF32{
        .x = 0.9,
        .y = 0.2,
    }));
    try std.testing.expectEqual(0b0010000101101001, trap1);

    const trap2 = half_planes.getTrapezoidMask(Line.create(PointF32{
        .x = 0.5,
        .y = 0.6,
    }, PointF32{
        .x = 0.9,
        .y = 0.2,
    }));
    try std.testing.expectEqual(0b0010000000001001, trap2);

    const trap3 = half_planes.getTrapezoidMask(Line.create(PointF32{
        .x = 0.5,
        .y = 0.4,
    }, PointF32{
        .x = 0.9,
        .y = 0.2,
    }));
    try std.testing.expectEqual(0b0010000000000000, trap3);
}
