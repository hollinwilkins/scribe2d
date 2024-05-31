const std = @import("std");
const root = @import("../root.zig");
const Error = root.Error;
const Reader = root.Reader;
const GlyphId = root.GlyphId;
const LazyIntArray = root.LazyIntArray;

pub const Subtable4 = struct {
    const StartCodesList = LazyIntArray(u16);
    const EndCodesList = LazyIntArray(u16);
    const IdDeltasList = LazyIntArray(u16);
    const IdRangeOffsetsList = LazyIntArray(u16);

    start_codes: StartCodesList,
    end_codes: EndCodesList,
    id_deltas: IdDeltasList,
    id_range_offsets: IdRangeOffsetsList,
    id_range_offset_pos: usize,
    data: []const u8,

    pub fn create(data: []const u8) Error!Subtable4 {
        var reader = Reader.create(data);
        reader.skip(6); // format + length + language
        const seg_count_s2 = reader.readInt(u16) orelse return error.InvalidTable;
        if (seg_count_s2 < 2) {
            return error.InvalidTable;
        }

        const seg_count = seg_count_s2 / 2;
        reader.skip(6); // searchRange + entrySelector + rangeShift

        const end_codes = EndCodesList.read(reader, seg_count) orelse return error.InvalidTable;
        reader.skip(u16); // reservedPad
        const start_codes = StartCodesList.read(reader, seg_count) orelse return error.InvalidTable;
        const id_deltas = IdDeltasList.read(reader, seg_count) orelse return error.InvalidTable;
        const id_range_offset_pos = reader.cursor;
        const id_range_offsets = IdRangeOffsetsList.read(reader, seg_count) orelse return error.InvalidTable;

        return Subtable4{
            .start_codes = start_codes,
            .end_codes = end_codes,
            .id_deltas = id_deltas,
            .id_range_offsets = id_range_offsets,
            .id_range_offset_pos = id_range_offset_pos,
            .data = data,
        };
    }

    pub fn getGlyphIndex(self: Subtable4, codepoint32: u32) ?GlyphId {
        if (codepoint32 > std.math.maxInt(u16)) {
            return null;
        }
        const codepoint: u16 = @intCast(codepoint32);

        // Binary search
        var start: usize = 0;
        var end: usize = self.start_codes.len;

        while (end > start) {
            const index = (start + end) / 2;
            const end_value = self.end_codes.get(index) orelse return null;

            if (end_value >= codepoint) {
                const start_value = self.start_codes.get(index) orelse return null;

                if (start_value >= codepoint) {
                    end = index;
                } else {
                    const id_range_offset = self.id_range_offsets.get(index) orelse return null;
                    const id_delta = self.id_deltas.get(index) orelse return null;

                    if (id_range_offset == 0) {
                        return codepoint + id_delta;
                    } else if (id_range_offset == 0xffff) {
                        // Some malformed fonts have 0xFFFF as the last offset,
                        // which is invalid and should be ignored.
                        return null;
                    }

                    const delta32 = @as(u32, @intCast(codepoint)) - @as(u32, @intCast(start_value));
                    const delta: u16 = @intCast(delta32);

                    const id_range_offset_pos: u16 = @intCast(self.id_range_offset_pos + @as(usize, @intCast(index)) * 2);
                    const pos = id_range_offset_pos + delta + id_range_offset;

                    const glyph_array_value: u16 = std.mem.bigToNative(u16, std.mem.bytesToValue(u16, self.data[pos .. pos + @sizeOf(u16)]));

                    // 0 indicates missing glyph.
                    if (glyph_array_value == 0) {
                        return null;
                    }

                    const glyph_id = @as(i16, @intCast(glyph_array_value)) + id_delta;
                    return @intCast(glyph_id);
                }
            } else {
                start = index + 1;
            }
        }

        return null;
    }

    pub fn iterator(self: Subtable4) Iterator {
        return Iterator{
            .table = self,
            .index = 0,
            .i = 0,
        };
    }

    pub const Iterator = struct {
        table: Subtable4,
        index: usize,
        i: u16,

        pub fn next(self: *Iterator) ?u32 {
            const start = self.table.start_codes.get(self.index) orelse return null;
            const end = self.table.end_codes.get(self.index) orelse return null;

            if (start == end and start == 0xffff) {
                return null;
            }

            if (self.i < (end - start)) {
                const n = start + self.i;
                self.i += 1;
                return @intCast(n);
            } else {
                self.index += 1;
                self.i = 0;

                return self.next();
            }
        }
    };
};
