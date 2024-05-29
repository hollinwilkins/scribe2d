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
        if (reader.read(u32)) |i| {
            switch (i) {
                0x00010000 | 0x74727565 => return .true_type,
                0x4F54544F => return .open_type,
                0x74746366 => return .font_collection,
                _ => return null,
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
                if (self.i < self.lazy_array.n) {
                    self.i += 1;
                    return self.lazy_array.get(self.i - 1);
                }

                return null;
            }
        };

        n: usize,
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
