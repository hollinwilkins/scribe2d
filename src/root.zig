const std = @import("std");
const Face = @import("./Face.zig");
const testing = std.testing;
pub const table = @import("./table.zig");
pub const OutlineBuilder = @import("./OutlineBuilder.zig");
pub const Reader = @import("./Reader.zig");

pub const Error = error{
    FaceMagicError,
    FaceParsingError,
    MalformedFont,
    FaceIndexOutOfBounds,
    MissingRequiredTable,
    InvalidTable,
};

pub const GlyphId = u16;
pub const Range = struct {
    start: usize,
    end: usize,
};

pub const Transform = struct {
    /// The 'a' component of the transform.
    a: f32 = 1.0,
    /// The 'b' component of the transform.
    b: f32 = 0.0,
    /// The 'c' component of the transform.
    c: f32 = 0.0,
    /// The 'd' component of the transform.
    d: f32 = 1.0,
    /// The 'e' component of the transform.
    e: f32 = 0.0,
    /// The 'f' component of the transform.
    f: f32 = 0.0,

    pub fn isDefault(self: Transform) bool {
        return self == Transform{};
    }

    pub fn applyTo(self: Transform, x: *f32, y: *f32) void {
        const tx = *x;
        const ty = *y;
        x.* = self.a * tx + self.c * ty + self.e;
        y.* = self.b * tx + self.d * ty + self.f;
    }

    pub fn combine(self: Transform, other: Transform) Transform {
        return Transform{
            .a = self.a * other.a + self.c * other.b,
            .b = self.b * other.a + self.d * other.b,
            .c = self.a * other.c + self.c * other.d,
            .d = self.b * other.c + self.d * other.d,
            .e = self.a * other.e + self.c * other.f + self.e,
            .f = self.b * other.e + self.d * other.f + self.f,
        };
    }
};

pub const F2DOT14 = struct {
    value: i16,

    pub fn toF32(self: F2DOT14) f32 {
        return @as(f32, self.value) / 16384.0;
    }

    pub fn applyFloatDelta(self: F2DOT14, delta: f32) f32 {
        return self.toF32() + @as(f32, (@as(f64, delta) * (1.0 / 16384.0)));
    }

    pub fn read(reader: *Reader) ?F2DOT14 {
        const value = reader.readInt(i16) orelse return null;
        return F2DOT14{
            .value = value,
        };
    }
};

pub fn Rect(comptime T: type) type {
    return struct {
        x_min: T = 0,
        y_min: T = 0,
        x_max: T = 0,
        y_max: T = 0,

        pub fn create(x1: i16, x2: i16, y1: i16, y2: i16) @This() {
            return @This(){
                .x_min = @min(x1, x2),
                .y_min = @min(y1, y2),
                .x_max = @max(x1, x2),
                .y_max = @max(y1, y2),
            };
        }

        pub fn read(reader: *Reader) ?@This() {
            const x_min = reader.readInt(T) orelse return null;
            const y_min = reader.readInt(T) orelse return null;
            const x_max = reader.readInt(T) orelse return null;
            const y_max = reader.readInt(T) orelse return null;

            return @This(){
                .x_min = x_min,
                .y_min = y_min,
                .x_max = x_max,
                .y_max = y_max,
            };
        }

        // NOTE: can we use SIMD/NEON to make some of these functions more faster
        pub fn extendBy(self: *@This(), x: T, y: T) void {
            self.x_min = @min(self.x_min, x);
            self.y_min = @min(self.y_min, y);
            self.x_max = @min(self.x_max, x);
            self.y_max = @min(self.y_max, y);
        }
    };
}

pub const RectI16 = Rect(i16);
pub const RectF32 = Rect(f32);

pub fn Point(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        pub fn lerp(self: @This(), other: Point, t: T) @This() {
            return @This(){
                .x = self.x + t * (other.x - self.x),
                .y = self.y + t * (other.y - self.y),
            };
        }
    };
}

pub const PointF32 = Point(f32);

pub const Fixed = struct {
    value: f32,

    pub fn read(reader: *Reader) ?Fixed {
        const i = reader.read(i32) orelse return null;
        return createI32(i);
    }

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

pub const Offset32 = struct {
    const ReadSize = @sizeOf(Offset32);

    offset: u32,

    pub fn read(reader: *Reader) ?Offset32 {
        const offset = reader.read(u32) orelse return null;

        return Offset32{
            .offset = offset,
        };
    }
};

pub const Magic = enum {
    true_type,
    open_type,
    font_collection,

    pub fn read(reader: *Reader) ?Magic {
        if (reader.readInt(u32)) |i| {
            switch (i) {
                0x00010000 => return .true_type,
                0x74727565 => return .true_type,
                0x4F54544F => return .open_type,
                0x74746366 => return .font_collection,
                else => return null,
            }
        }

        return null;
    }
};

pub fn LazyArray(comptime T: type) type {
    return struct {
        const Self = @This();
        const ItemSize = T.ReadSize;

        pub const Iter = struct {
            lazy_array: *const Self,
            i: usize,

            pub fn next(self: *@This()) ?T {
                if (self.i < self.lazy_array.len) {
                    self.i += 1;
                    return self.lazy_array.get(self.i - 1);
                }

                return null;
            }
        };

        len: usize,
        data: []const u8,

        pub fn get(self: @This(), i: usize) ?T {
            const offset = i * ItemSize;
            const data = self.data[offset .. offset + ItemSize];
            var reader = Reader.create(data);
            return T.read(&reader);
        }

        pub fn read(reader: *Reader, n: usize) ?@This() {
            if (reader.readN(n * ItemSize)) |data| {
                return @This(){
                    .n = n,
                    .data = data,
                };
            }

            return null;
        }

        pub fn iterator(self: *const @This()) Iter {
            return Iter{
                .lazy_array = self,
                .i = 0,
            };
        }
    };
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test {
    std.testing.refAllDecls(Face);
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}
