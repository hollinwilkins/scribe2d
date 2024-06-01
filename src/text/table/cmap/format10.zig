const std = @import("std");
const text = @import("../../root.zig");
const util = @import("../../util.zig");
const Error = text.Error;
const GlyphId = text.GlyphId;
const Reader = util.Reader;
const LazyIntArray = util.LazyIntArray;

pub const Subtable10 = struct {
    const GlyphsList = LazyIntArray(u32);

    first_codepoint: u32,
    glyphs: GlyphsList,

    pub fn create(data: []const u8) Error!Subtable10 {
        var reader = Reader.create(data);
        reader.skip(u16); // format
        reader.skip(u16); // reserved
        reader.skip(u16); // length
        reader.skip(u16); // language

        const first_codepoint = reader.readInt(u32) orelse return error.InvalidTable;
        const count = reader.readInt(u32) orelse return error.InvalidTable;
        const glyphs = GlyphsList.read(reader, count) orelse return error.InvalidTable;

        return Subtable10{
            .first_codepoint = first_codepoint,
            .glyphs = glyphs,
        };
    }

    pub fn getGllyphIndex(self: Subtable10, codepoint32: u32) ?GlyphId {
        const index = codepoint32 - self.first_codepoint;
        return self.glyphs.get(index);
    }

    pub fn iterator(self: Subtable10) Iterator {
        return Iterator{
            .table = self,
            .index = 0,
        };
    }

    pub const Iterator = struct {
        table: Subtable10,
        index: u32,

        pub fn next(self: *Iterator) ?u32 {
            if (self.index >= self.table.glyphs.len) {
                return null;
            }

            const codepoint = self.table.first_codepoint + self.index;
            self.index += 1;
            return codepoint;
        }
    };
};
