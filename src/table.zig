const std = @import("std");
const mem = std.mem;
const root = @import("./root.zig");
const LazyArray = root.LazyArray;
const Offset32 = root.Offset32;
pub const head = @import("./table/head.zig");
pub const hhea = @import("./table/hhea.zig");
pub const maxp = @import("./table/maxp.zig");
pub const loca = @import("./table/loca.zig");
pub const name = @import("./table/name.zig");
pub const glyf = @import("./table/glyf.zig");
const Reader = @import("./root.zig").Reader;

pub const Magic = enum {
    true_type,
    open_type,
    font_collection,

    pub fn read(reader: *Reader) ?Magic {
        if (reader.readInt(u32)) |i| {
            switch (i) {
                0x00010000 => return .true_type,
                0x74727565 => return .true_type,
                0x4F54544F => return .open_type,
                0x74746366 => return .font_collection,
                else => return null,
            }
        }

        return null;
    }
};

pub const Tag = struct {
    value: u32,

    pub fn toBytes(self: Tag) [4]u8 {
        return .{
            @intCast(self.value >> 24 & 0xff),
            @intCast(self.value >> 16 & 0xff),
            @intCast(self.value >> 8 & 0xff),
            @intCast(self.value >> 0 & 0xff),
        };
    }

    pub fn read(reader: *Reader) ?Tag {
        if (reader.read([4]u8)) |bytes| {
            const tag1 = @as(u32, bytes[0]) << 24;
            const tag2 = @as(u32, bytes[1]) << 16;
            const tag3 = @as(u32, bytes[2]) << 8;
            const tag4 = @as(u32, bytes[3]);
            return Tag{
                .value = (tag1 | tag2 | tag3 | tag4),
            };
        }

        return null;
    }
};

pub const TableRecord = struct {
    pub const ReadSize: usize = @sizeOf(TableRecord);

    tag: Tag,
    check_sum: u32,
    offset: u32,
    length: u32,

    pub fn read(reader: *Reader) ?TableRecord {
        const tag = Tag.read(reader) orelse return null;
        const check_sum = reader.readInt(u32) orelse return null;
        const offset = reader.readInt(u32) orelse return null;
        const length = reader.readInt(u32) orelse return null;

        return TableRecord{
            .tag = tag,
            .check_sum = check_sum,
            .offset = offset,
            .length = length,
        };
    }
};

pub const Tables = struct {
    // Mandatory tables.
    head: head.Table,
    hhea: hhea.Table,
    maxp: maxp.Table,

    name: ?name.Table,

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

    pub fn create(raw: RawTables.TableRecords) !Tables {
        const head_table = try head.Table.create(raw.head);
        const hhea_table = try hhea.Table.create(raw.hhea);
        const maxp_table = try maxp.Table.create(raw.hhea);

        var name_table: ?name.Table = null;
        if (raw.name) |data| {
            name_table = try name.Table.create(data);
        }

        return Tables{
            .head = head_table,
            .hhea = hhea_table,
            .maxp = maxp_table,

            .name = name_table,
        };
    }
};

