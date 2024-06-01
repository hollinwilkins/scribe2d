const text = @import("../root.zig");
const util = @import("../util..zig");
const format0 = @import("./cmap/format0.zig");
const format2 = @import("./cmap/format2.zig");
const format4 = @import("./cmap/format4.zig");
const format6 = @import("./cmap/format6.zig");
const format10 = @import("./cmap/format10.zig");
const format12 = @import("./cmap/format12.zig");
const format13 = @import("./cmap/format13.zig");
const format14 = @import("./cmap/format14.zig");
const name = @import("./name.zig");
const GlyphId = text.GlyphId;
const Error = text.Error;
const Offset32 = util.Offset32;
const LazyArray = util.LazyArray;
const Reader = util.Reader;

pub const Format = union(u8) {
    byte_encoding: format0.Subtable0,
    high_byte_mapping: format2.Subtable2,
    segment_mapping_delta: format4.Subtable4,
    trimmed_table: format6.Subtable6,
    trimmed_array: format10.Subtable10,
    segmented_coverage: format12.Subtable12,
    many_to_one: format13.Subtable13,
    unicode_variation: format14.Subtable14,
    unsupported: u8,
};

pub const Subtable = struct {
    platform_id: name.PlatformId,
    encoding_id: u16,
    format: Format,

    pub fn isUnicode(self: Subtable) bool {
        const WINDOWS_UNICODE_BMP_ENCODING_ID: u16 = 1;
        const WINDOWS_UNICODE_FULL_REPERTOIRE_ENCODING_ID: u16 = 10;

        switch (self.platform_id) {
            .unicode => {
                return true;
            },
            .windows => {
                if (self.encoding_id == WINDOWS_UNICODE_BMP_ENCODING_ID) {
                    return true;
                }

                // "Note: Subtable format 13 has the same structure as format 12; it differs only
                // in the interpretation of the startGlyphID/glyphID fields".
                const is_format12_compatible = switch (self.format) {
                    .segmented_coverage => |_| true,
                    .many_to_one => |_| true,
                    else => false,
                };

                // "Fonts that support Unicode supplementary-plane characters (U+10000 to U+10FFFF)
                // on the Windows platform must have a format 12 subtable for platform ID 3,
                // encoding ID 10."
                return self.encoding_id == WINDOWS_UNICODE_FULL_REPERTOIRE_ENCODING_ID and is_format12_compatible;
            },
            else => {
                return false;
            },
        }
    }

    pub fn getGlyphIndex(self: Subtable, codepoint32: u32) ?GlyphId {
        switch (self.format) {
            .byte_encoding => |*table| return table.getGlyphIndex(codepoint32),
            .high_byte_mapping => |*table| return table.getGlyphIndex(codepoint32),
            .segment_mapping_delta => |*table| return table.getGlyphIndex(codepoint32),
            .trimmed_table => |*table| return table.getGlyphIndex(codepoint32),
            .trimmed_array => |*table| return table.getGlyphIndex(codepoint32),
            .segmented_coverage => |*table| return table.getGlyphIndex(codepoint32),
            .many_to_one => |*table| return table.getGlyphIndex(codepoint32),
            .unicode_variation => |_| return null,
            .unsupported => |_| return null,
        }
    }

    pub fn getGlyphVariationIndex(self: Subtable, codepoint32: u32, variation: u16) ?format14.GlyphVariationResult {
        switch (self.format) {
            .unicode_variation => |*table| return table.getGlyphIndex(codepoint32, variation),
            else => return null,
        }
    }

    pub fn iterator(self: Subtable) ?Iterator {
        switch (self.format) {
            .byte_encoding => |table| return Iterator{ .byte_encoding = table.iterator() },
            .high_byte_mapping => |table| return Iterator{ .high_byte_mapping = table.iterator() },
            .segment_mapping_delta => |table| return Iterator{ .segment_mapping_delta = table.iterator() },
            .trimmed_table => |table| return Iterator{ .trimmed_table = table.iterator() },
            .trimmed_array => |table| return Iterator{ .trimmed_array = table.iterator() },
            .segmented_coverage => |table| return Iterator{ .segmented_coverage = table.iterator() },
            .many_to_one => |table| return Iterator{ .many_to_one = table.iterator() },
            else => return null,
        }
    }

    pub const Iterator = union(u8) {
        byte_encoding: format0.Subtable0.Iterator,
        high_byte_mapping: format2.Subtable2.Iterator,
        segment_mapping_delta: format4.Subtable4.Iterator,
        trimmed_table: format6.Subtable6.Iterator,
        trimmed_array: format10.Subtable10.Iterator,
        segmented_coverage: format12.Subtable12.Iterator,
        many_to_one: format13.Subtable13.Iterator,

        pub fn next(self: *Iterator) ?u32 {
            switch (self) {
                .byte_encoding => |*it| return it.next(),
                .high_byte_mapping => |*it| return it.next(),
                .segment_mapping_delta => |*it| return it.next(),
                .trimmed_table => |*it| return it.next(),
                .trimmed_array => |*it| return it.next(),
                .segmented_coverage => |*it| return it.next(),
                .many_to_one => |*it| return it.next(),
            }
        }
    };
};

