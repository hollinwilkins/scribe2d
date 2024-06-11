const text = @import("../../root.zig");
const util = @import("../../util.zig");
const Error = text.Error;
const GlyphId = text.GlyphId;
const Reader = util.Reader;

pub const Subtable0 = struct {
    // Just a list of 256 8bit glyph IDs.
    glyph_ids: []const u8,

    pub fn create(data: []const u8) Error!Subtable0 {
        var reader = Reader.create(data);
        reader.skip(u16); // format
        reader.skip(u16); // length
        reader.skip(u16); // language
        const glyphd_ids = reader.readN(256) orelse return error.InvalidTable;

        return Subtable0{
            .glyph_ids = glyphd_ids,
        };
    }

    pub fn getGlyphIndex(self: Subtable0, code_point: u32) ?GlyphId {
        const index: usize = @intCast(code_point);

        if (index >= self.glyph_ids.len) {
            return null;
        }
        
        const glyph_id = self.glyph_ids[index];
        if (glyph_id != 0) {
            return @intCast(glyph_id);
        }

        return null;
    }

    pub fn iterator(self: Subtable0) Iterator {
        return Iterator{
            .table = self,
            .index = 0,
        };
    }

    pub const Iterator = struct {
        table: Subtable0,
        index: usize,

        pub fn next(self: *Iterator) ?u32 {
            var i = 0;
            for (self.table.glyph_ids[self.index..]) |glyph_id| {
                if (glyph_id != 0) {
                    self.index += i + 1;
                    return @intCast(i);
                }

                i += 1;
            }

            self.index += i;
            return null;
        }
    };
};
