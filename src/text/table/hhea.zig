const root = @import("../root.zig");
const Error = root.Error;
const Reader = root.Reader;

pub const Table = struct {
    /// Face ascender.
    ascender: i16,
    /// Face descender.
    descender: i16,
    /// Face line gap.
    line_gap: i16,
    /// Number of metrics in the `hmtx` table.
    number_of_metrics: u16,

    pub fn create(data: []const u8) Error!Table {
        // Do not check the exact length, because some fonts include
        // padding in table's length in table records, which is incorrect.
        if (data.len < 36) {
            return error.InvalidTable;
        }

        var r = Reader.create(data);
        r.skip(u32); // version
        const ascender = r.readInt(i16) orelse return error.InvalidTable;
        const descender = r.readInt(i16) orelse return error.InvalidTable;
        const line_gap = r.readInt(i16) orelse return error.InvalidTable;
        r.skipN(24);
        const number_of_metrics = r.readInt(u16) orelse return error.InvalidTable;

        return Table{
            .ascender = ascender,
            .descender = descender,
            .line_gap = line_gap,
            .number_of_metrics = number_of_metrics,
        };
    }
};
