pub fn Point(comptime T: type) type {
    return struct {
        x: T = 0,
        y: T = 0,

        pub fn add(self: @This(), other: @This()) @This() {
            return @This(){
                .x = self.x + other.x,
                .y = self.y + other.y,
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

        pub fn fitsInside(self: *const @This(), other: *const @This()) bool {
            return self.width <= other.width and self.height <= other.height;
        }
    };
}

pub const DimensionsF32 = Dimensions(f32);
pub const DimensionsUsize = Dimensions(usize);
pub const DimensionsU32 = Dimensions(u32);

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

        pub fn fitsInside(self: *const @This(), other: *const @This()) bool {
            return self.getDimensions().fitsInside(other.getDimensions());
        }

        // NOTE: can we use SIMD/NEON to make some of these functions more faster
        pub fn extendBy(self: *@This(), x: T, y: T) void {
            self.min.x = @min(self.min.x, x);
            self.min.y = @min(self.min.y, y);
            self.max.x = @max(self.max.x, x);
            self.max.y = @max(self.max.y, y);
        }
    };
}

pub const RectF32 = Rect(f32);
pub const RectI16 = Rect(i16);
pub const RectU32 = Rect(u32);
