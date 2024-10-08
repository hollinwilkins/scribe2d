const std = @import("std");

pub fn Point(comptime T: type) type {
    return extern struct {
        pub const T_MIN: T = switch (@typeInfo(T)) {
            .Int => |_| std.math.minInt(T),
            .Float => |_| std.math.floatMin(T),
            else => @panic("Point(T): T must be a Float or Int"),
        };

        pub const T_MAX: T = switch (@typeInfo(T)) {
            .Int => |_| std.math.maxInt(T),
            .Float => |_| std.math.floatMax(T),
            else => @panic("Point(T): T must be a Float or Int"),
        };

        pub const MIN: @This() = @This(){
            .x = T_MIN,
            .y = T_MIN,
        };
        pub const MAX: @This() = @This(){
            .x = T_MAX,
            .y = T_MAX,
        };

        x: T = 0,
        y: T = 0,

        pub fn create(x: T, y: T) @This() {
            return @This(){
                .x = x,
                .y = y,
            };
        }

        pub fn cast(self: @This(), comptime T2: type) Point(T2) {
            switch (@typeInfo(T)) {
                .Float => |_| {
                    switch (@typeInfo(T2)) {
                        .Float => |_| {
                            return Point(T2){
                                .x = @floatCast(self.x),
                                .y = @floatCast(self.y),
                            };
                        },
                        .Int => |_| {
                            return Point(T2){
                                .x = @intFromFloat(self.x),
                                .y = @intFromFloat(self.y),
                            };
                        },
                        else => @panic("Must cast to float or int type"),
                    }
                },
                .Int => |_| {
                    switch (@typeInfo(T2)) {
                        .Float => |_| {
                            return Point(T2){
                                .x = @floatFromInt(self.x),
                                .y = @floatFromInt(self.y),
                            };
                        },
                        .Int => |_| {
                            return Point(T2){
                                .x = @intCast(self.x),
                                .y = @intCast(self.y),
                            };
                        },
                        else => @panic("Must cast to float or int type"),
                    }
                },
                else => @panic("Must cast from float or int type"),
            }
        }

        pub fn approxEqAbs(self: @This(), other: @This(), tolerance: T) bool {
            return std.math.approxEqAbs(
                T,
                self.x,
                other.x,
                tolerance,
            ) and std.math.approxEqAbs(
                T,
                self.y,
                other.y,
                tolerance,
            );
        }

        pub fn reflectOn(self: @This(), other: @This()) @This() {
            return other.add(other.sub(self));
        }

        pub fn affineTransform(self: @This(), transform: Transform(T).Affine) @This() {
            return transform.apply(self);
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

        pub fn lengthSquared(self: @This()) f32 {
            return self.dot(self);
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

        pub fn divScalar(self: @This(), scalar: T) @This() {
            return @This(){
                .x = self.x / scalar,
                .y = self.y / scalar,
            };
        }

        pub fn floor(self: @This()) @This() {
            return @This() {
                .x = @floor(self.x),
                .y = @floor(self.y),
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

            return @This(){
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
    return extern struct {
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
    return extern struct {
        pub const NONE: @This() = @This(){
            .min = P.MAX,
            .max = P.MIN,
        };

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

        pub fn affineTransform(self: @This(), t: Transform(T).Affine) @This() {
            const p0 = self.min.affineTransform(t);
            const p1 = self.max.affineTransform(t);

            return @This().create(p0, p1);
        }

        pub fn transformMatrixInPlace(self: *@This(), t: Transform(T).Matrix) void {
            const p0 = t.apply(self.min);
            const p1 = t.apply(self.max);

            self.min = p0.min(p1);
            self.max = p0.max(p1);
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

        pub fn extendByInPlace(self: *@This(), point: Point(T)) void {
            self.min = self.min.min(point);
            self.max = self.max.max(point);
        }
    };
}

pub const RectF32 = Rect(f32);
pub const RectI16 = Rect(i16);
pub const RectI32 = Rect(i32);
pub const RectU32 = Rect(u32);

pub fn Transform(comptime T: type) type {
    return extern struct {
        const SelfTransform = @This();

        pub const Matrix = extern struct {
            pub const IDENTITY: Matrix = (SelfTransform{}).toMatrix();

            coefficients: [6]T = [_]T{undefined} ** 6,

            pub fn apply(self: @This(), point: P) P {
                const z = self.coefficients;
                const x = z[0] * point.x + z[1] * point.y + z[2];
                const y = z[3] * point.x + z[4] * point.y + z[5];

                // const x = z[0] * point.x + z[3] * point.y + z[2];
                // const y = z[1] * point.x + z[4] * point.y + z[5];

                if (x > 10000 or y > 10000) {
                    std.debug.assert(true);
                    std.debug.assert(true);
                }

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
                // TODO: does this actually make sense?
                const c = self.coefficients;
                const v1x = c[0] + c[4];
                const v2x = c[0] - c[4];
                const v1y = c[1] - c[3];
                const v2y = c[1] + c[3];

                return std.math.sqrt(v1x * v1x + v1y * v1y) + std.math.sqrt(v2x * v2x + v2y * v2y);
            }

            pub fn mul(self: @This(), other: @This()) @This() {
                const a = self.coefficients;
                const b = other.coefficients;

                return @This(){
                    .coefficients = [_]T{
                        a[0] * b[0] + a[1] * b[3], a[0] * b[1] + a[1] * b[4], a[0] * b[2] + a[1] * b[5] + a[2],
                        a[3] * b[0] + a[4] * b[3], a[3] * b[1] + a[4] * b[4], a[3] * b[2] + a[4] * b[5] + a[5],
                    },
                };
            }
        };
        pub const Affine = Matrix;

        const P = Point(T);
        const Scale = Point(T);
        const Translation = Point(T);

        scale: Scale = Scale{
            .x = 1.0,
            .y = 1.0,
        },
        rotate: f32 = 0.0,
        translate: Translation = Translation{},

        pub fn apply(self: @This(), point: P) P {
            return P{
                .x = (self.scale.x * (point.x + self.translate.x)),
                .y = (self.scale.y * (point.y + self.translate.y)),
            };
        }

        pub fn toMatrix(self: @This()) Matrix {
            const cos = std.math.cos(self.rotate);
            const sin = std.math.sin(self.rotate);
            const s = self.scale;
            const t = self.translate;

            return Matrix{
                .coefficients = [_]T{
                    cos * s.x, -sin * s.y, cos * s.x * t.x - sin * s.y * t.y,
                    sin * s.x, cos * s.y, sin * s.x * t.x + cos * s.y * t.y,
                },
            };
        }

        pub const toAffine = toMatrix;
    };
}

pub const TransformF32 = Transform(f32);
