const text = @import("../root.zig");
const util = @import("../util.zig");
const Error = text.Error;
const Reader = util.Reader;

pub const Table = struct {
    number_of_glyphs: u16,

    pub fn create(data: []const u8) Error!Table {
        var r = Reader.create(data);
        const version = r.readInt(u32) orelse return error.InvalidTable;
        if (!(version == 0x00005000 or version == 0x0010000)) {
            return error.InvalidTable;
        }

        const number_of_glyphs = r.readInt(u16) orelse return error.InvalidTable;
        if (number_of_glyphs == 0) {
            return error.InvalidTable;
        }

        return Table{
            .number_of_glyphs = number_of_glyphs,
        };
    }
};
