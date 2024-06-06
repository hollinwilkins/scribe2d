const std = @import("std");

pub fn Point(comptime T: type) type {
    return struct {
        x: T = 0,
        y: T = 0,

        pub fn create(x: T, y: T) @This() {
            return @This(){
                .x = x,
                .y = y,
            };
        }

        pub fn normalize(self: @This()) ?@This() {
            if (self.x == 0 and self.y == 0) {
                return null;
            }

            return self.normalizeUnsafe();
        }

        pub fn normalizeUnsafe(self: @This()) @This() {
            std.debug.assert(!(self.x == 0 and self.y == 0));
            const diagonal = std.math.sqrt(self.x * self.x + self.y * self.y);

            return @This(){
                .x = self.x / diagonal,
                .y = self.y / diagonal,
            };
        }

        pub fn negate(self: @This()) @This() {
            return @This(){
                .x = -self.x,
                .y = -self.y,
            };
        }

        pub fn dot(self: @This(), other: @This()) T {
            return self.x * other.x + self.y * other.y;
        }

        pub fn add(self: @This(), other: @This()) @This() {
            return @This(){
                .x = self.x + other.x,
                .y = self.y + other.y,
            };
        }

        pub fn sub(self: @This(), other: @This()) @This() {
            return @This(){
                .x = self.x - other.x,
                .y = self.y - other.y,
            };
        }

        pub fn mul(self: @This(), other: @This()) @This() {
            return @This(){
                .x = self.x * other.x,
                .y = self.y * other.y,
            };
        }

        pub fn min(self: @This(), other: @This()) @This() {
            return @This(){
                .x = @min(self.x, other.x),
                .y = @min(self.y, other.y),
            };
        }

        pub fn max(self: @This(), other: @This()) @This() {
            return @This(){
                .x = @max(self.x, other.x),
                .y = @max(self.y, other.y),
            };
        }

        pub fn invert(self: @This()) @This() {
            return @This(){
                .x = 1.0 - self.x,
                .y = 1.0 - self.y,
            };
        }

        pub fn invertX(self: @This()) @This() {
            return @This(){
                .x = 1.0 - self.x,
                .y = self.y,
            };
        }

        pub fn invertY(self: @This()) @This() {
            return @This(){
                .x = self.x,
                .y = 1.0 - self.y,
            };
        }

        pub fn lerp(self: @This(), other: @This(), t: T) @This() {
            return @This(){
                .x = self.x + t * (other.x - self.x),
                .y = self.y + t * (other.y - self.y),
            };
        }
    };
}

pub const PointF32 = Point(f32);
pub const PointI16 = Point(i16);
pub const PointU32 = Point(u32);
pub const PointI32 = Point(i32);

pub fn Dimensions(comptime T: type) type {
    return struct {
        width: T,
        height: T,

        pub fn create(width: T, height: T) ?@This() {
            const r = @mulWithOverflow(width, height);

            if (r[1] == 1) {
                return null;
            }

            return @This(){
                .width = width,
                .height = height,
            };
        }

        pub fn size(self: *const @This()) T {
            return self.width * self.height;
        }

        pub fn fitsInside(self: @This(), other: @This()) bool {
            return self.width <= other.width and self.height <= other.height;
        }
    };
}

pub const DimensionsF32 = Dimensions(f32);
pub const DimensionsUsize = Dimensions(usize);
pub const DimensionsU32 = Dimensions(u32);
pub const DimensionsU16 = Dimensions(u16);

pub fn Rect(comptime T: type) type {
    return struct {
        const P = Point(T);

        min: P = P{},
        max: P = P{},

        pub fn create(p1: P, p2: P) @This() {
            return @This(){
                .min = P{
                    .x = @min(p1.x, p2.x),
                    .y = @min(p1.y, p2.y),
                },
                .max = P{
                    .x = @max(p1.x, p2.x),
                    .y = @max(p1.y, p2.y),
                },
            };
        }

        pub fn getWidth(self: *const @This()) T {
            return self.max.x - self.min.x;
        }

        pub fn getHeight(self: *const @This()) T {
            return self.max.y - self.min.y;
        }

        pub fn getDimensions(self: *const @This()) Dimensions(T) {
            return Dimensions(T){
                .width = self.max.x - self.min.x,
                .height = self.max.y - self.min.y,
            };
        }

        pub fn fitsInside(self: @This(), other: @This()) bool {
            return self.getDimensions().fitsInside(other.getDimensions());
        }

        pub fn containsPoint(self: @This(), point: Point(T)) bool {
            return self.min.x <= point.x and self.max.x >= point.x and self.min.y <= point.y and self.max.y >= point.y;
        }

        pub fn extendBy(self: @This(), point: Point(T)) @This() {
            return @This(){
                .min = self.min.min(point),
                .max = self.max.max(point),
            };
        }
    };
}

pub const RectF32 = Rect(f32);
pub const RectI16 = Rect(i16);
pub const RectU32 = Rect(u32);
