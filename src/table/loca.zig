const std = @import("std");
const root = @import("../root.zig");
const Error = root.Error;
const Fixed = root.Fixed;
const GlyphId = root.GlyphId;
const Range = root.Range;
const Rect = root.RectI16;
const Reader = root.Reader;
const LazyArray = root.LazyArray;
const table = root.table;
const IndexToLocationFormat = table.head.IndexToLocationFormat;

pub const Short = struct {
    const List = LazyArray(u16);

    offsets: List,
};

pub const Long = struct {
    const List = LazyArray(u32);

    offsets: List,
};

pub const Table = union(u8) {
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
            .short => |*short| return short.offsets.len,
            .long => |*long| return long.offsets.len,
        }
    }

    pub fn isEmpty(self: Table) bool {
        return self.len() == 0;
    }

    pub fn glyph_range(self: Table, glyph_id: GlyphId) ?Range {
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
