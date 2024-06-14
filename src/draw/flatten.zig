const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const pen = @import("./pen.zig");
const curve = @import("./curve.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;
const PathMetadata = path_module.PathMetadata;
const Paths = path_module.Paths;
const PathsUnmanaged = path_module.PathsUnmanaged;
const Style = pen.Style;
const Line = curve.Line;

pub const LineSoup = struct {
    const PathRecord = struct {
        offsets: RangeU32 = RangeU32{},
    };
    const PathRecordList = std.ArrayListUnmanaged(PathRecord);
    const LineList = std.ArrayListUnmanaged(Line);

    allocator: Allocator,
    path_records: PathRecordList = PathRecordList{},
    lines: LineList = LineList{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        self.path_records.deinit(allocator);
        self.lines.deinit(allocator);
    }
};

pub const PathFlattener = struct {
    const PathRecord = struct {
        path_index: u32,
    };

    pub fn flattenAlloc(
        allocator: Allocator,
        metadatas: []const PathMetadata,
        paths: PathsUnmanaged,
        styles: []const Style,
        transforms: []const TransformF32,
    ) !Paths {
        var line_soup = LineSoup.init(allocator);
        var paths = Paths.init(allocator);

        for (metadatas) |metadata| {
            const style = styles[metadata.style_index];
            const transform = transforms[metadata.transform_index];
            _ = style;
            _ = transform;
            for (paths.path_records.items[metadata.path_offsets.start..metadata.path_offsets.end]) |path| {
                _ = path;
                // build lines for line_soup
                // push a PathRecord to line_soup
            }
        }

        return paths;
    }

    // pub fn flatten(paths: []const Path, styles: []const Style, flat_paths: []Path) void {

    // }
};

// for (self.path.getSubpathRecords()) |subpath_record| {
//     for (self.path.getCurveRecords()) |curve_record| {
//         const cubic_points = self.path.getCubicPoints(curve_record);
//         _ = cubic_points;
//         _ = subpath_record;
//     }
// }
