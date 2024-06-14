const std = @import("std");
const text = @import("../text/root.zig");
const core = @import("../core/root.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const pen = @import("./pen.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const TransformF32 = core.TransformF32;
const SequenceU32 = core.SequenceU32;
const GlyphPen = text.GlyphPen;
const Curve = curve_module.Curve;
const Line = curve_module.Line;
const QuadraticBezier = curve_module.QuadraticBezier;
const CubicPoints = euler.CubicPoints;
const Style = pen.Style;

pub const Scene = struct {
    pub const PathRecord = struct {
        subpath_offsets: RangeU32,
        is_closed: bool = false,
    };

    pub const SubpathRecord = struct {
        curve_offsets: RangeU32,
    };

    pub const CurveRecord = struct {
        pub const Kind = enum(u8) {
            line = 0,
            quadratic_bezier = 1,
        };

        kind: Kind,
        point_offsets: RangeU32,
        is_end: bool = false,
        is_open: bool = false,
    };

    const PathRecordList = std.ArrayListUnmanaged(PathRecord);
    const StyleList = std.ArrayListUnmanaged(Style);
    const SubpathRecordList = std.ArrayListUnmanaged(SubpathRecord);
    const CurveRecordList = std.ArrayListUnmanaged(CurveRecord);
    const PointList = std.ArrayListUnmanaged(PointF32);

    allocator: Allocator,
    path_records: PathRecordList = PathRecordList{},
    styles: StyleList = StyleList{}, // parallell with path_records
    subpath_records: SubpathRecordList = SubpathRecordList{},
    curve_records: CurveRecordList = CurveRecordList{},
    points: PointList = PointList{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.path_records.deinit(self.allocator);
        self.styles.deinit(self.allocator);
        self.subpath_records.deinit(self.allocator);
        self.curve_records.deinit(self.allocator);
        self.points.deinit(self.allocator);
    }

    pub fn getPathRecords(self: @This()) []const PathRecord {
        return self.path_records.items;
    }

    pub fn getStyles(self: @This()) []const Style {
        return self.styles.items;
    }

    pub fn getSubpathRecords(self: @This()) []const SubpathRecord {
        return self.subpath_records.items;
    }

    pub fn getCurveRecords(self: @This()) []const CurveRecord {
        return self.curve_records.items;
    }

    pub fn getPoints(self: @This()) []const PointF32 {
        return self.points.items;
    }

    pub fn getCurve(self: @This(), curve_record: CurveRecord) Curve {
        return switch (curve_record.kind) {
            .line => Curve{
                .line = Line.create(
                    self.points.items[curve_record.point_offsets.start],
                    self.points.items[curve_record.point_offsets.start + 1],
                ),
            },
            .quadratic_bezier => Curve{
                .quadratic_bezier = QuadraticBezier.create(
                    self.points.items[curve_record.point_offsets.start],
                    self.points.items[curve_record.point_offsets.start + 1],
                    self.points.items[curve_record.point_offsets.start + 2],
                ),
            },
        };
    }

    pub fn getCubicPoints(self: @This(), curve_record: CurveRecord) CubicPoints {
        var cubic_points = CubicPoints{};

        cubic_points.point0 = self.points.items[curve_record.point_offsets.start];
        cubic_points.point1 = self.points.items[curve_record.point_offsets.start + 1];

        switch (curve_record.kind) {
            .line => {
                cubic_points.point3 = cubic_points.point1;
                cubic_points.point2 = cubic_points.point3.lerp(cubic_points.point0, 1.0 / 3.0);
                cubic_points.point1 = cubic_points.point0.lerp(cubic_points.point3, 1.0 / 3.0);
            },
            .quadratic_bezier => {
                cubic_points.point3 = cubic_points.point2;
                cubic_points.point2 = cubic_points.point1.lerp(cubic_points.point2, 1.0 / 3.0);
                cubic_points.point1 = cubic_points.point1.lerp(cubic_points.point0, 1.0 / 3.0);
            },
        }
    }

    pub fn currentPathRecord(self: *@This()) ?*PathRecord {
        if (self.path_records.items.len > 0) {
            return self.currentPathRecordUnsafe();
        }

        return null;
    }

    pub fn currentPathRecordUnsafe(self: *@This()) *PathRecord {
        return &self.path_records.items[self.path_records.items.len - 1];
    }

    pub fn pushPathRecord(self: *@This()) !void {
        self.closePath();
        const path = try self.path_records.addOne(self.allocator);
        path.curve_offsets = RangeU32{
            .start = @intCast(self.curve_records.items.len),
            .end = @intCast(self.curve_records.items.len),
        };
    }

    pub fn closePath(self: *@This()) void {
        self.closeSubpath();
        if (self.currentPathRecord()) |path| {
            if (path.subpath_offsets.size() == 0) {
                // empty path, remove it from list
                self.path_records.items.len -= 1;
                return;
            }

            path.is_closed = true;
            path.subpath_offsets.end = @intCast(self.subpath_records.items.len);
        }
    }

    pub fn currentSubpathRecord(self: *@This()) ?*SubpathRecord {
        if (self.subpath_records.items.len > 0) {
            return self.currentSubpathRecordUnsafe();
        }

        return null;
    }

    pub fn currentSubpathRecordUnsafe(self: *@This()) *SubpathRecord {
        return &self.subpath_records.items[self.subpath_records.items.len - 1];
    }

    pub fn pushSubpathRecord(self: *@This()) !void {
        self.closeSubpath();
        const subpath = try self.subpath_records.addOne(self.allocator);
        subpath.curve_offsets = RangeU32{
            .start = @intCast(self.curve_records.items.len),
            .end = @intCast(self.curve_records.items.len),
        };
    }

    pub fn closeSubpath(self: *@This()) !void {
        if (self.currentSubpathRecord()) |subpath| {
            if (subpath.curve_offsets.size() == 0) {
                // empty subpath, remove it from list
                self.subpath_records.items.len -= 1;
                return;
            }

            const start_curve = self.curve_records.items[subpath.curve_offsets.start];
            var end_curve = &self.curve_records.items[subpath.curve_offsets.start - 1];
            const start_point = self.points.items[start_curve.curve_offsets.start];
            const end_point = self.points.items[end_curve.curve_offsets.end];

            if (start_point != end_point) {
                // we need to close the subpath
                try self.lineTo(start_point);
                end_curve = &self.curve_records.items[self.curve_records.items.len - 1];
                end_curve.is_open = true;
            }

            end_curve.is_end = true;
            subpath.curve_offsets.end = @intCast(self.curve_records.items.len);
        }
    }

    fn addCurveRecord(self: *@This()) !*CurveRecord {
        return try self.curve_records.addOne(self.allocator);
    }

    fn addPoint(self: *@This()) !*PointF32 {
        return try self.points.addOne(self.allocator);
    }

    fn addPoints(self: *@This(), n: usize) ![]PointF32 {
        return try self.points.addManyAsSlice(self.allocator, n);
    }

    pub fn transform(self: *@This(), t: TransformF32) void {
        for (self.points.items) |*point| {
            point.* = t.apply(point.*);
        }
    }

    pub fn lineTo(self: *@This(), point: PointF32) !void {
        const point_offsets = RangeU32{
            .start = @intCast(self.points.items.len - 1),
            .end = @intCast(self.points.items.len + 1),
        };

        (try self.addPoint()).* = point;
        const curve = try self.addCurveRecord();
        curve.* = CurveRecord{
            .kind = .line,
            .point_offsets = point_offsets,
        };
    }

    pub fn quadTo(self: *@This(), control: PointF32, point: PointF32) !void {
        const point_offsets = RangeU32{
            .start = @intCast(self.points.items.len - 1),
            .end = @intCast(self.points.items.len + 2),
        };

        const points = try self.addPoints(2);
        points[0] = control;
        points[1] = point;
        const curve = try self.addCurveRecord();
        curve.* = CurveRecord{
            .kind = .quadratic_bezier,
            .point_offsets = point_offsets,
        };
    }
};

// pub const PathBuilder = struct {
//     const GlyphPenVTable: *const GlyphPen.VTable = &.{
//         .moveTo = GlyphPenFunctions.moveTo,
//         .lineTo = GlyphPenFunctions.lineTo,
//         .quadTo = GlyphPenFunctions.quadTo,
//         .curveTo = GlyphPenFunctions.curveTo,
//         .close = GlyphPenFunctions.close,
//         .transform = GlyphPenFunctions.transform,
//     };

//     path: *Path,
//     start: ?PointF32 = null,
//     location: PointF32 = PointF32{},
//     is_error: bool = false,

//     pub fn create(path: *Path) @This() {
//         return @This(){
//             .path = path,
//         };
//     }

//     pub fn glyphPen(self: *@This()) GlyphPen {
//         return GlyphPen{
//             .ptr = @ptrCast(self),
//             .vtable = GlyphPenVTable,
//         };
//     }

//     pub fn moveTo(self: *@This(), point: PointF32) !void {
//         self.start = null;
//         self.location = point;
//     }

//     pub fn lineTo(self: *@This(), point: PointF32) !void {
//         if (self.start == null) {
//             // start of a new subpath
//             try self.path.pushSubpathRecord();
//             (try self.path.addPoint()).* = self.location;
//             self.start = self.location;
//         }

//         try self.path.lineTo(point);
//         self.location = point;
//     }

//     pub fn quadTo(self: *@This(), control: PointF32, point: PointF32) !void {
//         if (self.start == null) {
//             // start of a new subpath
//             try self.path.pushSubpathRecord();
//             (try self.path.addPoint()).* = self.location;
//             self.start = self.location;
//         }

//         try self.path.quadTo(control, point);
//         self.location = point;
//     }

//     pub fn close(self: *@This()) !void {
//         if (self.start) |start| {
//             if (!std.meta.eql(start, self.location)) {
//                 try self.lineTo(start);
//             }
//         }

//         self.path.close();
//         self.start = null;
//     }

//     pub const GlyphPenFunctions = struct {
//         fn moveTo(ctx: *anyopaque, point: PointF32) void {
//             var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
//             b.moveTo(point) catch {
//                 b.is_error = true;
//             };
//         }

//         fn lineTo(ctx: *anyopaque, point: PointF32) void {
//             var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
//             b.lineTo(point) catch {
//                 b.is_error = true;
//             };
//         }

//         fn quadTo(ctx: *anyopaque, control: PointF32, point: PointF32) void {
//             var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
//             b.quadTo(control, point) catch {
//                 b.is_error = true;
//             };
//         }

//         fn curveTo(_: *anyopaque, _: PointF32, _: PointF32, _: PointF32) void {
//             @panic("PathBuilder does not support curveTo\n");
//         }

//         fn close(ctx: *anyopaque) void {
//             var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
//             b.close() catch {
//                 b.is_error = true;
//             };
//         }

//         fn transform(ctx: *anyopaque, t: TransformF32) void {
//             const b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
//             b.path.transform(t);
//         }
//     };
// };