pub const EncodingRecord = struct {
    pub const ReadSize = @sizeOf(EncodingRecord);

    platform_id: name.PlatformId,
    encoding_id: u16,
    offset: Offset32,

    pub fn read(reader: *Reader) ?EncodingRecord {
        const platform_id = name.PlatformId.read(reader) orelse return null;
        const encoding_id = reader.readInt(u16) orelse return null;
        const offset = Offset32.read(reader) orelse return null;

        return EncodingRecord{
            .platform_id = platform_id,
            .encoding_id = encoding_id,
            .offset = offset,
        };
    }
};

pub const Subtables = struct {
    const EncodingRecordsList = LazyArray(EncodingRecord);

    data: []const u8,
    records: EncodingRecordsList,

    pub fn get(self: Subtables, index: usize) ?Subtable {
        const record = self.records.get(index) orelse return null;
        const data = self.data[record.offset..];
        var reader = Reader.create(data);
        const format_kind = reader.readInt(u16) orelse return null;

        const format: ?Format = switch (format_kind) {
            0 => Format{ .byte_encoding = format0.Subtable0.create(data) orelse null },
            2 => Format{ .high_byte_mapping = format2.Subtable2.create(data) orelse null },
            4 => Format{ .segment_mapping_delta = format4.Subtable4.create(data) orelse null },
            6 => Format{ .trimmed_table = format6.Subtable6.create(data) orelse null },
            10 => Format{ .trimmed_array = format10.Subtable10.create(data) orelse null },
            12 => Format{ .segmented_coverage = format12.Subtable12.create(data) orelse null },
            13 => Format{ .many_to_one = format13.Subtable13.create(data) orelse null },
            14 => Format{ .unicode_variation = format14.Subtable14.create(data) orelse null },
        };

        if (format) |f| {
            return Subtable{
                .platform_id = record.platform_id,
                .encoding_id = record.encoding_id,
                .format = f,
            };
        }

        return null;
    }

    pub fn len(self: Subtables) usize {
        return self.records.len;
    }

    pub fn isEmpty(self: Subtables) bool {
        return self.len() == 0;
    }

    pub const Iterator = struct {
        subtables: Subtables,
        index: usize,

        pub fn next(self: *Iterator) ?Subtable {
            if (self.index < self.subtables.len()) {
                self.index += 1;
                return self.subtables.get(self.index - 1);
            } else {
                return null;
            }
        }
    };
};

pub const Table = struct {
    subtables: Subtables,

    pub fn create(data: []const u8) Error!Table {
        var reader = Reader.create(data);
        reader.skip(u16); // version
        const count = reader.readInt(u16) orelse return error.InvalidTable;
        const records = Subtables.EncodingRecordsList.read(&reader, count) orelse return error.InvalidTable;

        return Table{
            .subtables = Subtables{
                .records = records,
                .data = data,
            },
        };
    }
};
