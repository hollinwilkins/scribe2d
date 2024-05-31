const root = @import("../root.zig");
const Error = root.Error;
const Fixed = root.Fixed;
const Rect = root.draw.RectI16;
const Reader = root.Reader;

pub const IndexToLocationFormat = enum {
    short,
    long,

    pub fn read(reader: *Reader) ?IndexToLocationFormat {
        if (reader.read(u16)) |i| {
            switch (i) {
                0 => return .short,
                1 => return .long,
                else => return null,
            }
        }

        return null;
    }
};

pub const Table = struct {
    units_per_em: u16,
    global_bbox: Rect,
    index_to_location_format: IndexToLocationFormat,

    pub fn create(data: []const u8) Error!Table {
        if (data.len < 54) {
            return error.InvalidTable;
        }

        var r = Reader.create(data);
        r.skip(u32); // version
        _ = Fixed.read(&r).?; // font revision
        r.skip(u32); // checksum adjustment
        r.skip(u32); // magic number
        r.skip(u16); // flags
        const units_per_em = r.readInt(u16).?;
        r.skip(u64); // create time
        r.skip(u64); // modified time
        const global_bbox = Rect.read(&r).?;
        r.skip(u16); // max style
        r.skip(u16); // lowest PPEM
        r.skip(i16); // font direction hint
        const index_to_location_format = IndexToLocationFormat.read(&r).?;

        if (units_per_em < 16 or units_per_em > 16384) {
            return error.InvalidTable;
        }

        return Table{
            .units_per_em = units_per_em,
            .global_bbox = global_bbox,
            .index_to_location_format = index_to_location_format,
        };
    }
};
