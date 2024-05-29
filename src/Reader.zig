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

pub fn setCursor(self: *Reader, cursor: usize) void {
    self.cursor = cursor;
}

pub fn setCursorChecked(self: *Reader, cursor: usize) bool {
    if (cursor < self.data.len) {
        self.cursor = cursor;
        return true;
    }

    return false;
}

pub fn skip(self: *Reader, comptime T: type) void {
    self.skipN(@sizeOf(T));
}

pub fn skipN(self: *Reader, n: usize) void {
    self.cursor += n;
}

pub fn skipChecked(self: *Reader, comptime T: type) bool {
    return self.skipCheckedN(@sizeOf(T));
}

pub fn skipCheckedN(self: *Reader, n: usize) bool {
    if (self.cursor + n <= self.data.len) {
        self.cursor += n;
        return true;
    }

    return false;
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
