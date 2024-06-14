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

pub const Paths = struct {
    pub const PathRecord = struct {
        subpath_offsets: RangeU32,
        bounds: RectF32 = RectF32{},
        is_closed: bool = false,
    };

    pub const SubpathRecord = struct {
        curve_offsets: RangeU32,
        is_closed: bool = false,
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
    const SubpathRecordList = std.ArrayListUnmanaged(SubpathRecord);
    const CurveRecordList = std.ArrayListUnmanaged(CurveRecord);
    const PointList = std.ArrayListUnmanaged(PointF32);

    allocator: Allocator,
    path_records: PathRecordList = PathRecordList{},
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
        self.subpath_records.deinit(self.allocator);
        self.curve_records.deinit(self.allocator);
        self.points.deinit(self.allocator);
    }

    pub fn getPathRecords(self: @This()) []const PathRecord {
        return self.path_records.items;
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

    pub fn openPath(self: *@This()) !void {
        try self.closePath();
        const path = try self.path_records.addOne(self.allocator);
        path.subpath_offsets = RangeU32{
            .start = @intCast(self.subpath_records.items.len),
            .end = @intCast(self.subpath_records.items.len),
        };
    }

    pub fn closePath(self: *@This()) !void {
        try self.closeSubpath();
        if (self.currentPathRecord()) |path| {
            if (path.is_closed or path.subpath_offsets.size() == 0) {
                // empty path, remove it from list
                self.path_records.items.len -= 1;
                return;
            }

            var bounds = RectF32{
                .min = PointF32{
                    .x = std.math.floatMax(f32),
                    .y = std.math.floatMax(f32),
                },
                .max = PointF32{
                    .x = std.math.floatMin(f32),
                    .y = std.math.floatMin(f32),
                },
            };

            for (self.subpath_records.items[path.subpath_offsets.start..path.subpath_offsets.end]) |subpath| {
                const start_point_index = self.curve_records.items[subpath.curve_offsets.start].point_offsets.start;
                const end_point_index = self.curve_records.items[subpath.curve_offsets.end - 1].point_offsets.end;

                for (self.points.items[start_point_index..end_point_index]) |point| {
                    bounds = bounds.extendBy(point);
                }
            }

            path.bounds = bounds;
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

    pub fn openSubpath(self: *@This()) !void {
        try self.closeSubpath();
        const subpath = try self.subpath_records.addOne(self.allocator);
        subpath.curve_offsets = RangeU32{
            .start = @intCast(self.curve_records.items.len),
            .end = @intCast(self.curve_records.items.len),
        };
    }

    pub fn closeSubpath(self: *@This()) !void {
        if (self.currentSubpathRecord()) |subpath| {
            if (subpath.is_closed or subpath.curve_offsets.size() == 0) {
                // empty subpath, remove it from list
                self.subpath_records.items.len -= 1;
                return;
            }

            const start_curve = self.curve_records.items[subpath.curve_offsets.start];
            var end_curve = &self.curve_records.items[subpath.curve_offsets.start - 1];
            const start_point = self.points.items[start_curve.point_offsets.start];
            const end_point = self.points.items[end_curve.point_offsets.end];

            if (std.meta.eql(start_point, end_point)) {
                // we need to close the subpath
                try self.lineTo(start_point);
                end_curve = &self.curve_records.items[self.curve_records.items.len - 1];
                end_curve.is_open = true;
            }

            end_curve.is_end = true;
            subpath.is_closed = true;
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

    pub fn transformCurrentPath(self: *@This(), t: TransformF32) void {
        if (self.currentPathRecord()) |path| {
            if (path.subpath_offsets.size() > 0) {
                const start_curve_index = self.subpath_records.items[path.subpath_offsets.start].curve_offsets.start;
                const end_curve_index = self.subpath_records.items[path.subpath_offsets.end - 1].curve_offsets.end;
                const start_point_index = self.curve_records.items[start_curve_index].point_offsets.start;
                const end_point_index = self.curve_records.items[end_curve_index].point_offsets.end;

                for (self.points.items[start_point_index..end_point_index]) |*point| {
                    point.* = t.apply(point.*);
                }
            }
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

pub const PathBuilder = struct {
    const GlyphPenVTable: *const GlyphPen.VTable = &.{
        .moveTo = GlyphPenFunctions.moveTo,
        .lineTo = GlyphPenFunctions.lineTo,
        .quadTo = GlyphPenFunctions.quadTo,
        .curveTo = GlyphPenFunctions.curveTo,
        .open = GlyphPenFunctions.open,
        .close = GlyphPenFunctions.close,
        .transform = GlyphPenFunctions.transform,
    };

    paths: *Paths,
    location: PointF32 = PointF32{},
    is_error: bool = false,

    pub fn create(paths: *Paths) @This() {
        return @This(){
            .paths = paths,
        };
    }

    pub fn glyphPen(self: *@This()) GlyphPen {
        return GlyphPen{
            .ptr = @ptrCast(self),
            .vtable = GlyphPenVTable,
        };
    }

    pub fn moveTo(self: *@This(), point: PointF32) !void {
        try self.paths.closeSubpath();
        self.location = point;
    }

    pub fn lineTo(self: *@This(), point: PointF32) !void {
        if (self.paths.currentSubpathRecord()) |subpath| {
            if (subpath.curve_offsets.size() == 0) {
                (try self.paths.addPoint()).* = self.location;
            }
        } else {
            try self.paths.openSubpath();
            (try self.paths.addPoint()).* = self.location;
        }

        try self.paths.lineTo(point);
        self.location = point;
    }

    pub fn quadTo(self: *@This(), control: PointF32, point: PointF32) !void {
        if (self.paths.currentSubpathRecord()) |subpath| {
            if (subpath.curve_offsets.size() == 0) {
                (try self.paths.addPoint()).* = self.location;
            }
        } else {
            try self.paths.openSubpath();
            (try self.paths.addPoint()).* = self.location;
        }

        try self.paths.quadTo(control, point);
        self.location = point;
    }

    pub fn open(self: *@This()) !void {
        try self.paths.openPath();
    }

    pub fn close(self: *@This()) !void {
        try self.paths.closePath();
    }

    pub const GlyphPenFunctions = struct {
        fn moveTo(ctx: *anyopaque, point: PointF32) void {
            var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            b.moveTo(point) catch {
                b.is_error = true;
            };
        }

        fn lineTo(ctx: *anyopaque, point: PointF32) void {
            var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            b.lineTo(point) catch {
                b.is_error = true;
            };
        }

        fn quadTo(ctx: *anyopaque, control: PointF32, point: PointF32) void {
            var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            b.quadTo(control, point) catch {
                b.is_error = true;
            };
        }

        fn curveTo(_: *anyopaque, _: PointF32, _: PointF32, _: PointF32) void {
            @panic("PathBuilder does not support curveTo\n");
        }

        fn open(ctx: *anyopaque) void {
            var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            b.open() catch {
                b.is_error = true;
            };
        }

        fn close(ctx: *anyopaque) void {
            var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            b.close() catch {
                b.is_error = true;
            };
        }

        fn transform(ctx: *anyopaque, t: TransformF32) void {
            const b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            b.paths.transformCurrentPath(t);
        }
    };
};
