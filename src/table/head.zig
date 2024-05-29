const root = @import("../root.zig");
const Fixed = root.Fixed;
const Rect = root.Rect;
const Reader = root.Reader;

pub const Error = error{
    InvalidHeadTableLength,
    InvalidHeadTable,
};

pub const IndexToLocationFormat = enum {
    short,
    long,
};

pub const Table = struct {
    units_per_em: u16,
    global_bbox: Rect,
    index_to_location_format: IndexToLocationFormat,

    pub fn create(data: []const u8) Error!Table {
        if (data.len < 54) {
            return error.InvalidHeadTableLength;
        }

        const r = Reader.create(data);
        r.skip(u32); // version
        r.skip(Fixed); // font revision
        r.skip(u32); // checksum adjustment
        r.skip(u32); // magic number
        r.skip(u16); // flags
        const units_per_em = r.read(u16).?;
        r.skip(u64); // create time
        r.skip(u64); // modified time
        const global_bbox = r.read(Rect).?;
        r.skip(u16); // max style
        r.skip(u16); // lowest PPEM
        r.skip(i16); // font direction hint
        const index_to_location_format_u16 = r.read(u16).?;

        if (units_per_em < 16 or units_per_em > 16384) {
            return error.InvalidHeadTable;
        }

        const index_to_location_format: IndexToLocationFormat = switch (index_to_location_format_u16) {
            0 => .short,
            1 => .long,
            _ => return error.InvalidHeadTable,
        };

        return Table{
            .units_per_em = units_per_em,
            .global_bbox = global_bbox,
            .index_to_location_format = index_to_location_format,
        };
    }
};
