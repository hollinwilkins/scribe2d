pub fn Range(comptime T: type) type {
    return extern struct {
        const Self = @This();

        start: T = 0,
        end: T = 0,

        pub fn create(start: T, end: T) @This() {
            return @This(){
                .start = start,
                .end = end,
            };
        }

        pub fn size(self: @This()) usize {
            return @intCast(self.end - self.start);
        }

        pub fn chunkIterator(self: @This(), chunk_size: T) ChunkIterator {
            return ChunkIterator{
                .range = self,
                .chunk_size = chunk_size,
            };
        }

        pub const ChunkIterator = struct {
            range: Self,
            chunk_size: T,
            index: T = 0,

            pub fn next(self: *@This()) ?Self {
                const chunk_start = self.range.start + self.index * self.chunk_size;
                if (chunk_start >= self.range.end) {
                    return null;
                }

                self.index += 1;
                return Self{
                    .start = chunk_start,
                    .end = @min(self.range.end, chunk_start + self.chunk_size),
                };
            }
        };
    };
}

pub const RangeUsize = Range(usize);
pub const RangeF32 = Range(f32);
pub const RangeU32 = Range(u32);
pub const RangeI32 = Range(i32);
