const std = @import("std");
const text = @import("../root.zig");
const util = @import("../util.zig");
const head = @import("./head.zig");
const Error = text.Error;
const GlyphId = text.GlyphId;
const Reader = util.Reader;
const Fixed = util.Fixed;
const Range = util.Range;
const Rect = util.RectI16;
const LazyIntArray = util.LazyIntArray;
const IndexToLocationFormat = head.IndexToLocationFormat;

pub const Short = struct {
    const List = LazyIntArray(u16);

    offsets: List,
};

pub const Long = struct {
    const List = LazyIntArray(u32);

    offsets: List,
};

pub const Table = union(enum) {
    short: Short,
    long: Long,

    pub fn create(data: []const u8, number_of_glyphs: u16, format: IndexToLocationFormat) Error!Table {
        var total = if (number_of_glyphs == std.math.maxInt(u16)) number_of_glyphs else number_of_glyphs + 1;
        const actual_total_usize: usize = switch (format) {
            .short => data.len / 2,
            .long => data.len / 4,
        };
        const actual_total: u16 = @intCast(actual_total_usize);
        total = @min(total, actual_total);

        var r = Reader.create(data);
        switch (format) {
            .short => {
                const offsets = Short.List.read(&r, total) orelse return error.InvalidTable;
                return Table{
                    .short = Short{
                        .offsets = offsets,
                    },
                };
            },
            .long => {
                const offsets = Long.List.read(&r, total) orelse return error.InvalidTable;
                return Table{
                    .long = Long{
                        .offsets = offsets,
                    },
                };
            },
        }
    }

    pub fn len(self: Table) u16 {
        switch (self) {
            .short => |*short| return @intCast(short.offsets.data.len),
            .long => |*long| return @intCast(long.offsets.data.len),
        }
    }

    pub fn isEmpty(self: Table) bool {
        return self.len() == 0;
    }

    pub fn glyphRange(self: Table, glyph_id: GlyphId) ?Range {
        if (glyph_id == std.math.maxInt(u16)) {
            return null;
        }

        if (glyph_id >= self.len() - 1) {
            return null;
        }

        const range = switch (self) {
            .short => |*short| Range{
                .start = short.offsets.get(glyph_id).? * 2,
                .end = short.offsets.get(glyph_id + 1).? * 2,
            },
            .long => |*long| Range{
                .start = long.offsets.get(glyph_id).?,
                .end = long.offsets.get(glyph_id + 1).?,
            },
        };

        if (range.start >= range.end) {
            return null;
        }

        return range;
    }
};
