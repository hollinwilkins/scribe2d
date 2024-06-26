const std = @import("std");
const core = @import("../core/root.zig");
const mem = std.mem;
const PointF32 = core.PointF32;

pub const Reader = struct {
    cursor: usize,
    data: []const u8,

    pub fn create(data: []const u8) Reader {
        return Reader{
            .cursor = 0,
            .data = data,
        };
    }

    pub fn tail(self: *Reader) []const u8 {
        return self.data[self.cursor..];
    }

    pub fn setCursor(self: *Reader, cursor: usize) void {
        self.cursor = cursor;
    }

    pub fn setCursorChecked(self: *Reader, cursor: usize) bool {
        if (cursor < self.data.len) {
            self.cursor = cursor;
            return true;
        }

        return false;
    }

    pub fn skip(self: *Reader, comptime T: type) void {
        self.skipN(@sizeOf(T));
    }

    pub fn skipN(self: *Reader, n: usize) void {
        self.cursor += n;
    }

    pub fn skipToEnd(self: *Reader) void {
        self.cursor = self.data.len;
    }

    pub fn skipChecked(self: *Reader, comptime T: type) bool {
        return self.skipCheckedN(@sizeOf(T));
    }

    pub fn skipCheckedN(self: *Reader, n: usize) bool {
        if (self.cursor + n <= self.data.len) {
            self.cursor += n;
            return true;
        }

        return false;
    }

    pub fn readN(self: *Reader, n: usize) ?[]const u8 {
        if (self.cursor + n <= self.data.len) {
            const bytes = self.data[self.cursor .. self.cursor + n];
            self.cursor += n;
            return bytes;
        }

        return null;
    }

    pub fn read(self: *Reader, comptime T: type) ?T {
        if (self.readN(@sizeOf(T))) |bytes| {
            return mem.bytesToValue(T, bytes);
        }

        return null;
    }

    pub fn readInt(self: *Reader, comptime T: type) ?T {
        if (self.readN(@sizeOf(T))) |bytes| {
            return mem.bigToNative(T, mem.bytesToValue(T, bytes));
        }

        return null;
    }
};

pub fn readRect(comptime T: type, reader: *Reader) ?core.Rect(T) {
    const x_min = reader.readInt(T) orelse return null;
    const y_min = reader.readInt(T) orelse return null;
    const x_max = reader.readInt(T) orelse return null;
    const y_max = reader.readInt(T) orelse return null;

    return core.Rect(T){
        .min = core.Point(T){
            .x = x_min,
            .y = y_min,
        },
        .max = core.Point(T){
            .x = x_max,
            .y = y_max,
        },
    };
}

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
        return std.meta.eql(self, Transform{});
    }

    pub fn apply(self: Transform, point: PointF32) PointF32 {
        return PointF32{
            .x = self.a * point.x + self.c * point.y + self.e,
            .y = self.b * point.x + self.d * point.y + self.f,
        };
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
        return @as(f32, @floatFromInt(self.value)) / 16384.0;
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

pub const Offset16 = struct {
    const ReadSize = @sizeOf(Offset16);

    offset: u16,

    pub fn read(reader: *Reader) ?Offset16 {
        const offset = reader.readInt(u16) orelse return null;

        return Offset16{
            .offset = offset,
        };
    }
};

pub const Offset32 = struct {
    const ReadSize = @sizeOf(Offset32);

    offset: u32,

    pub fn read(reader: *Reader) ?Offset32 {
        const offset = reader.readInt(u32) orelse return null;

        return Offset32{
            .offset = offset,
        };
    }
};

pub const Range = struct {
    start: usize,
    end: usize,
};

pub fn LazyIntArray(comptime T: type) type {
    return struct {
        const Self = @This();
        
        pub const Iter = struct {
            lazy_array: *const Self,
            i: usize,

            pub fn next(self: *@This()) ?T {
                if (self.i < self.lazy_array.data.len) {
                    self.i += 1;
                    return self.lazy_array.get(self.i - 1);
                }

                return null;
            }
        };

        data: []const T = &.{},

        pub fn get(self: @This(), index: usize) ?T {
            if (index < self.data.len) {
                return std.mem.bigToNative(T, self.data[index]);
            }

            return null;
        }

        pub fn last(self: @This()) ?T {
            if (self.data.len > 0) {
                return self.get(self.data.len - 1);
            }

            return null;
        }

        pub fn read(reader: *Reader, n: usize) ?@This() {
            const bytes = reader.readN(n * @sizeOf(T)) orelse return null;
            return @This(){
                .data = @alignCast(std.mem.bytesAsSlice(T, bytes)),
            };
        }

        pub fn iterator(self: *const @This()) Iter {
            return Iter{
                .lazy_array = self,
                .i = 0,
            };
        }
    };
}

pub fn LazyArray(comptime T: type) type {
    return struct {
        const Self = @This();
        const ItemSize = T.ReadSize;

        pub const Search = struct {
            index: usize,
            value: T,
        };

        pub const Iter = struct {
            array: *const Self,
            index: usize,

            pub fn next(self: *@This()) ?T {
                if (self.index < self.array.len) {
                    self.index += 1;
                    return self.array.get(self.index - 1);
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

        pub fn last(self: @This()) ?T {
            if (self.data.len > 0) {
                return self.get(self.data.len - 1);
            }

            return null;
        }

        pub fn read(reader: *Reader, n: usize) ?@This() {
            if (reader.readN(n * ItemSize)) |data| {
                return @This(){
                    .len = n,
                    .data = data,
                };
            }

            return null;
        }

        pub fn iterator(self: *const @This()) Iter {
            return Iter{
                .array = self,
                .index = 0,
            };
        }

        pub fn binarySearchBy(
            self: @This(),
            key: anytype,
            f: *const fn (@TypeOf(key), *const T) std.math.Order,
        ) ?Search {
            var size = self.len;
            if (size == 0) {
                return null;
            }

            var base: usize = 0;
            while (size > 1) {
                const half = size / 2;
                const mid = base + half;
                const item = self.get(mid) orelse return null;
                const cmp = f(key, &item);
                base = if (cmp == .gt) base else mid;
                size -= half;
            }

            const item = self.get(base) orelse return null;
            if (f(key, &item) == .eq) {
                return Search{
                    .index = base,
                    .value = item,
                };
            } else {
                return null;
            }
        }
    };
}
