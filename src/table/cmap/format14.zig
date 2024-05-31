const std = @import("std");
const root = @import("../../root.zig");
const Error = root.Error;
const Offset32 = root.Offset32;
const Reader = root.Reader;
const GlyphId = root.GlyphId;
const LazyArray = root.LazyArray;

pub const VariationSelectorRecord = struct {
    pub const ReadSize = @sizeOf(VariationSelectorRecord);

    var_selector: u24,
    default_uvs_offset: ?Offset32,
    non_default_uvs_offset: ?Offset32,

    pub fn read(reader: *Reader) ?VariationSelectorRecord {
        const var_selector = reader.readInt(u24) orelse return null;
        const default_uvs_offset = Offset32.read(reader);
        const non_default_uvs_offset = Offset32.read(reader);

        return VariationSelectorRecord{
            .var_selector = var_selector,
            .default_uvs_offset = default_uvs_offset,
            .non_default_uvs_offset = non_default_uvs_offset,
        };
    }
};

pub const UVSMappingRecord = struct {
    pub const ReadSize = @sizeOf(UVSMappingRecord);

    unicode_value: u24,
    glyph_id: GlyphId,

    pub fn read(reader: *Reader) ?UVSMappingRecord {
        const unicode_value = reader.readInt(u24) orelse return null;
        const glyph_id = reader.readIng(GlyphId) orelse return null;

        return UVSMappingRecord{
            .unicode_value = unicode_value,
            .glyph_id = glyph_id,
        };
    }
};

pub const UnicodeRangeRecord = struct {
    pub const ReadSize = @sizeOf(UnicodeRangeRecord);

    start_unicode_value: u24,
    additional_count: u8,

    pub fn read(reader: *Reader) ?UnicodeRangeRecord {
        const start_unicode_value = reader.readInt(u24) orelse return null;
        const additional_count = reader.readInt(u8) orelse return null;

        return UnicodeRangeRecord{
            .start_unicode_value = start_unicode_value,
            .additional_count = additional_count,
        };
    }
};

pub const GlyphVariationResult = struct {
    glyph_id: ?GlyphId,
};

pub const Subtable14 = struct {
    const RecordsList = LazyArray(VariationSelectorRecord);
    const UnicodeRangeRecordsList = LazyArray(UnicodeRangeRecord);
    const UVSMappingRecordsList = LazyArray(UVSMappingRecord);

    records: RecordsList,
    data: []const u8,

    pub fn create(data: []const u8) Error!Subtable14 {
        var reader = Reader.create(data);
        reader.skip(u16); // format
        reader.skip(u32); // length
        const count = reader.readInt(u32) orelse return error.InvalidTable;
        const records = RecordsList.read(&reader, count) orelse return error.InvalidTable;

        return Subtable14{
            .records = records,
            .data = data,
        };
    }

    pub fn getGlyphIndex(self: Subtable14, codepoint32: u32, variation: u32) ?GlyphVariationResult {
        const search = self.records.binarySearchBy(variation, &orderVariation) orelse return null;

        if (search.value.default_uvs_offset) |offset| {
            const data = self.data[offset..];
            var reader = Reader.create(data);
            const count = reader.read(u32) orelse return null;
            const ranges = UnicodeRangeRecordsList.read(reader, count) orelse return null;
            for (ranges) |range| {
                if (range.contains(codepoint32)) {
                    return GlyphVariationResult{
                        .glyph_id = null,
                    };
                }
            }
        }

        if (search.value.non_default_uvs_offset) |offset| {
            const data = self.data[offset..];
            var reader = Reader.create(data);
            const count = reader.readInt(u32) orelse return null;
            const uvs_mappings = UVSMappingRecordsList.read(&reader, count) orelse return null;

            const uv_search = uvs_mappings.binarySearchBy(codepoint32, orderCodepoint) orelse return null;
            return GlyphVariationResult{
                .glyph_id = uv_search.value.glyph_id,
            };
        }

        return null;
    }

    fn orderVariation(variation: u32, record: *const VariationSelectorRecord) std.math.Order {
        if (record.var_selector < variation) {
            return .lt;
        } else if (record.var_selector == variation) {
            return .eq;
        } else {
            return .gt;
        }
    }

    fn orderCodepoint(codepoint32: u32, record: *const UVSMappingRecord) std.math.Order {
        if (codepoint32 < record.unicode_value) {
            return .lt;
        } else if (codepoint32 == record.unicode_value) {
            return .eq;
        } else {
            return .gt;
        }
    }
};
