const root = @import("../root.zig");
const Error = root.Error;
const Reader = root.Reader;
const GlyphId = root.GlyphId;

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
        const glyph_id = self.glyph_ids.get(@intCast(code_point)) orelse return null;

        if (glyph_id != 0) {
            return @intCast(glyph_id);
        }

        return null;
    }
};
