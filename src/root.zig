const std = @import("std");
const Face = @import("./Face.zig");
const testing = std.testing;
pub const Reader = @import("./Reader.zig");

pub const Rect = struct {
    x_min: i16 = 0,
    y_min: i16 = 0,
    x_max: i16 = 0,
    y_max: i16 = 0,

    pub fn create(x1: i16, x2: i16, y1: i16, y2: i16) Rect {
        return Rect{
            .x_min = @min(x1, x2),
            .y_min = @min(y1, y2),
            .x_max = @max(x1, x2),
            .y_max = @max(y1, y2),
        };
    }
};

pub const Fixed = struct {
    value: f32,

    pub fn createI32(i: i32) Fixed {
        return Fixed{
            .value = @as(f32, @floatFromInt(i)) / 65536.0,
        };
    }

    pub fn addDelta(self: Fixed, delta: f32) Fixed {
        return Fixed{
            .value = self.value + @as(f32, @as(f64, delta) * (1.0 / 65536.0)),
        };
    }
};

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test {
    std.testing.refAllDecls(Face);
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
