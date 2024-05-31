const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const root = @import("./root.zig");
const Rect = root.RectI16;
const Magic = root.Magic;
const Reader = root.Reader;
const Offset32 = root.Offset32;
const table = @import("./table.zig");
const TableRecord = table.TableRecord;

const Face = @This();

const Tables = struct {
    // Mandatory tables.
    head: table.head.Table,
    hhea: table.hhea.Table,
    maxp: table.maxp.Table,

    name: ?table.name.Table,

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

    pub fn create(raw: Raw.TableRecords) !Tables {
        const head = try table.head.Table.create(raw.head);
        const hhea = try table.hhea.Table.create(raw.hhea);
        const maxp = try table.maxp.Table.create(raw.hhea);

        var name: ?table.name.Table = null;
        if (raw.name) |data| {
            name = try table.name.Table.create(data);
        }

        return Tables{
            .head = head,
            .hhea = hhea,
            .maxp = maxp,

            .name = name,
        };
    }
};

pub const Raw = struct {
    pub const TableRecordsList = root.LazyArray(TableRecord);
    pub const OffsetsList = root.LazyArray(Offset32);

    const HasRequiredTables = struct {
        head: bool = false,
        hhea: bool = false,
        maxp: bool = false,

        fn check(self: HasRequiredTables) bool {
            return self.head and self.hhea and self.maxp;
        }
    };

    pub const TableRecords = struct {

        // Mandatory tables.
        head: []const u8 = &.{},
        hhea: []const u8 = &.{},
        maxp: []const u8 = &.{},

        bdat: ?[]const u8 = null,
        bloc: ?[]const u8 = null,
        cbdt: ?[]const u8 = null,
        cblc: ?[]const u8 = null,
        cff: ?[]const u8 = null,
        cmap: ?[]const u8 = null,
        colr: ?[]const u8 = null,
        cpal: ?[]const u8 = null,
        ebdt: ?[]const u8 = null,
        eblc: ?[]const u8 = null,
        glyf: ?[]const u8 = null,
        hmtx: ?[]const u8 = null,
        kern: ?[]const u8 = null,
        loca: ?[]const u8 = null,
        name: ?[]const u8 = null,
        os2: ?[]const u8 = null,
        post: ?[]const u8 = null,
        sbix: ?[]const u8 = null,
        svg: ?[]const u8 = null,
        vhea: ?[]const u8 = null,
        vmtx: ?[]const u8 = null,
        vorg: ?[]const u8 = null,

        // opentype layout
        gdef: ?[]const u8 = null,
        gpos: ?[]const u8 = null,
        gsub: ?[]const u8 = null,
        math: ?[]const u8 = null,

        // apple layout
        ankr: ?[]const u8 = null,
        feat: ?[]const u8 = null,
        kerx: ?[]const u8 = null,
        morx: ?[]const u8 = null,
        trak: ?[]const u8 = null,

        // variable fonts
        avar: ?[]const u8 = null,
        cff2: ?[]const u8 = null,
        fvar: ?[]const u8 = null,
        gvar: ?[]const u8 = null,
        hvar: ?[]const u8 = null,
        mvar: ?[]const u8 = null,
        vvar: ?[]const u8 = null,

        pub fn create(data: []const u8, table_records: TableRecordsList) !TableRecords {
            var tables = TableRecords{};
            var checks = HasRequiredTables{};
            var iter = table_records.iterator();

            while (iter.next()) |tr| {
                const tag = tr.tag.toBytes();
                const name = &tag;
                const table_data = data[tr.offset .. tr.offset + tr.length];

                if (std.mem.eql(u8, name, "bdat")) {
                    tables.bdat = table_data;
                } else if (std.mem.eql(u8, name, "bloc")) {
                    tables.bloc = table_data;
                } else if (std.mem.eql(u8, name, "CBDT")) {
                    tables.cbdt = table_data;
                } else if (std.mem.eql(u8, name, "CBLC")) {
                    tables.cblc = table_data;
                } else if (std.mem.eql(u8, name, "CFF")) {
                    tables.cff = table_data;
                } else if (std.mem.eql(u8, name, "CFF2")) {
                    tables.cff2 = table_data;
                } else if (std.mem.eql(u8, name, "COLR")) {
                    tables.colr = table_data;
                } else if (std.mem.eql(u8, name, "CPAL")) {
                    tables.cpal = table_data;
                } else if (std.mem.eql(u8, name, "EBDT")) {
                    tables.ebdt = table_data;
                } else if (std.mem.eql(u8, name, "EBLC")) {
                    tables.eblc = table_data;
                } else if (std.mem.eql(u8, name, "GDEF")) {
                    tables.gdef = table_data;
                } else if (std.mem.eql(u8, name, "GPOS")) {
                    tables.gpos = table_data;
                } else if (std.mem.eql(u8, name, "GSUB")) {
                    tables.gsub = table_data;
                } else if (std.mem.eql(u8, name, "MATH")) {
                    tables.math = table_data;
                } else if (std.mem.eql(u8, name, "HVAR")) {
                    tables.hvar = table_data;
                } else if (std.mem.eql(u8, name, "OS/2")) {
                    tables.os2 = table_data;
                } else if (std.mem.eql(u8, name, "SVG")) {
                    tables.svg = table_data;
                } else if (std.mem.eql(u8, name, "VORG")) {
                    tables.vorg = table_data;
                } else if (std.mem.eql(u8, name, "VVAR")) {
                    tables.vvar = table_data;
                } else if (std.mem.eql(u8, name, "ankr")) {
                    tables.ankr = table_data;
                } else if (std.mem.eql(u8, name, "avar")) {
                    tables.avar = table_data;
                } else if (std.mem.eql(u8, name, "cmap")) {
                    tables.cmap = table_data;
                } else if (std.mem.eql(u8, name, "feat")) {
                    tables.feat = table_data;
                } else if (std.mem.eql(u8, name, "fvar")) {
                    tables.fvar = table_data;
                } else if (std.mem.eql(u8, name, "glyf")) {
                    tables.glyf = table_data;
                } else if (std.mem.eql(u8, name, "gvar")) {
                    tables.gvar = table_data;
                } else if (std.mem.eql(u8, name, "head")) {
                    tables.head = table_data;
                    checks.head = true;
                } else if (std.mem.eql(u8, name, "hhea")) {
                    tables.hhea = table_data;
                    checks.hhea = true;
                } else if (std.mem.eql(u8, name, "hmtx")) {
                    tables.hmtx = table_data;
                } else if (std.mem.eql(u8, name, "kern")) {
                    tables.kern = table_data;
                } else if (std.mem.eql(u8, name, "kerx")) {
                    tables.kerx = table_data;
                } else if (std.mem.eql(u8, name, "loca")) {
                    tables.loca = table_data;
                } else if (std.mem.eql(u8, name, "maxp")) {
                    tables.maxp = table_data;
                    checks.maxp = true;
                } else if (std.mem.eql(u8, name, "morx")) {
                    tables.morx = table_data;
                } else if (std.mem.eql(u8, name, "name")) {
                    tables.name = table_data;
                } else if (std.mem.eql(u8, name, "post")) {
                    tables.post = table_data;
                } else if (std.mem.eql(u8, name, "sbix")) {
                    tables.sbix = table_data;
                } else if (std.mem.eql(u8, name, "trak")) {
                    tables.trak = table_data;
                } else if (std.mem.eql(u8, name, "vhea")) {
                    tables.vhea = table_data;
                } else if (std.mem.eql(u8, name, "vmtx")) {
                    tables.vmtx = table_data;
                }
            }

            if (!checks.check()) {
                return error.MissingHead;
            }

            return tables;
        }
    };

    table_records: TableRecordsList,

    pub fn create(data: []const u8, index: usize) !Raw {
        var r = Reader.create(data);
        return try read(&r, index);
    }

    pub fn read(reader: *Reader, index: usize) !Raw {
        const magic = Magic.read(reader) orelse return error.FaceMagicError;

        if (magic == .font_collection) {
            reader.skip(u32); // version
            const number_of_faces = reader.readInt(u32) orelse return error.MalformedFont;
            const offsets = OffsetsList.read(reader, number_of_faces) orelse return error.MalformedFont;
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
        const table_records = TableRecordsList.read(reader, num_tables) orelse return error.MalformedFont;

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
    const raw_tables = try Raw.TableRecords.create(data, raw_face.table_records);

    return Face{
        .allocator = allocator,
        .unmanaged = Unmanaged{
            .data = data,
            .tables = try Tables.create(raw_tables),
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

    const name = rm_face.unmanaged.tables.name.?;

    const raw = try Raw.create(rm_face.unmanaged.data, 0);
    var iter = raw.table_records.iterator();

    while (iter.next()) |tr| {
        const name = tr.tag.toBytes();
        std.debug.print("Table: {s}\n", .{&name});
    }
}
