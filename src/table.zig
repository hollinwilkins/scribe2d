const std = @import("std");
const mem = std.mem;
pub const head = @import("./table/head.zig");
pub const hhea = @import("./table/hhea.zig");
pub const maxp = @import("./table/maxp.zig");
const Reader = @import("./root.zig").Reader;

pub const Tag = struct {
    value: u32,

    pub fn toBytes(self: Tag) [4]u8 {
        return .{
            @intCast(self.value >> 24 & 0xff),
            @intCast(self.value >> 16 & 0xff),
            @intCast(self.value >> 8 & 0xff),
            @intCast(self.value >> 0 & 0xff),
        };
    }

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
    pub const ReadSize: usize = @sizeOf(TableRecord);

    tag: Tag,
    check_sum: u32,
    offset: u32,
    length: u32,

    pub fn read(reader: *Reader) ?TableRecord {
        const tag = Tag.read(reader) orelse return null;
        const check_sum = reader.readInt(u32) orelse return null;
        const offset = reader.readInt(u32) orelse return null;
        const length = reader.readInt(u32) orelse return null;

        return TableRecord{
            .tag = tag,
            .check_sum = check_sum,
            .offset = offset,
            .length = length,
        };
    }
};
