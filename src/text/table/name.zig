const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const text = @import("../root.zig");
const util = @import("../util.zig");
const Error = text.Error;
const GlyphId = text.GlyphId;
const Language = text.Language;
const Reader = util.Reader;
const LazyArray = util.LazyArray;
const LazyIntArray = util.LazyIntArray;
const Offset16 = util.Offset16;

pub const KnownNameId = enum(u16) {
    copyright_notice = 0,
    family = 1,
    subfamily = 2,
    unique_id = 3,
    full_name = 4,
    version = 5,
    post_script_name = 6,
    trademark = 7,
    manufacturer = 8,
    designer = 9,
    description = 10,
    vendor_url = 11,
    designer_url = 12,
    license = 13,
    license_url = 14,
    reserved = 15,
    typographic_family = 16,
    typographic_subfamily = 17,
    compatible_full = 18,
    sample_text = 19,
    post_script_cid = 20,
    wws_family = 21,
    wws_subfamily = 22,
    light_background_palette = 23,
    dark_background_palette = 24,
    variations_post_script_name_prefix = 25,
};

pub const NameId = union(enum) {
    known: KnownNameId,
    unknown: u16,

    pub fn read(reader: *Reader) ?NameId {
        const value = reader.readInt(u16) orelse return null;

        if (value <= 25) {
            return NameId{
                .known = @enumFromInt(value),
            };
        }

        return NameId{
            .unknown = value,
        };
    }

    pub fn equalsKnown(self: NameId, known_id: KnownNameId) bool {
        switch (self) {
            .known => |known| return known == known_id,
            else => return false,
        }
    }
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
    pub const ReadSize: usize = 12;

    platform_id: PlatformId, // 2 bytes
    encoding_id: u16, // 2 bytes
    language_id: u16, // 2 bytes
    name_id: NameId, // 2 bytes
    length: u16, // 2 bytes
    offset: Offset16, // 2 bytes

    pub fn read(reader: *Reader) ?NameRecord {
        const platform_id = PlatformId.read(reader) orelse return null;
        const encoding_id = reader.readInt(u16) orelse return null;
        const language_id = reader.readInt(u16) orelse return null;
        const name_id = NameId.read(reader) orelse return null;
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
    name_id: NameId,
    name: []const u8,

    pub fn toUtf8Alloc(self: Name, allocator: Allocator) !?[]u8 {
        if (self.isUnicode()) {
            if (self.name.len % 2 != 0) {
                // TODO: there is probably a better error type here
                return error.InvalidTable;
            }

            const utf16 = try allocator.alloc(u16, self.name.len / 2);
            defer allocator.free(utf16);
            const utf16_from8: []const u16 = @alignCast(std.mem.bytesAsSlice(u16, self.name));

            for (utf16_from8, utf16) |c, *c2| {
                c2.* = std.mem.bigToNative(u16, c);
            }

            return try std.unicode.utf16LeToUtf8Alloc(allocator, utf16);
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

    pub fn get(self: Names, index: usize) ?Name {
        const record = self.records.get(index) orelse return null;
        const name_start: usize = @intCast(record.offset.offset);
        const name_end = name_start + @as(usize, @intCast(record.length));
        const name = self.storage[name_start..name_end];

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

    pub fn iterator(self: Names) Iterator {
        return Iterator{
            .names = self,
            .index = 0,
        };
    }
};

pub const Table = struct {
    const NameRecordsList = LazyArray(NameRecord);

    names: Names,

    pub fn create(data: []const u8) Error!Table {
        const LANG_TAG_SIZE: u16 = 4;

        var reader = Reader.create(data);
        const version = reader.readInt(u16) orelse return error.InvalidTable;
        const count = reader.readInt(u16) orelse return error.InvalidTable;
        const storage_offset = Offset16.read(&reader) orelse return error.InvalidTable;

        if (version == 0) {
            // Do nothing
        } else if (version == 1) {
            const lang_tag_count = reader.readInt(u16) orelse return error.InvalidTable;
            const lang_tag_len = lang_tag_count * LANG_TAG_SIZE;
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

    pub fn getNameAlloc(self: Table, allocator: Allocator, name_id: KnownNameId) !?[]const u8 {
        var iterator = self.names.records.iterator();

        while (iterator.next()) |record| {
            if (record.name_id.equalsKnown(name_id)) {
                const name = self.names.get(iterator.index) orelse return null;
                return try name.toUtf8Alloc(allocator);
            }
        }

        return null;
    }
};
