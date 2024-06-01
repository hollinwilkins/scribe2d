const std = @import("std");
const text = @import("../../root.zig");
const util = @import("../../util.zig");
const Error = text.Error;
const GlyphId = text.GlyphId;
const Reader = util.Reader;
const LazyIntArray = util.LazyIntArray;

pub const Subtable6 = struct {
    const GlyphsList = LazyIntArray(GlyphId);

    first_codepoint: u16,
    glyphs: GlyphsList,

    pub fn create(data: []const u8) Error!Subtable6 {
        const reader = Reader.create(data);
        reader.skip(u16); // format
        reader.skip(u16); // length
        reader.skip(u16); // language
        const first_code_point = reader.readInt(u16) orelse return error.InvalidTable;
        const count = reader.readInt(u16) orelse return error.InvalidTable;
        const glyphs = GlyphsList.read(&reader, count) orelse return error.InvalidTable;

        return Subtable6{
            .first_code_point = first_code_point,
            .glyphs = glyphs,
        };
    }

    pub fn getGlyphIndex(self: Subtable6, codepoint32: u32) ?GlyphId {
        if (codepoint32 > std.math.maxInt(u16)) {
            return null;
        }
        const codepoint: u16 = @intCast(codepoint32);
        const index = codepoint - self.first_codepoint;
        return self.glyphs.get(index);
    }

    pub fn iterator(self: Subtable6) Iterator {
        return Iterator{
            .table = self,
        };
    }

    pub const Iterator = struct {
        table: Subtable6,
        index: usize,

        pub fn next(self: *Iterator) ?u32 {
            if (self.index >= self.table.glyphs.len) {
                return null;
            }

            const codepoint = self.table.first_codepoint + self.index;
            return @intCast(codepoint);
        }
    };
};
