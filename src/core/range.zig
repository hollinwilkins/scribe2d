pub fn Range(comptime T: type) type {
    return struct {
        start: T = 0,
        end: T = 0,

        pub fn size(self: @This()) usize {
            return @intCast(self.end - self.start);
        }
    };
}

pub const RangeUsize = Range(usize);
pub const RangeF32 = Range(f32);
pub const RangeU32 = Range(u32);
pub const RangeI32 = Range(i32);
