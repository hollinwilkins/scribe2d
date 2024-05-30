const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const root = @import("./root.zig");
const Rect = root.Rect;
const Magic = root.Magic;
const Reader = root.Reader;
const Offset32 = root.Offset32;
const table = @import("./table.zig");
const TableRecord = table.TableRecord;
const head = table.head;

const Face = @This();

const Error = error{
    FaceMagicError,
    FaceParsingError,
    MalformedFont,
    FaceIndexOutOfBounds,
};

const Tables = struct {
    // Mandatory tables.
    head: head.Table,
    // pub head: head::Table,
    // pub hhea: hhea::Table,
    // pub maxp: maxp::Table,

    // pub bdat: Option<cbdt::Table<'a>>,
    // pub cbdt: Option<cbdt::Table<'a>>,
    // pub cff: Option<cff::Table<'a>>,
    // pub cmap: Option<cmap::Table<'a>>,
    // pub colr: Option<colr::Table<'a>>,
    // pub ebdt: Option<cbdt::Table<'a>>,
    // pub glyf: Option<glyf::Table<'a>>,
    // pub hmtx: Option<hmtx::Table<'a>>,
    // pub kern: Option<kern::Table<'a>>,
    // pub name: Option<name::Table<'a>>,
    // pub os2: Option<os2::Table<'a>>,
    // pub post: Option<post::Table<'a>>,
    // pub sbix: Option<sbix::Table<'a>>,
    // pub svg: Option<svg::Table<'a>>,
    // pub vhea: Option<vhea::Table>,
    // pub vmtx: Option<hmtx::Table<'a>>,
    // pub vorg: Option<vorg::Table<'a>>,

    // #[cfg(feature = "opentype-layout")]
    // pub gdef: Option<gdef::Table<'a>>,
    // #[cfg(feature = "opentype-layout")]
    // pub gpos: Option<opentype_layout::LayoutTable<'a>>,
    // #[cfg(feature = "opentype-layout")]
    // pub gsub: Option<opentype_layout::LayoutTable<'a>>,
    // #[cfg(feature = "opentype-layout")]
    // pub math: Option<math::Table<'a>>,

    // #[cfg(feature = "apple-layout")]
    // pub ankr: Option<ankr::Table<'a>>,
    // #[cfg(feature = "apple-layout")]
    // pub feat: Option<feat::Table<'a>>,
    // #[cfg(feature = "apple-layout")]
    // pub kerx: Option<kerx::Table<'a>>,
    // #[cfg(feature = "apple-layout")]
    // pub morx: Option<morx::Table<'a>>,
    // #[cfg(feature = "apple-layout")]
    // pub trak: Option<trak::Table<'a>>,

    // #[cfg(feature = "variable-fonts")]
    // pub avar: Option<avar::Table<'a>>,
    // #[cfg(feature = "variable-fonts")]
    // pub cff2: Option<cff2::Table<'a>>,
    // #[cfg(feature = "variable-fonts")]
    // pub fvar: Option<fvar::Table<'a>>,
    // #[cfg(feature = "variable-fonts")]
    // pub gvar: Option<gvar::Table<'a>>,
    // #[cfg(feature = "variable-fonts")]
    // pub hvar: Option<hvar::Table<'a>>,
    // #[cfg(feature = "variable-fonts")]
    // pub mvar: Option<mvar::Table<'a>>,
    // #[cfg(feature = "variable-fonts")]
    // pub vvar: Option<hvar::Table<'a>>,
};

pub const Raw = struct {
    pub const TableRecords = root.LazyArray(TableRecord);
    pub const Offsets = root.LazyArray(Offset32);

    table_records: TableRecords,

    pub fn read(reader: *Reader, index: usize) !Raw {
        const magic = Magic.read(reader) orelse return error.FaceMagicError;

        if (magic == .font_collection) {
            reader.skip(u32); // version
            const number_of_faces = reader.readInt(u32) orelse return error.MalformedFont;
            const offsets = Offsets.read(reader, number_of_faces) orelse return error.MalformedFont;
            const face_offset = offsets.get(index) orelse return error.FaceIndexOutOfBounds;

            if (!reader.setCursorChecked(face_offset.offset)) {
                return error.MalformedFont;
            }

            const font_magic = Magic.read(reader) orelse return error.FaceMagicError;
            if (font_magic == .font_collection) {
                return error.MalformedFont;
            }
        } else {
            if (index != 0) {
                return error.FaceParsingError;
            }
        }

        const num_tables = reader.readInt(u16) orelse return error.MalformedFont;
        reader.skipN(6); // searchRange (u16) + entrySelector (u16) + rangeShift (u16)
        const table_records = TableRecords.read(reader, num_tables) orelse return error.MalformedFont;

        return Raw{
            .table_records = table_records,
        };
    }
};

const VariableCoordinates = struct {};
const Unmanaged = struct {
    data: []const u8,
    tables: Tables,
    coordinates: VariableCoordinates,

    pub fn deinit(self: *Unmanaged, allocator: Allocator) void {
        allocator.free(self.data);
    }
};

allocator: Allocator,
unmanaged: Unmanaged,

pub fn initFile(allocator: Allocator, path: []const u8) !Face {
    const data = try readFileBytesAlloc(allocator, path);
    var reader = Reader.create(data);
    const raw_face = try Raw.read(&reader, 0);
    _ = raw_face;

    return Face{
        .allocator = allocator,
        .unmanaged = Unmanaged{
            .data = data,
            .tables = Tables{
                .head = head.Table{
                    .global_bbox = Rect{},
                    .index_to_location_format = .long,
                    .units_per_em = 23,
                },
            },
            .coordinates = VariableCoordinates{},
        },
    };
}

pub fn deinit(self: *Face) void {
    self.unmanaged.deinit(self.allocator);
}

fn readFileBytesAlloc(allocator: Allocator, path: []const u8) ![]const u8 {
    const absolute_path = try std.fs.realpathAlloc(allocator, path);
    defer allocator.free(absolute_path);

    var file = try std.fs.openFileAbsolute(absolute_path, .{
        .mode = .read_only,
    });
    defer file.close();

    // Read the file into a buffer.
    const stat = try file.stat();
    return try file.readToEndAlloc(allocator, stat.size);
}

test "parsing roboto medium" {
    var rm_face = try Face.initFile(std.testing.allocator, "fixtures/fonts/roboto-medium.ttf");
    defer rm_face.deinit();
}
