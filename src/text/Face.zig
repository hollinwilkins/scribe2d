const std = @import("std");
const table = @import("./table/table.zig");
const util = @import("./util.zig");
const text = @import("./root.zig");
const core = @import("../core/root.zig");
const GlyphPen = @import("./GlyphPen.zig");
const GlyphBuilder = @import("./GlyphBuilder.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const GlyphId = text.GlyphId;
const Rect = util.RectI16;
const Magic = util.Magic;
const Reader = util.Reader;
const Offset32 = util.Offset32;
const Transform = util.Transform;
const Tables = table.Tables;
const RawTables = table.RawTables;
const RectF32 = core.RectF32;
const TransformF32 = core.TransformF32;
const PointF32 = core.PointF32;

const VariableCoordinates = struct {};
const Unmanaged = struct {
    data: []const u8,
    tables: Tables,
    raw_tables: RawTables,
    coordinates: VariableCoordinates,

    pub fn deinit(self: *Unmanaged, allocator: Allocator) void {
        allocator.free(self.data);
    }
};

pub const Face = struct {
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
                .raw_tables = raw_face,
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

    pub fn outline(self: Face, glyph_id: GlyphId, points: f32, pen: GlyphPen) !RectF32 {
        var builder = GlyphBuilder.create(
            null,
            Transform{},
            pen,
        );

        if (self.unmanaged.tables.glyf) |glyf| {
            const units_per_em: f32 = @floatFromInt(self.unmanaged.tables.head.units_per_em);
            const bounds = try glyf.outline(glyph_id, points, &builder);
            const transform = TransformF32{
                .scale = PointF32{
                    .x = points / units_per_em,
                    .y = points / units_per_em,
                },
                .translate = PointF32{
                    .x = -bounds.min.x,
                    .y = -bounds.min.y,
                },
            };
            const bounds2 = bounds.transform(transform);

            builder.pen.transform(transform);
            builder.pen.transform(TransformF32{
                .scale = PointF32{
                    .x = 1.0,
                    .y = -1.0,
                },
                .translate = PointF32{
                    .x = 0.0,
                    .y = -(bounds2.getHeight() / 2.0),
                }
            });
            builder.pen.transform(TransformF32{
                .scale = PointF32{
                    .x = 1.0,
                    .y = 1.0,
                },
                .translate = PointF32{
                    .x = 0.0,
                    .y = bounds2.getHeight() / 2.0,
                }
            });
            return bounds2;
        } else {
            return error.InvalidFace;
        }
    }
};

test "parsing roboto medium" {
    var rm_face = try Face.initFile(std.testing.allocator, "fixtures/fonts/roboto-medium.ttf");
    defer rm_face.deinit();

    const name_table = rm_face.unmanaged.tables.name.?;
    const family = (try name_table.getNameAlloc(std.testing.allocator, .family)).?;
    defer std.testing.allocator.free(family);

    const outliner = GlyphPen.Debug.Instance;
    const bounds = try rm_face.unmanaged.tables.glyf.?.outline(48, outliner);
    _ = bounds;

    const raw = try RawTables.create(rm_face.unmanaged.data, 0);
    var iter = raw.table_records.iterator();

    while (iter.next()) |tr| {
        const name = tr.tag.toBytes();
        std.debug.print("Table: {s}\n", .{&name});
    }
}
