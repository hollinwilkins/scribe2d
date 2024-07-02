const std = @import("std");
const muck_module = @import("./muck.zig");
const geometry_module = @import("./geometry.zig");
const Point = geometry_module.Point;

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
    };
}

pub const LineF32 = Line(f32);
pub const LineI16 = Line(i16);

pub fn Arc(comptime T: type) type {
    const P = Point(T);

    return extern struct {
        p0: P,
        p1: P,
        center: P,
        angle: T,

        pub usingnamespace muck_module.ByteData(@This());

        pub fn create(p0: P, p1: P, center: P, angle: T) @This() {
            return @This(){
                .p0 = p0,
                .p1 = p1,
                .center = center,
                .angle = angle,
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
    };
}

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
    };
}

