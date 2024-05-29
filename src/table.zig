const std = @import("std");
const mem = std.mem;
pub const head = @import("./table/head.zig");
const Reader = @import("./root.zig").Reader;

pub const Tag = struct {
    value: u32,

    pub fn read(reader: *Reader) ?Tag {
        if (reader.read([4]u8)) |bytes| {
            const tag1 = @as(u32, bytes[0]) << 24;
            const tag2 = @as(u32, bytes[1]) << 16;
            const tag3 = @as(u32, bytes[2]) << 8;
            const tag4 = @as(u32, bytes[3]);
            return Tag{
                .value = (tag1 | tag2 | tag3 | tag4),
            };
        }

        return null;
    }
};

pub const TableRecord = struct {
    tag: Tag,
    check_sum: u32,
    offset: u32,
    length: u32,
};
