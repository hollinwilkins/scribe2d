const std = @import("std");
const root = @import("../../root.zig");
const Error = root.Error;
const Reader = root.Reader;
const GlyphId = root.GlyphId;
const LazyArray = root.LazyArray;

pub const SequentialMapGroup = struct {
    pub const ReadSize = @sizeOf(SequentialMapGroup);

    start_char_code: u32,
    end_char_code: u32,
    start_glyph_id: u32,

    pub fn read(reader: *Reader) ?SequentialMapGroup {
        const start_char_code = reader.readInt(u32) orelse return null;
        const end_char_code = reader.readInt(u32) orelse return null;
        const start_glyph_id = reader.readInt(u32) orelse return null;

        return SequentialMapGroup{
            .start_char_code = start_char_code,
            .end_char_code = end_char_code,
            .start_glyph_id = start_glyph_id,
        };
    }
};

pub const Subtable12 = struct {
    const SequentialMapGroupsList = LazyArray(SequentialMapGroup);

    groups: SequentialMapGroupsList,

    pub fn create(data: []const u8) Error!Subtable12 {
        var reader = Reader.create(data);
        reader.skip(u16); // format
        reader.skip(u16); // reserved
        reader.skip(u16); // length
        reader.skip(u16); // language
        const count = reader.readInt(u32) orelse return error.InvalidTable;
        const groups = SequentialMapGroupsList.read(&reader, count) orelse return error.InvalidTable;

        return Subtable12{
            .groups = groups,
        };
    }

    pub fn getGlyphIndex(self: Subtable12, codepoint32: u32) ?GlyphId {
        // const search = self.groups.binarySearchBy(f: *const fn(*const T)std.math.Order)
        if (self.groups.binarySearchBy(codepoint32, &order)) |search| {
            const id = search.value.start_glyph_id + codepoint32 - search.value.start_char_code;
            return @intCast(id);
        }

        return null;
    }

    fn order(codepoint: u32, group: *const SequentialMapGroup) std.math.Order {
        if (group.start_char_code > codepoint) {
            return .gt;
        } else if (group.end_char_code < codepoint) {
            return .lt;
        }

        return .eq;
    }

    pub const Iterator = struct {
        table: Subtable12,
        index: usize,
        i: usize,

        pub fn next(self: *Iterator) ?u32 {
            const group = self.table.groups.get(self.index) orelse return null;
            const codepoint = group.start_char_code + self.i;

            if (codepoint < group.end_char_code) {
                self.i += 1;
                return codepoint;
            } else {
                self.i = 0;
                self.index += 1;
                return self.next(0);
            }
        }
    };
};
