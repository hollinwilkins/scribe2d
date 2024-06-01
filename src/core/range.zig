pub fn Range(comptime T: type) type {
    return struct {
        start: T,
        end: T,
    };
}

pub const RangeU32 = Range(u32);
