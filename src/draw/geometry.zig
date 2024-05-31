pub const Error = error{
    DimensionOverflow,
};

pub fn Point(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}

pub const PointF32 = Point(f32);

pub fn Dimensions(comptime T: type) type {
    return struct {
        width: T,
        height: T,

        pub fn create(width: T, height: T) !@This() {
            const r = @mulWithOverflow(width, height);

            if (r[1] == 1) {
                return error.DimensionOverflow;
            }

            return @This(){
                .width = width,
                .height = height,
            };
        }

        pub fn size(self: *const @This()) T {
            return self.width * self.height;
        }
    };
}

pub const DimensionsF32 = Dimensions(f32);
pub const DimensionsUsize = Dimensions(usize);
pub const DimensionsU32 = Dimensions(u32);

pub fn Rect(comptime T: type) type {
    return struct {
        const P = Point(T);

        min: P,
        max: P,

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
    };
}

pub const RectF32 = Rect(f32);
