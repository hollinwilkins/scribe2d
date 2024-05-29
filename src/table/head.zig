const root = @import("../root.zig");
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
        _ = data;
        return Table{
            .units_per_em = 0,
            .global_bbox = Rect{},
            .index_to_location_format = .short,
        };

        // if (data.len < 54) {
        //     return error.InvalidHeadTableLength;
        // }

        // let mut s = Stream::new(data);
        // s.skip::<u32>(); // version
        // s.skip::<Fixed>(); // font revision
        // s.skip::<u32>(); // checksum adjustment
        // s.skip::<u32>(); // magic number
        // s.skip::<u16>(); // flags
        // let units_per_em = s.read::<u16>()?;
        // s.skip::<u64>(); // created time
        // s.skip::<u64>(); // modified time
        // let x_min = s.read::<i16>()?;
        // let y_min = s.read::<i16>()?;
        // let x_max = s.read::<i16>()?;
        // let y_max = s.read::<i16>()?;
        // s.skip::<u16>(); // mac style
        // s.skip::<u16>(); // lowest PPEM
        // s.skip::<i16>(); // font direction hint
        // let index_to_location_format = s.read::<u16>()?;

        // if !(16..=16384).contains(&units_per_em) {
        //     return None;
        // }

        // let index_to_location_format = match index_to_location_format {
        //     0 => IndexToLocationFormat::Short,
        //     1 => IndexToLocationFormat::Long,
        //     _ => return None,
        // };

        // Some(Table {
        //     units_per_em,
        //     global_bbox: Rect {
        //         x_min,
        //         y_min,
        //         x_max,
        //         y_max,
        //     },
        //     index_to_location_format,
        // })
    }
};
