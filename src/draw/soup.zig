const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const soup_pen = @import("./soup_pen.zig");
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
const Style = soup_pen.Style;
const Line = curve_module.Line;
const Arc = curve_module.Arc;
const CubicPoints = euler.CubicPoints;
const CubicParams = euler.CubicParams;
const EulerParams = euler.EulerParams;
const EulerSegment = euler.EulerSegment;
const Scene = scene_module.Scene;

pub fn Soup(comptime T: type) type {
    return struct {
        pub const PathRecord = struct {
            fill: Style.Fill,
            subpath_offsets: RangeU32,
        };

        pub const SubpathRecord = struct {
            curve_offsets: RangeU32,
        };

        pub const CurveRecord = struct {
            item_offsets: RangeU32,
        };

        pub const FillJob = struct {
            // index in the source Paths struct for the curve data
            metadata_index: u32,
            source_curve_index: u32,
            curve_index: u32,
        };
        pub const StrokeJob = struct {
            // index in the source Paths struct for the curve data
            metadata_index: u32,
            source_subpath_index: u32,
            source_curve_index: u32,
            left_curve_index: u32,
            right_curve_index: u32,
        };

        pub const PathRecordList = std.ArrayListUnmanaged(PathRecord);
        pub const SubpathRecordList = std.ArrayListUnmanaged(SubpathRecord);
        pub const CurveRecordList = std.ArrayListUnmanaged(CurveRecord);
        pub const EstimateList = std.ArrayListUnmanaged(u32);
        pub const FillJobList = std.ArrayListUnmanaged(FillJob);
        pub const StrokeJobList = std.ArrayListUnmanaged(StrokeJob);
        pub const ItemList = std.ArrayListUnmanaged(T);

        allocator: Allocator,
        path_records: PathRecordList = PathRecordList{},
        subpath_records: SubpathRecordList = SubpathRecordList{},
        curve_records: CurveRecordList = CurveRecordList{},
        curve_estimates: EstimateList = EstimateList{},
        base_estimates: EstimateList = EstimateList{},
        fill_jobs: FillJobList = FillJobList{},
        stroke_jobs: StrokeJobList = StrokeJobList{},
        items: ItemList = ItemList{},

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.path_records.deinit(self.allocator);
            self.subpath_records.deinit(self.allocator);
            self.curve_records.deinit(self.allocator);
            self.curve_estimates.deinit(self.allocator);
            self.base_estimates.deinit(self.allocator);
            self.fill_jobs.deinit(self.allocator);
            self.stroke_jobs.deinit(self.allocator);
            self.items.deinit(self.allocator);
        }

        pub fn openPath(self: *@This(), fill: Style.Fill) !*PathRecord {
            const path = try self.path_records.addOne(self.allocator);
            path.* = PathRecord{
                .fill = fill,
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
                .curve_offsets = RangeU32{
                    .start = @intCast(self.curve_records.items.len),
                    .end = @intCast(self.curve_records.items.len),
                },
            };
            return subpath;
        }

        pub fn closeSubpath(self: *@This()) void {
            self.subpath_records.items[self.subpath_records.items.len - 1].curve_offsets.end = @intCast(self.curve_records.items.len);
        }

        pub fn openCurve(self: *@This()) !*CurveRecord {
            const curve = try self.curve_records.addOne(self.allocator);
            curve.* = CurveRecord{
                .item_offsets = RangeU32{
                    .start = @intCast(self.items.items.len),
                    .end = @intCast(self.items.items.len),
                },
            };
            return curve;
        }

        pub fn closeCurve(self: *@This()) void {
            self.curve_records.items[self.curve_records.items.len - 1].item_offsets.end = @intCast(self.items.items.len);
        }

        pub fn addCurveEstimate(self: *@This()) !*u32 {
            return try self.curve_estimates.addOne(self.allocator);
        }

        pub fn addCurveEstimates(self: *@This(), n: usize) ![]u32 {
            return try self.curve_estimates.addManyAsSlice(self.allocator, n);
        }

        pub fn addBaseEstimate(self: *@This()) !*u32 {
            return try self.base_estimates.addOne(self.allocator);
        }

        pub fn addBaseEstimates(self: *@This(), n: usize) ![]u32 {
            return try self.base_estimates.addManyAsSlice(self.allocator, n);
        }

        pub fn addItem(self: *@This()) !*T {
            return try self.items.addOne(self.allocator);
        }

        pub fn addItems(self: *@This(), n: usize) ![]T {
            return try self.items.addManyAsSlice(self.allocator, n);
        }

        pub fn addFillJob(self: *@This()) !*FillJob {
            return try self.fill_jobs.addOne(self.allocator);
        }

        pub fn addFillJobs(self: *@This(), n: usize) ![]FillJob {
            return try self.fill_jobs.addManyAsSlice(self.allocator, n);
        }

        pub fn addStrokeJob(self: *@This()) !*FillJob {
            return try self.stroke_jobs.addOne(self.allocator);
        }

        pub fn addStrokeJobs(self: *@This(), n: usize) ![]StrokeJob {
            return try self.stroke_jobs.addManyAsSlice(self.allocator, n);
        }
    };
}

pub const LineSoup = Soup(Line);
