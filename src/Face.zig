const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const root = @import("./root.zig");
const Rect = root.RectI16;
const Magic = root.Magic;
const Reader = root.Reader;
const Offset32 = root.Offset32;
const table = @import("./table.zig");
const Tables = table.Tables;
const RawTables = table.RawTables;

const Face = @This();

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
    const raw_face = try RawTables.read(&reader, 0);
    const raw_tables = try RawTables.TableRecords.create(data, raw_face.table_records);

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

    const name_table = rm_face.unmanaged.tables.name.?;
    const family = (try name_table.getNameAlloc(std.testing.allocator, .family)).?;
    defer std.testing.allocator.free(family);

    const outline_builder = root.OutlineBuilder.Debug.Instance;
    const bounds = try rm_face.unmanaged.tables.glyf.?.outline(91, outline_builder);
    _ = bounds;

    const raw = try RawTables.create(rm_face.unmanaged.data, 0);
    var iter = raw.table_records.iterator();

    while (iter.next()) |tr| {
        const name = tr.tag.toBytes();
        std.debug.print("Table: {s}\n", .{&name});
    }
}
