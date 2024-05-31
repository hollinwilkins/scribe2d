const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const root = @import("../root.zig");
const Error = root.Error;
const LazyArray = root.LazyArray;
const GlyphId = root.GlyphId;
const Reader = root.Reader;
const Offset16 = root.Offset16;
const Language = root.Language;

pub const NameId = struct {
    pub const COPYRIGHT_NOTICE: u16 = 0;
    pub const FAMILY: u16 = 1;
    pub const SUBFAMILY: u16 = 2;
    pub const UNIQUE_ID: u16 = 3;
    pub const FULL_NAME: u16 = 4;
    pub const VERSION: u16 = 5;
    pub const POST_SCRIPT_NAME: u16 = 6;
    pub const TRADEMARK: u16 = 7;
    pub const MANUFACTURER: u16 = 8;
    pub const DESIGNER: u16 = 9;
    pub const DESCRIPTION: u16 = 10;
    pub const VENDOR_URL: u16 = 11;
    pub const DESIGNER_URL: u16 = 12;
    pub const LICENSE: u16 = 13;
    pub const LICENSE_URL: u16 = 14;
    //        RESERVED                                  = 15
    pub const TYPOGRAPHIC_FAMILY: u16 = 16;
    pub const TYPOGRAPHIC_SUBFAMILY: u16 = 17;
    pub const COMPATIBLE_FULL: u16 = 18;
    pub const SAMPLE_TEXT: u16 = 19;
    pub const POST_SCRIPT_CID: u16 = 20;
    pub const WWS_FAMILY: u16 = 21;
    pub const WWS_SUBFAMILY: u16 = 22;
    pub const LIGHT_BACKGROUND_PALETTE: u16 = 23;
    pub const DARK_BACKGROUND_PALETTE: u16 = 24;
    pub const VARIATIONS_POST_SCRIPT_NAME_PREFIX: u16 = 25;
};

pub const PlatformId = enum {
    unicode,
    macintosh,
    iso,
    windows,
    custom,

    pub fn read(reader: *Reader) ?PlatformId {
        const data = reader.readInt(u16) orelse return null;

        return switch (data) {
            0 => .unicode,
            1 => .macintosh,
            2 => .iso,
            3 => .windows,
            4 => .custom,
            else => null,
        };
    }
};

pub fn isUnicodeEncoding(platform_id: PlatformId, encoding_id: u16) bool {
    const WINDOWS_SYMBOL_ENCODING_ID: u16 = 0;
    const WINDOWS_UNICODE_BMP_ENCODING_ID: u16 = 1;

    return switch (platform_id) {
        .unicode => true,
        .windows => encoding_id == WINDOWS_SYMBOL_ENCODING_ID or encoding_id == WINDOWS_UNICODE_BMP_ENCODING_ID,
        else => false,
    };
}

pub const NameRecord = struct {
    pub const ReadSize: usize = @sizeOf(NameRecord);

    platform_id: PlatformId,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    length: u16,
    offset: Offset16,

    pub fn read(reader: *Reader) ?NameRecord {
        const platform_id = PlatformId.read(reader) orelse return null;
        const encoding_id = reader.readInt(u16) orelse return null;
        const language_id = reader.readInt(u16) orelse return null;
        const name_id = reader.readInt(u16) orelse return null;
        const length = reader.readInt(u16) orelse return null;
        const offset = Offset16.read(reader) orelse return null;

        return NameRecord{
            .platform_id = platform_id,
            .encoding_id = encoding_id,
            .language_id = language_id,
            .name_id = name_id,
            .length = length,
            .offset = offset,
        };
    }
};

pub const Name = struct {
    platform_id: PlatformId,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    name: []const u8,

    pub fn toUtf8Alloc(self: Name, allocator: Allocator) !?[]u8 {
        if (self.isUnicode()) {
            return try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.bytesAsSlice(u16, self.name));
        } else {
            return null;
        }
    }

    pub fn isUnicode(self: Name) bool {
        return isUnicodeEncoding(self.platform_id, self.encoding_id);
    }

    pub fn getLanguage(self: Name) Language {
        if (self.platform_id == .windows) {
            return Language.windowsLanguage(self.language_id);
        } else if (self.platform_id == .macintosh and self.encoding_id == 0 and self.language_id == 0) {
            return .English_UnitedStates;
        } else {
            return .Unknown;
        }
    }
};

pub const Names = struct {
    const NamesList = LazyArray(NameRecord);

    pub const Iterator = struct {
        names: Names,
        index: usize,

        pub fn next(self: *Iterator) ?Name {
            self.index += 1;
            return self.names.get(self.index - 1);
        }
    };

    records: NamesList,
    storage: []const u8,

    pub fn get(self: Names, index: u16) ?Name {
        const record = self.records.get(index) orelse return null;
        const name_start: usize = @intCast(record.offset.value);
        const name_end = name_start + @as(usize, @intCast(record.length));
        const name = self.storage.get[name_start..name_end];

        return Name{
            .platform_id = record.platform_id,
            .encoding_id = record.encoding_id,
            .language_id = record.language_id,
            .name_id = record.name_id,
            .name = name,
        };
    }

    pub fn len(self: Names) usize {
        return self.records.len;
    }

    pub fn isEmpty(self: Names) bool {
        return self.len() == 0;
    }
};

pub const Table = struct {
    const NameRecordsList = LazyArray(NameRecord);

    names: Names,

    pub fn create(data: []const u8) Error!Table {
        const LANG_TAG_RECORD_SIZE: u16 = 4;

        var reader = Reader.create(data);
        const version = reader.readInt(u16) orelse return error.InvalidTable;
        const count = reader.readInt(u16) orelse return error.InvalidTable;
        const storage_offset = Offset16.read(&reader) orelse return error.InvalidTable;

        if (version == 0) {
            // Do nothing
        } else if (version == 1) {
            const lang_tag_count = reader.readInt(u16) orelse return error.InvalidTable;
            const lang_tag_len = lang_tag_count * LANG_TAG_RECORD_SIZE;
            reader.skipN(@intCast(lang_tag_len));
        } else {
            return error.InvalidTable;
        }

        const records = NameRecordsList.read(&reader, count) orelse return error.InvalidTable;

        const offset: usize = @intCast(storage_offset.offset);
        if (reader.cursor < offset) {
            reader.skipN(offset - reader.cursor);
        }

        const storage = reader.tail();

        return Table{
            .names = Names{
                .records = records,
                .storage = storage,
            },
        };
    }
};