pub const RawTables = struct {
    pub const TableRecordsList = LazyArray(TableRecord);
    pub const OffsetsList = LazyArray(Offset32);

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
                const tag_name = &tag;
                const table_data = data[tr.offset .. tr.offset + tr.length];

                if (std.mem.eql(u8, tag_name, "bdat")) {
                    tables.bdat = table_data;
                } else if (std.mem.eql(u8, tag_name, "bloc")) {
                    tables.bloc = table_data;
                } else if (std.mem.eql(u8, tag_name, "CBDT")) {
                    tables.cbdt = table_data;
                } else if (std.mem.eql(u8, tag_name, "CBLC")) {
                    tables.cblc = table_data;
                } else if (std.mem.eql(u8, tag_name, "CFF")) {
                    tables.cff = table_data;
                } else if (std.mem.eql(u8, tag_name, "CFF2")) {
                    tables.cff2 = table_data;
                } else if (std.mem.eql(u8, tag_name, "COLR")) {
                    tables.colr = table_data;
                } else if (std.mem.eql(u8, tag_name, "CPAL")) {
                    tables.cpal = table_data;
                } else if (std.mem.eql(u8, tag_name, "EBDT")) {
                    tables.ebdt = table_data;
                } else if (std.mem.eql(u8, tag_name, "EBLC")) {
                    tables.eblc = table_data;
                } else if (std.mem.eql(u8, tag_name, "GDEF")) {
                    tables.gdef = table_data;
                } else if (std.mem.eql(u8, tag_name, "GPOS")) {
                    tables.gpos = table_data;
                } else if (std.mem.eql(u8, tag_name, "GSUB")) {
                    tables.gsub = table_data;
                } else if (std.mem.eql(u8, tag_name, "MATH")) {
                    tables.math = table_data;
                } else if (std.mem.eql(u8, tag_name, "HVAR")) {
                    tables.hvar = table_data;
                } else if (std.mem.eql(u8, tag_name, "OS/2")) {
                    tables.os2 = table_data;
                } else if (std.mem.eql(u8, tag_name, "SVG")) {
                    tables.svg = table_data;
                } else if (std.mem.eql(u8, tag_name, "VORG")) {
                    tables.vorg = table_data;
                } else if (std.mem.eql(u8, tag_name, "VVAR")) {
                    tables.vvar = table_data;
                } else if (std.mem.eql(u8, tag_name, "ankr")) {
                    tables.ankr = table_data;
                } else if (std.mem.eql(u8, tag_name, "avar")) {
                    tables.avar = table_data;
                } else if (std.mem.eql(u8, tag_name, "cmap")) {
                    tables.cmap = table_data;
                } else if (std.mem.eql(u8, tag_name, "feat")) {
                    tables.feat = table_data;
                } else if (std.mem.eql(u8, tag_name, "fvar")) {
                    tables.fvar = table_data;
                } else if (std.mem.eql(u8, tag_name, "glyf")) {
                    tables.glyf = table_data;
                } else if (std.mem.eql(u8, tag_name, "gvar")) {
                    tables.gvar = table_data;
                } else if (std.mem.eql(u8, tag_name, "head")) {
                    tables.head = table_data;
                    checks.head = true;
                } else if (std.mem.eql(u8, tag_name, "hhea")) {
                    tables.hhea = table_data;
                    checks.hhea = true;
                } else if (std.mem.eql(u8, tag_name, "hmtx")) {
                    tables.hmtx = table_data;
                } else if (std.mem.eql(u8, tag_name, "kern")) {
                    tables.kern = table_data;
                } else if (std.mem.eql(u8, tag_name, "kerx")) {
                    tables.kerx = table_data;
                } else if (std.mem.eql(u8, tag_name, "loca")) {
                    tables.loca = table_data;
                } else if (std.mem.eql(u8, tag_name, "maxp")) {
                    tables.maxp = table_data;
                    checks.maxp = true;
                } else if (std.mem.eql(u8, tag_name, "morx")) {
                    tables.morx = table_data;
                } else if (std.mem.eql(u8, tag_name, "name")) {
                    tables.name = table_data;
                } else if (std.mem.eql(u8, tag_name, "post")) {
                    tables.post = table_data;
                } else if (std.mem.eql(u8, tag_name, "sbix")) {
                    tables.sbix = table_data;
                } else if (std.mem.eql(u8, tag_name, "trak")) {
                    tables.trak = table_data;
                } else if (std.mem.eql(u8, tag_name, "vhea")) {
                    tables.vhea = table_data;
                } else if (std.mem.eql(u8, tag_name, "vmtx")) {
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

    pub fn create(data: []const u8, index: usize) !RawTables {
        var r = Reader.create(data);
        return try read(&r, index);
    }

    pub fn read(reader: *Reader, index: usize) !RawTables {
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

        return RawTables{
            .table_records = table_records,
        };
    }
};
