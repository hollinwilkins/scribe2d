const std = @import("std");
const muck_module = @import("./muck.zig");
const geometry_module = @import("./geometry.zig");
const Point = geometry_module.Point;
const Transform = geometry_module.Transform;

pub fn Intersection(comptime T: type) type {
    const P = Point(T);

    return struct {
        t: f32,
        point: P,

        pub fn fitToGrid(self: @This()) @This() {
            const GRID_FIT_THRESHOLD: f32 = 1e-4;

            var point = self.point;
            const rounded_x = @round(self.point.x);
            const rounded_y = @round(self.point.y);

            if (@abs(rounded_x - self.point.x) < GRID_FIT_THRESHOLD) {
                point.x = rounded_x;
            }

            if (@abs(rounded_y - self.point.y) < GRID_FIT_THRESHOLD) {
                point.y = rounded_y;
            }

            return @This(){
                .t = self.t,
                .point = point,
            };
        }
    };
}

pub const IntersectionF32 = Intersection(f32);

pub fn Line(comptime T: type) type {
    const P = Point(T);
    const I = Intersection(T);

    return extern struct {
        p0: P,
        p1: P,

        pub usingnamespace muck_module.ByteData(@This());

        pub fn create(p0: P, p1: P) @This() {
            return @This(){
                .p0 = p0,
                .p1 = p1,
            };
        }

        pub fn apply(self: @This(), t: f32) P {
            return self.p0.cast(f32).lerp(self.p1.cast(f32), t).cast(T);
        }

        pub fn cast(self: @This(), comptime T2: type) Line(T2) {
            return Line(T2){
                .p0 = self.p0.cast(T2),
                .p1 = self.p1.cast(T2),
            };
        }

        pub fn length(self: @This()) T {
            return self.p1.sub(self.p0).length();
        }

        pub fn normal(self: @This()) P {
            return P{
                .x = -(self.p1.y - self.p0.y),
                .y = self.p1.x - self.p0.x,
            };
        }

        pub fn reflectNormal(self: @This()) P {
            return P{
                .x = (self.p1.y - self.p0.y),
                .y = -(self.p1.x - self.p0.x),
            };
        }

        pub fn midpoint(self: @This()) P {
            return self.apply(0.5);
        }

        pub fn affineTransform(self: @This(), affine: Transform(T).Affine) @This() {
            return @This(){
                .p0 = self.p0.affineTransform(affine),
                .p1 = self.p1.affineTransform(affine),
            };
        }

        pub fn translate(self: @This(), t: P) @This() {
            return @This(){
                .p0 = self.p0.add(t),
                .p1 = self.p1.add(t),
            };
        }

        pub fn pointIntersectLine(self: @This(), other: @This()) ?P {
            const x1 = self.p0.x;
            const x2 = self.p1.x;
            const x3 = other.p0.x;
            const x4 = other.p1.x;
            const y1 = self.p0.y;
            const y2 = self.p1.y;
            const y3 = other.p0.y;
            const y4 = other.p1.y;

            const c1 = x1 - x2;
            const c2 = y3 - y4;
            const c3 = y1 - y2;
            const c4 = x3 - x4;

            const d = (c1 * c2) - (c3 * c4);

            // put some thresholding here
            if (d == 0) {
                return null;
            }

            const x1y2 = x1 * y2;
            const y1x2 = y1 * x2;
            const y3x4 = y3 * x4;
            const x3y4 = x3 * y4;
            const xn = ((x1y2 - y1x2) * c4) - (c1 * (x3y4 - y3x4));
            const yn = ((x1y2 - y1x2) * c2) - (c3 * (x3y4 - y3x4));
            const x = xn / d;
            const y = yn / d;

            return P{
                .x = x,
                .y = y,
            };
        }

        pub fn intersectHorizontalLine(self: @This(), other: @This()) ?I {
            const delta_y = self.p1.y - self.p0.y;
            if (delta_y == 0.0) {
                return null;
            }

            const t = -(self.p0.y - other.p0.y) / delta_y;
            if (t < 0.0 or t > 1.0) {
                return null;
            }

            const point = self.apply(t);
            if (point.x < other.p0.x or point.x > other.p1.x) {
                return null;
            }

            return I{
                .t = t,
                .point = P{
                    .x = point.x,
                    .y = other.p0.y,
                },
            };
        }

        pub fn intersectVerticalLine(self: @This(), other: @This()) ?I {
            const delta_x = self.p1.x - self.p0.x;
            if (delta_x == 0.0) {
                return null;
            }

            const t = -(self.p0.x - other.p0.x) / delta_x;
            if (t < 0.0 or t > 1.0) {
                return null;
            }

            const point = self.apply(t);
            if (point.y < other.p0.y or point.y > other.p1.y) {
                return null;
            }

            return I{
                .t = t,
                .point = P{
                    .x = other.p0.x,
                    .y = point.y,
                },
            };
        }
    };
}

