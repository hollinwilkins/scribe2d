const std = @import("std");
const mem = std.mem;

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

pub fn readN(self: *Reader, n: usize) ?[]const u8 {
    if (self.cursor + n <= self.data.len) {
        const bytes = self.data[self.cursor .. self.cursor + n];
        self.cursor += n;
        return bytes;
    }

    return null;
}

pub fn read(self: *Reader, comptime T: type) ?T {
    if (self.readN(@sizeOf(T))) |bytes| {
        return mem.bytesAsValue(T, bytes);
    }

    return null;
}
