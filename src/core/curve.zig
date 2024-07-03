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
    };
}

pub const IntersectionF32 = Intersection(f32);

pub fn Line(comptime T: type) type {
    const P = Point(T);

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

        pub fn affineTransform(self: @This(), affine: Transform(T).Affine) @This() {
            return @This(){
                .p0 = self.p0.affineTransform(affine),
                .p1 = self.p1.affineTransform(affine),
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
