const std = @import("std");
const muck_module = @import("./muck.zig");
const geometry_module = @import("./geometry.zig");
const Point = geometry_module.Point;
const Transform = geometry_module.Transform;

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

        pub fn cast(self: @This(), comptime T2: type) Line(T2) {
            return Line(T2){
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

        pub fn cast(self: @This(), comptime T2: type) Line(T2) {
            return Line(T2){
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

        pub fn cast(self: @This(), comptime T2: type) Line(T2) {
            return Line(T2){
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
