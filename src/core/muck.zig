const std = @import("std");

pub fn ByteData(comptime T: type) type {
    return struct {
        pub fn asBytes(self: *const T) []const u8 {
            return std.mem.asBytes(self);
        }

        pub fn fromBytes(bytes: []const u8) T {
            return std.mem.bytesToValue(@This(), bytes);
        }
    };
}
