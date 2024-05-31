const std = @import("std");
const root = @import("../../root.zig");
const Error = root.Error;
const Reader = root.Reader;
const GlyphId = root.GlyphId;
const LazyArray = root.LazyArray;
const SequentialMapGroup = @import("./format12.zig").SequentialMapGroup;

pub const Subtable13 = struct {
    const SequentialMapGroupsList = LazyArray(SequentialMapGroup);

    groups: SequentialMapGroupsList,

    pub fn create(data: []const u8) Error!Subtable13 {
        var reader = Reader.create(data);
        reader.skip(u16); // format
        reader.skip(u16); // reserved
        reader.skip(u16); // length
        reader.skip(u16); // language
        const count = reader.readInt(u32) orelse return error.InvalidTable;
        const groups = SequentialMapGroupsList.read(&reader, count) orelse return error.InvalidTable;

        return Subtable13{
            .groups = groups,
        };
    }

    pub fn getGlyphIndex(self: Subtable13, codepoint32: u32) ?GlyphId {
        var iterator = self.groups.iterator();

        while (iterator.next()) |group| {
            const start_char_code = group.start_char_code;
            if (codepoint32 >= start_char_code and codepoint32 <= group.end_char_code) {
                return @intCast(group.start_glyph_id);
            }
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
        table: Subtable13,
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
