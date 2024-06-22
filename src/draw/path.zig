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

pub const PathMetadata = struct {
    style_index: u16,
    transform_index: u16,
    path_offsets: RangeU32 = RangeU32{},
};

pub const PathsUnmanaged = struct {
    path_records: Paths.PathRecordList = Paths.PathRecordList{},
    subpath_records: Paths.SubpathRecordList = Paths.SubpathRecordList{},
    curve_records: Paths.CurveRecordList = Paths.CurveRecordList{},
    points: Paths.PointList = Paths.PointList{},

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        var managed = self.toManaged(allocator);
        managed.deinit();
    }

    pub fn toManaged(self: @This(), allocator: Allocator) Paths {
        return Paths{
            .allocator = allocator,
            .path_records = self.path_records,
            .subpath_records = self.subpath_records,
            .curve_records = self.curve_records,
            .points = self.points,
        };
    }

    pub fn getPathRecord(self: @This(), index: u32) ?Paths.PathRecord {
        if (index < self.path_records.items.len) {
            return self.path_records.items[index];
        }

        return null;
    }

    pub fn getCurveRecord(self: @This(), index: u32) Paths.CurveRecord {
        return self.curve_records.items[index];
    }

    pub fn getCubicPoints(self: @This(), curve_record: Paths.CurveRecord) CubicPoints {
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
};

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
        is_cap: bool = false,
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

    pub fn toUnmanaged(self: @This()) PathsUnmanaged {
        return PathsUnmanaged{
            .path_records = self.path_records,
            .subpath_records = self.subpath_records,
            .curve_records = self.curve_records,
            .points = self.points,
        };
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
        path.* = PathRecord{
            .subpath_offsets = RangeU32{
                .start = @intCast(self.subpath_records.items.len),
                .end = @intCast(self.subpath_records.items.len),
            },
        };
    }

    pub fn closePath(self: *@This()) !void {
        try self.closeSubpath();
        if (self.currentPathRecord()) |path| {
            path.subpath_offsets.end = @intCast(self.subpath_records.items.len);
            if (path.is_closed) {
                return;
            }
            if (path.subpath_offsets.size() == 0) {
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
        }
    }

    pub fn copyPath(self: *@This(), paths: PathsUnmanaged, path_index: u32) !void {
        if (paths.getPathRecord(path_index)) |path| {
            try self.openPath();

            const start_curve_index = paths.subpath_records.items[path.subpath_offsets.start].curve_offsets.start;
            const end_curve_index = paths.subpath_records.items[path.subpath_offsets.end].curve_offsets.end;
            const start_point_index = paths.curve_records.items[start_curve_index].point_offsets.start;
            const end_point_index = paths.curve_records.items[end_curve_index].point_offsets.end;

            const self_start_point_index: u32 = @intCast(self.points.items.len);
            const points = try self.addPoints(end_point_index - start_point_index);
            std.mem.copyForwards(PointF32, points, paths.points[start_point_index..end_point_index]);

            const self_start_curve_index: u32 = @intCast(self.curve_records.items.len);
            const curve_records = try self.addCurveRecords(end_curve_index - start_curve_index);
            for (curve_records, paths.curve_records.items[start_curve_index..end_curve_index]) |*self_curve, curve| {
                self_curve.* = curve;
                self_curve.point_offsets = RangeU32{
                    .start = curve.point_offsets.start - start_point_index + self_start_point_index,
                    .end = curve.point_offsets.end - start_point_index + self_start_point_index,
                };
            }

            const subpath_records = try self.addSubpathRecords(path.subpath_offsets.size());
            for (subpath_records, paths.subpath_records.items[path.subpath_offsets.start..path.subpath_offsets.end]) |*self_subpath, subpath| {
                self_subpath.* = subpath;
                self_subpath.curve_offsets = RangeU32{
                    .start = subpath.curve_offsets.start - start_curve_index + self_start_curve_index,
                    .end = subpath.curve_offsets.end - start_curve_index + self_start_curve_index,
                };
            }

            try self.closePath();
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
        subpath.* = SubpathRecord{
            .curve_offsets = RangeU32{
                .start = @intCast(self.curve_records.items.len),
                .end = @intCast(self.curve_records.items.len),
            },
        };
    }

    pub fn closeSubpath(self: *@This()) !void {
        if (self.currentSubpathRecord()) |subpath| {
            subpath.curve_offsets.end = @intCast(self.curve_records.items.len);
            if (subpath.is_closed) {
                return;
            }
            if (subpath.curve_offsets.size() == 0) {
                // empty subpath, remove it from list
                self.subpath_records.items.len -= 1;
                return;
            }

            const start_curve = &self.curve_records.items[subpath.curve_offsets.start];
            var end_curve = &self.curve_records.items[self.curve_records.items.len - 1];
            const start_point = self.points.items[start_curve.point_offsets.start];
            const end_point = self.points.items[end_curve.point_offsets.end - 1];

            if (std.meta.eql(start_point, end_point)) {
                // we need to close the subpath
                try self.lineTo(start_point);
                end_curve = &self.curve_records.items[self.curve_records.items.len - 1];
                end_curve.is_open = true;
                end_curve.is_cap = true;
                start_curve.is_cap = true;
            }

            end_curve.is_end = true;
            subpath.is_closed = true;
        }
    }

    fn addSubpathRecords(self: *@This(), n: usize) ![]SubpathRecord {
        return try self.subpath_records.addManyAsSlice(self.allocator, n);
    }

    fn addCurveRecord(self: *@This(), kind: CurveRecord.Kind) !*CurveRecord {
        const curve = try self.curve_records.addOne(self.allocator);
        curve.* = CurveRecord{
            .kind = kind,
            .point_offsets = RangeU32{
                .start = @intCast(self.points.items.len),
                .end = @intCast(self.points.items.len),
            },
        };
        return curve;
    }

    fn addCurveRecords(self: *@This(), n: usize) ![]CurveRecord {
        return try self.curve_records.addManyAsSlice(self.allocator, n);
    }

    fn addPoint(self: *@This()) !*PointF32 {
        return try self.points.addOne(self.allocator);
    }

    fn addPoints(self: *@This(), n: usize) ![]PointF32 {
        return try self.points.addManyAsSlice(self.allocator, n);
    }

    pub fn transformCurrentPath(self: *@This(), t: TransformF32) void {
        if (self.currentPathRecord()) |path| {
            const start_curve_index = self.subpath_records.items[path.subpath_offsets.start].curve_offsets.start;
            const start_point_index = self.curve_records.items[start_curve_index].point_offsets.start;
            const end_point_index = self.points.items.len;

            for (self.points.items[start_point_index..end_point_index]) |*point| {
                point.* = t.apply(point.*);
            }
        }
    }

    pub fn lineTo(self: *@This(), point: PointF32) !void {
        const point_offsets = RangeU32{
            .start = @intCast(self.points.items.len - 1),
            .end = @intCast(self.points.items.len + 1),
        };

        (try self.addPoint()).* = point;
        const curve = try self.addCurveRecord(.line);
        curve.point_offsets = point_offsets;
    }

    pub fn quadTo(self: *@This(), control: PointF32, point: PointF32) !void {
        const point_offsets = RangeU32{
            .start = @intCast(self.points.items.len - 1),
            .end = @intCast(self.points.items.len + 2),
        };

        const points = try self.addPoints(2);
        points[0] = control;
        points[1] = point;
        const curve = try self.addCurveRecord(.quadratic_bezier);
        curve.point_offsets = point_offsets;
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
    is_subpath_initialized: bool = false,
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
        self.is_subpath_initialized = false;
    }

    pub fn lineTo(self: *@This(), point: PointF32) !void {
        if (!self.is_subpath_initialized) {
            try self.paths.openSubpath();
            (try self.paths.addPoint()).* = self.location;
            self.is_subpath_initialized = true;
        }

        try self.paths.lineTo(point);
        self.location = point;
    }

    pub fn quadTo(self: *@This(), control: PointF32, point: PointF32) !void {
        if (!self.is_subpath_initialized) {
            try self.paths.openSubpath();
            (try self.paths.addPoint()).* = self.location;
            self.is_subpath_initialized = true;
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
