const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const pen = @import("./pen.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const scene_module = @import("./scene.zig");
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
const Scene = scene_module.Scene;

pub const Estimate = struct {
    intersections: u32 = 0,
    items: u32 = 0,

    pub fn add(self: @This(), other: @This()) @This() {
        return @This(){
            .intersections = self.intersections + other.intersections,
            .items = self.items + other.items,
        };
    }

    pub fn mulScalar(self: @This(), value: f32) @This() {
        return @This(){
            .intersections = @intFromFloat(@as(f32, @floatFromInt(self.intersections)) * value),
            .items = @intFromFloat(@as(f32, @floatFromInt(self.items)) * value),
        };
    }
};

pub fn Soup(comptime T: type) type {
    return struct {
        pub const Encoding = struct {
            path_records: []const PathRecord,
            subpath_records: []const SubpathRecord,
            curve_estimates: []const Estimate,
            items: []const T,
        };

        pub const PathRecord = struct {
            subpath_offsets: RangeU32,
        };

        pub const SubpathRecord = struct {
            estimate: Estimate = Estimate{},
            item_offsets: RangeU32,
        };

        pub const PathRecordList = std.ArrayListUnmanaged(PathRecord);
        pub const SubpathRecordList = std.ArrayListUnmanaged(SubpathRecord);
        pub const EstimateList = std.ArrayListUnmanaged(Estimate);
        pub const ItemList = std.ArrayListUnmanaged(T);

        allocator: Allocator,
        path_records: PathRecordList = PathRecordList{},
        subpath_records: SubpathRecordList = SubpathRecordList{},
        curve_estimates: EstimateList = EstimateList{},
        items: ItemList = ItemList{},

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.path_records.deinit(self.allocator);
            self.subpath_records.deinit(self.allocator);
            self.curve_estimates.deinit(self.allocator);
            self.items.deinit(self.allocator);
        }

        pub fn toEncoding(self: @This()) Encoding {
            return Encoding{
                .path_records = self.path_records.items,
                .subpath_records = self.subpath_records.items,
                .curve_estimates = self.curve_estimates.items,
                .items = self.items.items,
            };
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

        pub fn openPath(self: *@This()) !*PathRecord {
            const path = try self.path_records.addOne(self.allocator);
            path.* = PathRecord{
                .subpath_offsets = RangeU32{
                    .start = @intCast(self.subpath_records.items.len),
                    .end = @intCast(self.subpath_records.items.len),
                },
            };
            return path;
        }

        pub fn closePath(self: *@This()) void {
            self.path_records.items[self.path_records.items.len - 1].subpath_offsets.end = @intCast(self.subpath_records.items.len);
        }

        pub fn openSubpath(self: *@This()) !*SubpathRecord {
            const subpath = try self.subpath_records.addOne(self.allocator);
            subpath.* = SubpathRecord{
                .item_offsets = RangeU32{
                    .start = @intCast(self.items.items.len),
                    .end = @intCast(self.items.items.len),
                },
            };
            return subpath;
        }

        pub fn closeSubpath(self: *@This()) void {
            self.subpath_records.items[self.subpath_records.items.len - 1].item_offsets.end = @intCast(self.items.items.len);
        }

        pub fn addCurveEstimate(self: *@This()) !*Estimate {
            return try self.curve_estimates.addOne(self.allocator);
        }

        pub fn addCurveEstimates(self: *@This(), n: usize) ![]Estimate {
            return try self.curve_estimates.addManyAsSlice(self.allocator, n);
        }

        pub fn addItem(self: *@This()) !*T {
            return try self.items.addOne(self.allocator);
        }

        pub fn addItems(self: *@This(), n: usize) ![]T {
            return try self.items.addManyAsSlice(self.allocator, n);
        }
    };
}

pub const LineSoup = Soup(Line);
