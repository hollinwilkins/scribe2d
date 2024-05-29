const Reader = @This();

cursor: usize,
data: []const u8,

pub fn create(data: []const u8) Reader {
    return Reader{
        .cursor = 0,
        .data = data,
    };
}

pub fn skip(self: *Reader, comptime T: type) void {
    self.skipN(@sizeOf(T));
}

pub fn skipN(self: *Reader, n: usize) void {
    self.cursor += n;
}

// pub fn read(self: *Reader, comptime T: type) ?T {
// }
