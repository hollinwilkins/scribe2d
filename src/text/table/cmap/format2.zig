const std = @import("std");
const text = @import("../../root.zig");
const util = @import("../../util.zig");
const Error = text.Error;
const GlyphId = text.GlyphId;
const Reader = util.Reader;
const LazyIntArray = util.LazyIntArray;
const LazyArray = util.LazyArray;

pub const SubHeaderRecord = struct {
    pub const ReadSize = @sizeOf(SubHeaderRecord);

    first_code: u16,
    entry_count: u16,
    id_delta: i16,
    id_range_offset: u16,

    pub fn read(reader: *Reader) ?SubHeaderRecord {
        const first_code = reader.readInt(u16) orelse return null;
        const entry_count = reader.readInt(u16) orelse return null;
        const id_delta = reader.readInt(i16) orelse return null;
        const id_range_offset = reader.readInt(u16) orelse return null;

        return SubHeaderRecord{
            .first_code = first_code,
            .entry_count = entry_count,
            .id_delta = id_delta,
            .id_range_offset = id_range_offset,
        };
    }
};

pub const Subtable2 = struct {
    const SubHeadersList = LazyArray(SubHeaderRecord);
    const SubHeaderKeysList = LazyIntArray(u16);

    sub_header_keys: SubHeaderKeysList,
    sub_headers_offset: usize,
    sub_headers: SubHeadersList,
    data: []const u8,

    pub fn create(data: []const u8) Error!Subtable2 {
        var reader = Reader.create(data);
        reader.skip(u16); // format
        reader.skip(u16); // length
        reader.skip(u16); // language

        const sub_header_keys = SubHeaderKeysList.read(&reader, 256) orelse return error.InvalidTable;
        // The maximum index in a sub_header_keys is a sub_headers count.
        var sub_headers_count: usize = 0;
        var key_iterator = sub_header_keys.iterator();
        while (key_iterator.next()) |key| {
            sub_headers_count = @max(sub_headers_count, key / 8);
        }
        sub_headers_count += 1;

        // Remember sub_headers offset before reading. Will be used later.
        const sub_headers_offset = reader.cursor;
        const sub_headers = SubHeadersList.read(&reader, sub_headers_count) orelse return error.InvalidTable;

        return Subtable2{
            .sub_header_keys = sub_header_keys,
            .sub_headers_offset = sub_headers_offset,
            .sub_headers = sub_headers,
            .data = data,
        };
    }

    pub fn getGlyphIndex(self: Subtable2, codepoint32: u32) ?GlyphId {
        // This subtable supports code points only in a u16 range.
        if (codepoint32 > std.math.maxInt(u16)) {
            return null;
        }
        const codepoint: u16 = @intCast(codepoint32);
        const high_byte = codepoint >> 8;
        const low_byte = codepoint & 0x00ff;

        var i: u16 = 0;
        if (codepoint < 0xff) {
            // 'SubHeader 0 is special: it is used for single-byte character codes.'
            i = 0;
        } else {
            // 'Array that maps high bytes to subHeaders: value is subHeader index × 8.'
            const high_byte_key = self.sub_header_keys.get(high_byte) orelse return null;
            i = high_byte_key / 8;
        }

        const sub_header = self.sub_headers.get(i) orelse return null;

        const first_code = sub_header.first_code;
        const range_end = first_code + sub_header.entry_count;

        if (low_byte < first_code or low_byte >= range_end) {
            return null;
        }

        // SubHeaderRecord::id_range_offset points to SubHeaderRecord::first_code
        // in the glyphIndexArray. So we have to advance to our code point.
        const index_offset = @as(usize, @intCast(low_byte - first_code)) * @sizeOf(u16);

        // 'The value of the idRangeOffset is the number of bytes
        // past the actual location of the idRangeOffset'.
        const offset = self.sub_headers_offset
        // Advance to required subheader.
        + @sizeOf(SubHeaderRecord) * @as(usize, @intCast(i + 1))
        // Move back to idRangeOffset start.
        - @sizeOf(u16)
        // Use defined offset.
        + @as(usize, @intCast(sub_header.id_range_offset))
        // Advance to required index in the glyphIndexArray.
        + index_offset;

        const glyph = std.mem.bigToNative(u16, std.mem.bytesToValue(u16, self.data[offset .. offset + @sizeOf(u16)]));
        if (glyph == 0) {
            return null;
        }

        return @as(u16, @intCast(@mod((@as(i32, @intCast(glyph)) + @as(i32, @intCast(sub_header.id_delta))), 65536)));
    }

    pub fn iterator(self: Subtable2) Iterator {
        return Iterator{
            .table = self,
            .index = 0,
            .first_byte = 0,
            .sub_byte = 0,
        };
    }

    pub const Iterator = struct {
        table: Subtable2,
        index: usize,
        first_byte: u16,
        sub_byte: u16,

        pub fn next(self: *Iterator) ?u32 {
            if (self.first_byte >= 256) {
                return null;
            }

            const first_byte = self.table.sub_header_keys.get(self.first_byte) orelse return null;
            const i = first_byte / 8;
            const sub_header = self.table.sub_headers.get(i) orelse return null;
            const first_code = sub_header.first_code;

            if (i == 0) {
                // This is a single byte code.
                const range_end = first_code + sub_header.entry_count;

                self.first_byte += 1;
                self.sub_byte = 0;
                if (first_byte >= first_code and first_byte < range_end) {
                    return @intCast(first_byte);
                }

                return self.next();
            } else {
                // This is a two byte code.
                const base = first_code + (first_byte << 8);
                if (self.sub_byte < sub_header.entry_count) {
                    const codepoint = base + self.sub_byte;
                    self.sub_byte += 1;
                    return @intCast(codepoint);
                }

                self.first_byte += 1;
                self.sub_byte = 0;
                return self.next();
            }
        }
    };
};
