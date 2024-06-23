const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const pen = @import("./pen.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;
const PathMetadata = path_module.PathMetadata;
const Paths = path_module.Paths;
const Style = pen.Style;
const Line = curve_module.Line;
const Arc = curve_module.Arc;
const CubicPoints = euler.CubicPoints;
const CubicParams = euler.CubicParams;
const EulerParams = euler.EulerParams;
const EulerSegment = euler.EulerSegment;

const PathRecord = struct {
    fill: Style.Fill,
    offsets: RangeU32,
};

const SubpathRecord = struct {
    offsets: RangeU32,
};

const PathRecordList = std.ArrayListUnmanaged(PathRecord);
const SubpathRecordList = std.ArrayListUnmanaged(SubpathRecord);

pub fn Soup(comptime T: type) type {
    return struct {
        const ItemList = std.ArrayListUnmanaged(T);

        allocator: Allocator,
        path_records: PathRecordList = PathRecordList{},
        subpath_records: SubpathRecordList = SubpathRecordList{},
        items: ItemList = ItemList{},

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.path_records.deinit(self.allocator);
            self.subpath_records.deinit(self.allocator);
            self.items.deinit(self.allocator);
        }

        pub fn getPathRecords(self: @This()) []const PathRecord {
            return self.path_records.items;
        }

        pub fn getSubpathRecords(self: @This()) []const SubpathRecord {
            return self.subpath_records.items;
        }

        pub fn getItems(self: @This()) []const T {
            return self.items.items;
        }

        pub fn openPath(self: *@This(), fill: Style.Fill) !void {
            const path = try self.path_records.addOne(self.allocator);
            path.* = PathRecord{
                .fill = fill,
                .offsets = RangeU32{
                    .start = @intCast(self.subpath_records.items.len),
                    .end = @intCast(self.subpath_records.items.len),
                },
            };
        }

        pub fn closePath(self: *@This()) !void {
            self.path_records.items[self.path_records.items.len - 1].offsets.end = @intCast(self.subpath_records.items.len);
        }

        pub fn openSubpath(self: *@This()) !void {
            const subpath = try self.subpath_records.addOne(self.allocator);
            subpath.* = SubpathRecord{
                .offsets = RangeU32{
                    .start = @intCast(self.items.items.len),
                    .end = @intCast(self.items.items.len),
                },
            };
        }

        pub fn closeSubpath(self: *@This()) !void {
            self.subpath_records.items[self.subpath_records.items.len - 1].offsets.end = @intCast(self.subpath_records.items.len);
        }

        pub fn addItem(self: *@This()) !*T {
            return try self.items.addOne(self.allocator);
        }
    };
}

pub const LineSoup = Soup(Line);
pub const ArcSoup = Soup(Arc);
