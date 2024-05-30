const std = @import("std");
const root = @import("../root.zig");
const Error = root.Error;
const LazyIntArray = root.LazyIntArray;
const LazyArray = root.LazyArray;
const Reader = root.Reader;
const GlyphId = root.GlyphId;

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

        const sub_header_keys = SubHeaderKeysList.read(reader, 256) orelse return error.InvalidTable;
        // The maximum index in a sub_header_keys is a sub_headers count.
        var sub_headers_count = 0;
        var key_iterator = sub_header_keys.iterator();
        while (key_iterator.next()) |key| {
            sub_headers_count = @max(sub_headers_count, key / 8);
        }
        sub_headers_count += 1;

        // Remember sub_headers offset before reading. Will be used later.
        const sub_headers_offset = reader.cursor;
        const sub_headers = SubHeadersList.read(reader, sub_headers_count) orelse return error.InvalidTable;

        return Subtable2{
            .sub_header_keys = sub_header_keys,
            .sub_headers_offset = sub_headers_offset,
            .sub_headers = sub_headers,
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

        var i = 0;
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
        const offset = self.sub_headers.offset
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

        return @as(u16, @intCast(@as(i32, @intCast(glyph)) + @as(i32, @intCast(sub_header.id_delta)) % 65536));
    }
};

//     /// Calls `f` for each codepoint defined in this table.
//     pub fn codepoints(&self, f: impl FnMut(u32)) {
//         let _ = self.codepoints_inner(f);
//     }

//     #[inline]
//     fn codepoints_inner(&self, mut f: impl FnMut(u32)) -> Option<()> {
//         for first_byte in 0u16..256 {
//             let i = self.sub_header_keys.get(first_byte)? / 8;
//             let sub_header = self.sub_headers.get(i)?;
//             let first_code = sub_header.first_code;

//             if i == 0 {
//                 // This is a single byte code.
//                 let range_end = first_code.checked_add(sub_header.entry_count)?;
//                 if first_byte >= first_code && first_byte < range_end {
//                     f(u32::from(first_byte));
//                 }
//             } else {
//                 // This is a two byte code.
//                 let base = first_code.checked_add(first_byte << 8)?;
//                 for k in 0..sub_header.entry_count {
//                     let code_point = base.checked_add(k)?;
//                     f(u32::from(code_point));
//                 }
//             }
//         }

//         Some(())
//     }
// }

// impl core::fmt::Debug for Subtable2<'_> {
//     fn fmt(&self, f: &mut core::fmt::Formatter) -> core::fmt::Result {
//         write!(f, "Subtable2 {{ ... }}")
//     }
// }