pub const LineF32 = Line(f32);
pub const LineI16 = Line(i16);

pub fn Arc(comptime T: type) type {
    const P = Point(T);

    return extern struct {
        p0: P, // start
        p1: P, // zenith of arc
        p2: P, // end

        pub usingnamespace muck_module.ByteData(@This());

        pub fn create(p0: P, p1: P, p2: P) @This() {
            return @This(){
                .p0 = p0,
                .p1 = p1,
                .p2 = p2,
            };
        }

        // pub fn apply(self: @This(), t: f32) P {
        //     return self.p0.cast(f32).lerp(self.p1.cast(f32), t).cast(T);
        // }

        pub fn cast(self: @This(), comptime T2: type) Arc(T2) {
            return Arc(T2){
                .p0 = self.p0.cast(T2),
                .p1 = self.p1.cast(T2),
                .p2 = self.p2.cast(T2),
            };
        }

        pub fn affineTransform(self: @This(), affine: Transform(T).Affine) @This() {
            return @This(){
                .p0 = self.p0.affineTransform(affine),
                .p1 = self.p1.affineTransform(affine),
                .p2 = self.p2.affineTransform(affine),
            };
        }
    };
}

pub const ArcF32 = Arc(f32);
pub const ArcI16 = Arc(i16);

pub fn QuadraticBezier(comptime T: type) type {
    const P = Point(T);

    return extern struct {
        p0: P,
        p1: P,
        p2: P,

        pub usingnamespace muck_module.ByteData(@This());

        pub fn create(p0: P, p1: P, p2: P) @This() {
            return @This(){
                .p0 = p0,
                .p1 = p1,
                .p2 = p2,
            };
        }

        pub fn apply(self: @This(), t: f32) P {
            const mt = 1.0 - t;
            const v1 = self.p0.cast(f32).mulScalar(mt * mt);
            const v2 = self.p1.cast(f32).mulScalar(mt * 2.0).add(self.p2.cast(f32).mulScalar(t)).mulScalar(t);

            return v1.add(v2).cast(T);
        }

        pub fn cast(self: @This(), comptime T2: type) QuadraticBezier(T2) {
            return QuadraticBezier(T2){
                .p0 = self.p0.cast(T2),
                .p1 = self.p1.cast(T2),
                .p2 = self.p2.cast(T2),
            };
        }

        pub fn affineTransform(self: @This(), affine: Transform(T).Affine) @This() {
            return @This(){
                .p0 = self.p0.affineTransform(affine),
                .p1 = self.p1.affineTransform(affine),
                .p2 = self.p2.affineTransform(affine),
            };
        }
    };
}

pub const QuadraticBezierF32 = QuadraticBezier(f32);
pub const QuadraticBezierI16 = QuadraticBezier(i16);

pub fn CubicBezier(comptime T: type) type {
    const P = Point(T);

    return extern struct {
        p0: P,
        p1: P,
        p2: P,
        p3: P,

        pub usingnamespace muck_module.ByteData(@This());

        pub fn create(p0: P, p1: P, p2: P, p3: P) @This() {
            return @This(){
                .p0 = p0,
                .p1 = p1,
                .p2 = p2,
                .p3 = p3,
            };
        }

        pub fn apply(self: @This(), t: f32) P {
            const mt = 1.0 - t;
            const p1 = self.p1.cast(f32);
            const p2 = self.p2.cast(f32);
            const v1 = self.p0.cast(f32).mulScalar(mt * mt * mt);
            const v2 = p1.mulScalar(mt * mt * 3.0);
            const v3 = (p2.mulScalar(mt * 3.0).add(self.p3.cast(f32).mulScalar(t))).mulScalar(t);
            return v1.add(v2).add(v3.mulScalar(t)).cast(T);
        }

        pub fn cast(self: @This(), comptime T2: type) CubicBezier(T2) {
            return CubicBezier(T2){
                .p0 = self.p0.cast(T2),
                .p1 = self.p1.cast(T2),
                .p2 = self.p2.cast(T2),
                .p3 = self.p3.cast(T2),
            };
        }

        pub fn affineTransform(self: @This(), affine: Transform(T).Affine) @This() {
            return @This(){
                .p0 = self.p0.affineTransform(affine),
                .p1 = self.p1.affineTransform(affine),
                .p2 = self.p2.affineTransform(affine),
                .p3 = self.p3.affineTransform(affine),
            };
        }
    };
}

pub const CubicBezierF32 = CubicBezier(f32);
pub const CubicBezierI16 = CubicBezier(i16);
