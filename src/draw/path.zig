const std = @import("std");
const text = @import("../text/root.zig");
const core = @import("../core/root.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const soup_pen = @import("./soup_pen.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const TransformF32 = core.TransformF32;
const SequenceU32 = core.SequenceU32;
const GlyphPen = text.GlyphPen;
const Line = curve_module.Line;
const QuadraticBezier = curve_module.QuadraticBezier;
const CubicPoints = euler.CubicPoints;
const Style = soup_pen.Style;

pub const PathMetadata = struct {
    style_index: u16,
    transform_index: u16,
    path_offsets: RangeU32 = RangeU32{},
};

pub const Path = struct {
    subpath_offsets: RangeU32,
    bounds: RectF32 = RectF32{},
    is_closed: bool = false,
};

pub const Subpath = struct {
    curve_offsets: RangeU32,
    is_closed: bool = false,
};

pub const Curve = struct {
    pub const Cap = enum(u8) {
        none = 0,
        start = 1,
        end = 2,
    };

    pub const Kind = enum(u8) {
        line = 0,
        quadratic_bezier = 1,
    };

    kind: Kind,
    point_offsets: RangeU32,
    is_end: bool = false,
    is_open: bool = false,
    cap: Cap = .none,

    pub fn isCapped(self: @This()) bool {
        return self.cap != .none;
    }
};

pub const Paths = struct {
    const PathList = std.ArrayListUnmanaged(Path);
    const SubpathList = std.ArrayListUnmanaged(Subpath);
    const CurveList = std.ArrayListUnmanaged(Curve);
    const PointList = std.ArrayListUnmanaged(PointF32);

    allocator: Allocator,
    paths: PathList = PathList{},
    subpaths: SubpathList = SubpathList{},
    curves: CurveList = CurveList{},
    points: PointList = PointList{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.paths.deinit(self.allocator);
        self.subpaths.deinit(self.allocator);
        self.curves.deinit(self.allocator);
        self.points.deinit(self.allocator);
    }

    pub fn currentPath(self: *@This()) ?*Path {
        if (self.paths.items.len > 0) {
            return self.currentPathUnsafe();
        }

        return null;
    }

    pub fn currentPathUnsafe(self: *@This()) *Path {
        return &self.paths.items[self.paths.items.len - 1];
    }

    pub fn openPath(self: *@This()) !void {
        try self.closePath();
        const path = try self.paths.addOne(self.allocator);
        path.* = Path{
            .subpath_offsets = RangeU32{
                .start = @intCast(self.subpaths.items.len),
                .end = @intCast(self.subpaths.items.len),
            },
        };
    }

    pub fn closePath(self: *@This()) !void {
        try self.closeSubpath();
        if (self.currentPath()) |path| {
            path.subpath_offsets.end = @intCast(self.subpaths.items.len);
            if (path.is_closed) {
                return;
            }
            if (path.subpath_offsets.size() == 0) {
                // empty path, remove it from list
                self.paths.items.len -= 1;
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

            for (self.subpaths.items[path.subpath_offsets.start..path.subpath_offsets.end]) |subpath| {
                const start_point_index = self.curves.items[subpath.curve_offsets.start].point_offsets.start;
                const end_point_index = self.curves.items[subpath.curve_offsets.end - 1].point_offsets.end;

                for (self.points.items[start_point_index..end_point_index]) |point| {
                    bounds = bounds.extendBy(point);
                }
            }

            path.bounds = bounds;
            path.is_closed = true;
        }
    }

    pub fn copyPath(self: *@This(), paths: Paths, path_index: u32) !void {
        const path = paths.paths.items[path_index];
        try self.openPath();

        const start_curve_index = paths.subpaths.items[path.subpath_offsets.start].curve_offsets.start;
        const end_curve_index = paths.subpaths.items[path.subpath_offsets.end - 1].curve_offsets.end;
        const start_point_index = paths.curves.items[start_curve_index].point_offsets.start;
        const end_point_index = paths.curves.items[end_curve_index - 1].point_offsets.end;

        const self_start_point_index: u32 = @intCast(self.points.items.len);
        const points = try self.addPoints(end_point_index - start_point_index);
        std.mem.copyForwards(PointF32, points, paths.points.items[start_point_index..end_point_index]);

        const self_start_curve_index: u32 = @intCast(self.curves.items.len);
        const curves = try self.addCurveRecords(end_curve_index - start_curve_index);
        for (curves, paths.curves.items[start_curve_index..end_curve_index]) |*self_curve, curve| {
            self_curve.* = curve;
            self_curve.point_offsets = RangeU32{
                .start = curve.point_offsets.start - start_point_index + self_start_point_index,
                .end = curve.point_offsets.end - start_point_index + self_start_point_index,
            };
        }

        const subpaths = try self.addSubpathRecords(path.subpath_offsets.size());
        for (subpaths, paths.subpaths.items[path.subpath_offsets.start..path.subpath_offsets.end]) |*self_subpath, subpath| {
            self_subpath.* = subpath;
            self_subpath.curve_offsets = RangeU32{
                .start = subpath.curve_offsets.start - start_curve_index + self_start_curve_index,
                .end = subpath.curve_offsets.end - start_curve_index + self_start_curve_index,
            };
        }

        try self.closePath();
    }

    pub fn currentSubpathRecord(self: *@This()) ?*Subpath {
        if (self.subpaths.items.len > 0) {
            return self.currentSubpathRecordUnsafe();
        }

        return null;
    }

    pub fn currentSubpathRecordUnsafe(self: *@This()) *Subpath {
        return &self.subpaths.items[self.subpaths.items.len - 1];
    }

    pub fn openSubpath(self: *@This()) !void {
        try self.closeSubpath();
        const subpath = try self.subpaths.addOne(self.allocator);
        subpath.* = Subpath{
            .curve_offsets = RangeU32{
                .start = @intCast(self.curves.items.len),
                .end = @intCast(self.curves.items.len),
            },
        };
    }

    pub fn closeSubpath(self: *@This()) !void {
        if (self.currentSubpathRecord()) |subpath| {
            subpath.curve_offsets.end = @intCast(self.curves.items.len);
            if (subpath.is_closed) {
                return;
            }
            if (subpath.curve_offsets.size() == 0) {
                // empty subpath, remove it from list
                self.subpaths.items.len -= 1;
                return;
            }

            const start_curve = &self.curves.items[subpath.curve_offsets.start];
            var end_curve = &self.curves.items[self.curves.items.len - 1];
            const start_point = self.points.items[start_curve.point_offsets.start];
            const end_point = self.points.items[end_curve.point_offsets.end - 1];

            if (!std.meta.eql(start_point, end_point)) {
                // we need to close the subpath
                try self.lineTo(start_point);
                end_curve = &self.curves.items[self.curves.items.len - 1];
                end_curve.is_open = true;
                end_curve.cap = .end;
                start_curve.cap = .start;
            }

            end_curve.is_end = true;
            subpath.is_closed = true;
        }
    }

    fn addSubpathRecords(self: *@This(), n: usize) ![]Subpath {
        return try self.subpaths.addManyAsSlice(self.allocator, n);
    }

    pub fn isSubpathCapped(self: @This(), subpath: Subpath) bool {
        const first_curve = self.curves.items[subpath.curve_offsets.start];
        return first_curve.isCapped();
    }

    pub fn getCubicPoints(self: @This(), curve: Curve) CubicPoints {
        var cubic_points = CubicPoints{};

        cubic_points.point0 = self.points.items[curve.point_offsets.start];
        cubic_points.point1 = self.points.items[curve.point_offsets.start + 1];

        switch (curve.kind) {
            .line => {
                cubic_points.point3 = cubic_points.point1;
                cubic_points.point2 = cubic_points.point3.lerp(cubic_points.point0, 1.0 / 3.0);
                cubic_points.point1 = cubic_points.point0.lerp(cubic_points.point3, 1.0 / 3.0);
            },
            .quadratic_bezier => {
                cubic_points.point2 = self.points.items[curve.point_offsets.start + 2];
                cubic_points.point3 = cubic_points.point2;
                cubic_points.point2 = cubic_points.point1.lerp(cubic_points.point2, 1.0 / 3.0);
                cubic_points.point1 = cubic_points.point1.lerp(cubic_points.point0, 1.0 / 3.0);
            },
        }

        return cubic_points;
    }

    fn addCurveRecord(self: *@This(), kind: Curve.Kind) !*Curve {
        const curve = try self.curves.addOne(self.allocator);
        curve.* = Curve{
            .kind = kind,
            .point_offsets = RangeU32{
                .start = @intCast(self.points.items.len),
                .end = @intCast(self.points.items.len),
            },
        };
        return curve;
    }

    fn addCurveRecords(self: *@This(), n: usize) ![]Curve {
        return try self.curves.addManyAsSlice(self.allocator, n);
    }

    fn addPoint(self: *@This()) !*PointF32 {
        return try self.points.addOne(self.allocator);
    }

    fn addPoints(self: *@This(), n: usize) ![]PointF32 {
        return try self.points.addManyAsSlice(self.allocator, n);
    }

    pub fn transformCurrentPath(self: *@This(), t: TransformF32) void {
        if (self.currentPath()) |path| {
            const start_curve_index = self.subpaths.items[path.subpath_offsets.start].curve_offsets.start;
            const start_point_index = self.curves.items[start_curve_index].point_offsets.start;
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
