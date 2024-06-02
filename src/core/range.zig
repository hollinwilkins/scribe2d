pub fn Range(comptime T: type) type {
    return struct {
        start: T,
        end: T,

        pub fn size(self: @This()) usize {
            return @intCast(self.end - self.start);
        }
    };
}

pub const RangeF32 = Range(f32);
pub const RangeU32 = Range(u32);
pub const RangeI32 = Range(i32);
