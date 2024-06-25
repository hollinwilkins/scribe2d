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
            const diagonal = self.length();

            return @This(){
                .x = self.x / diagonal,
                .y = self.y / diagonal,
            };
        }

        pub fn length(self: @This()) f32 {
            return std.math.hypot(self.x, self.y);
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

        pub fn mulScalar(self: @This(), scalar: T) @This() {
            return @This(){
                .x = self.x * scalar,
                .y = self.y * scalar,
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

        pub fn rotate(self: @This(), theta: f32) @This() {
            const cos_theta = std.math.cos(theta);
            const sin_theta = std.math.sin(theta);

            return @This() {
                .x = (self.x * cos_theta) - (self.y * sin_theta),
                .y = (self.y * cos_theta) + (self.x * sin_theta),
            };
        }

        pub fn atan2(self: @This()) f32 {
            return std.math.atan2(self.y, self.x);
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

        pub fn size(self: @This()) usize {
            return self.getDimensions().size();
        }

        pub fn getAspectRatio(self: *const @This()) f64 {
            return @as(f64, self.getWidth()) / @as(f64, self.getHeight());
        }

        pub fn getDimensions(self: *const @This()) Dimensions(T) {
            return Dimensions(T){
                .width = self.max.x - self.min.x,
                .height = self.max.y - self.min.y,
            };
        }

        pub fn transform(self: @This(), t: Transform(T)) @This() {
            return @This(){
                .min = t.apply(self.min),
                .max = t.apply(self.max),
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
pub const RectI32 = Rect(i32);
pub const RectU32 = Rect(u32);

pub fn Transform(comptime T: type) type {
    return struct {
        pub const Matrix = struct {
            coefficients: [6]T = [_]T{undefined} ** 6,

            pub fn apply(self: @This(), point: P) P {
                const z = self.coefficients;
                const x = z[0] * point.x + z[2] * point.y + z[4];
                const y = z[1] * point.x + z[3] * point.y + z[5];

                return P{
                    .x = x,
                    .y = y,
                };
            }

            pub fn applyScale(self: @This(), point: P) P {
                return PointF32{
                    .x = self.coefficients[0] * point.x + self.coefficients[2] * point.y,
                    .y = self.coefficients[1] * point.x + self.coefficients[3] * point.y,
                };
            }

            pub fn getScale(self: @This()) T {
                const c = self.coefficients;
                const v1x = c[0] + c[3];
                const v2x = c[0] - c[3];
                const v1y = c[1] - c[2];
                const v2y = c[1] - c[2];

                return std.math.sqrt(v1x * v1x + v1y * v1y) + (v2x * v2x + v2y * v2y);
            }
        };

        const P = Point(T);
        const Scale = Point(T);
        const Rotation = Point(T);
        const Translation = Point(T);

        scale: Scale = Scale{
            .x = 1.0,
            .y = 1.0,
        },
        rotation: Rotation = Rotation{
            .x = 0.0,
            .y = 0.0,
        },
        translate: Translation = Translation{},

        pub fn apply(self: @This(), point: P) P {
            return P{
                .x = (self.scale.x * (point.x + self.translate.x)),
                .y = (self.scale.y * (point.y + self.translate.y)),
            };
        }

        // pub fn toMatrix(self: @This()) Matrix {
        // // let (x_axis, y_axis, z_axis) = Self::quat_to_axes(rotation);
        // // Self::from_cols(
        // //     x_axis.mul(scale.x),
        // //     y_axis.mul(scale.y),
        // //     z_axis.mul(scale.z),
        // //     Vec4::from((translation, 1.0)),
        // // )

        //     return Matrix{
        //         .coefficients = [_]T{
        //             scale.x * 
        //         },
        //     };
        // }
    };
}

pub const TransformF32 = Transform(f32);
