const std = @import("std");
const text = @import("../text/root.zig");
const core = @import("../core/root.zig");
const curve_module = @import("./curve.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const TransformF32 = core.TransformF32;
const SequenceU32 = core.SequenceU32;
const GlyphPen = text.GlyphPen;

pub const Subpath = extern struct {
    curve_offsets: RangeU32,
};

pub const Curve = extern struct {
    pub const Kind = enum(u8) {
        line = 0,
        quadratic_bezier = 1,
    };

    kind: Kind,
    point_offsets: RangeU32,
};

pub const PathUnmanaged = struct {
    const SubpathList = std.ArrayListUnmanaged(Subpath);
    const CurveList = std.ArrayListUnmanaged(Curve);
    const PointList = std.ArrayListUnmanaged(PointF32);

    subpaths: SubpathList = SubpathList{},
    curves: CurveList = CurveList{},
    points: PointList = PointList{},

    pub fn deinit(self: @This(), allocator: Allocator) void {
        self.subpaths.deinit(allocator);
        self.curve.deinit(allocator);
        self.points.deinit(allocator);
    }
};

pub const Path = struct {
    const SubpathList = std.ArrayListUnmanaged(Subpath);
    const CurveList = std.ArrayListUnmanaged(Curve);
    const PointList = std.ArrayListUnmanaged(PointF32);

    allocator: Allocator,
    subpaths: SubpathList = SubpathList{},
    curves: CurveList = CurveList{},
    points: PointList = PointList{},

    pub fn init(allocator: Allocator) @This() {
        return @This() {
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Path) void {
        self.toUnmanaged().deinit(self.allocator);
    }

    pub fn getSubpaths(self: @This()) []Subpath {
        return self.subpaths.items;
    }

    pub fn getCurves(self: @This()) []Curve {
        return self.curves.items;
    }

    pub fn getPoints(self: @This()) []PointF32 {
        return self.points.items;
    }

    pub fn currentSubpath(self: *@This()) ?*Subpath {
        if (self.subpaths.items.len > 0) {
            return self.currentSubpathUnsafe();
        }

        return null;
    }

    pub fn currentSubpathUnsafe(self: *@This()) *Subpath {
        return &self.subpaths.items[self.subpaths.items.len - 1];
    }

    pub fn pushSubpath(self: *@This()) !void {
        if (self.currentSubpath()) |subpath| {
            subpath.curve_offsets.end = self.curves.items.len;
        }

        const subpath = try self.subpaths.addOne(self.allocator);
        subpath.curve_offsets = RangeU32{
            .start = self.curves.items.len,
            .end = self.curves.items.len,
        };
    }

    fn addCurve(self: *@This()) !*Curve {
        return try self.curves.addOne(self.allocator);
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
        const curve = try self.addCurve();
        curve.* = Curve{
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
        const curve = try self.addCurve();
        curve.* = Curve{
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
            try self.path.pushSubpath();
            (try self.path.addPoint()).* = self.location;
            self.start = self.location;
        }

        try self.path.lineTo(point);
        self.location = point;
    }

    pub fn quadTo(self: *@This(), control: PointF32, point: PointF32) !void {
        if (self.start == null) {
            // start of a new subpath
            try self.path.pushSubpath();
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
