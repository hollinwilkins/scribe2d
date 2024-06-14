const std = @import("std");
const text = @import("../text/root.zig");
const core = @import("../core/root.zig");
const curve_module = @import("./curve2.zig");
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

pub const SubpathRecord = extern struct {
    curve_offsets: RangeU32,
};

pub const CurveRecord = extern struct {
    pub const Kind = enum(u8) {
        line = 0,
        quadratic_bezier = 1,
    };

    kind: Kind,
    point_offsets: RangeU32,
};

pub const PathUnmanaged = struct {
    const SubpathList = std.ArrayListUnmanaged(SubpathRecord);
    const CurveList = std.ArrayListUnmanaged(CurveRecord);
    const PointList = std.ArrayListUnmanaged(PointF32);

    subpath_records: SubpathList = SubpathList{},
    curve_records: CurveList = CurveList{},
    points: PointList = PointList{},

    pub fn deinit(self: @This(), allocator: Allocator) void {
        self.subpath_records.deinit(allocator);
        self.curve_records.deinit(allocator);
        self.points.deinit(allocator);
    }
};

pub const Path = struct {
    const SubpathRecordList = std.ArrayListUnmanaged(SubpathRecord);
    const CurveRecordList = std.ArrayListUnmanaged(CurveRecord);
    const PointList = std.ArrayListUnmanaged(PointF32);

    allocator: Allocator,
    subpath_records: SubpathRecordList = SubpathRecordList{},
    curve_records: CurveRecordList = CurveRecordList{},
    points: PointList = PointList{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Path) void {
        self.toUnmanaged().deinit(self.allocator);
    }

    pub fn toUnmanaged(self: Path) PathUnmanaged {
        return PathUnmanaged{
            .subpath_records = self.subpath_records,
            .curve_records = self.curve_records,
            .points = self.points,
        };
    }

    pub fn getSubpathRecords(self: @This()) []SubpathRecord {
        return self.subpath_records.items;
    }

    pub fn getCurveRecords(self: @This()) []CurveRecord {
        return self.curve_records.items;
    }

    pub fn getPoints(self: @This()) []PointF32 {
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
        if (self.currentSubpathRecord()) |subpath| {
            subpath.curve_offsets.end = self.curve_records.items.len;
        }

        const subpath = try self.subpath_records.addOne(self.allocator);
        subpath.curve_offsets = RangeU32{
            .start = self.curve_records.items.len,
            .end = self.curve_records.items.len,
        };
    }

    fn addCurveRecord(self: *@This()) !*CurveRecord {
        return try self.curve_records.addOne(self.allocator);
    }

    pub fn addPoint(self: *@This()) *PointF32 {
        return try self.points.addOne(self.allocator);
    }

    pub fn addPoints(self: *@This(), n: usize) []PointF32 {
        return try self.points.addManyAsSlice(self.allocator, n);
    }

    pub fn transform(self: *@This(), t: TransformF32) !void {
        for (self.points.items) |*point| {
            point.* = t.apply(point.*);
        }
    }

    pub fn lineTo(self: *@This(), point: PointF32) !void {
        const point_offsets = RangeU32{
            .start = self.points.items.len,
            .end = self.points.items.len + 1,
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
            .start = self.points.items.len,
            .end = self.points.items.len + 2,
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
        .close = GlyphPenFunctions.close,
        .transform = GlyphPenFunctions.transform,
    };

    path: Path,
    start: ?PointF32 = null,
    location: ?PointF32 = null,
    is_error: bool = false,

    pub fn create(path: Path) @This() {
        return @This(){
            .path = path,
        };
    }

    pub fn glyphPen(self: *@This()) GlyphPen {
        return GlyphPen{
            .ptr = @ptrCast(self),
            .vtable = GlyphPenVTable,
        };
    }

    pub fn moveTo(self: *@This(), point: PointF32) !void {
        self.start = null;
        self.location = point;
    }

    pub fn lineTo(self: *@This(), point: PointF32) !void {
        if (self.start == null) {
            // start of a new subpath
            try self.path.pushSubpathRecord();
            (try self.path.addPoint()).* = self.location;
            self.start = self.location;
        }

        try self.path.lineTo(point);
        self.location = point;
    }

    pub fn quadTo(self: *@This(), control: PointF32, point: PointF32) !void {
        if (self.start == null) {
            // start of a new subpath
            try self.path.pushSubpathRecord();
            (try self.path.addPoint()).* = self.location;
            self.start = self.location;
        }

        try self.path.quadTo(control, point);
        self.location = point;
    }

    pub fn close(self: *@This()) !void {
        if (self.start != self.location) {
            try self.lineTo(self.start);
        }

        self.start = null;
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

        fn close(ctx: *anyopaque) void {
            var b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            b.close() catch {
                b.is_error = true;
            };
        }

        fn transform(ctx: *anyopaque, t: TransformF32) void {
            const b = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            b.path.transform(t);
        }
    };
};
