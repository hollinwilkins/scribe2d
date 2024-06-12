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
const Curve = curve_module.Curve;
const CurveFn = curve_module.CurveFn;
const Subpath = curve_module.Subpath;
const Line = curve_module.Line;
const QuadraticBezier = curve_module.QuadraticBezier;
const SequenceU32 = core.SequenceU32;

pub const Path = struct {
    pub const Unmanaged = struct {
        var IdSequence = SequenceU32.initValue(0);

        id: u32,
        subpaths: []const Subpath,
        curves: []const Curve,

        pub fn create(subpaths: []const Subpath, curves: []const Curve) Unmanaged {
            return Unmanaged{
                .id = IdSequence.next(),
                .subpaths = subpaths,
                .curves = curves,
            };
        }

        pub fn deinit(self: Unmanaged, allocator: Allocator) void {
            allocator.free(self.subpaths);
            allocator.free(self.curves);
        }
    };

    allocator: Allocator,
    unmanaged: Unmanaged,

    pub fn deinit(self: Path) void {
        self.unmanaged.deinit(self.allocator);
    }

    pub fn getId(self: Path) u32 {
        return self.unmanaged.id;
    }

    pub fn getSubpaths(self: *const Path) []const Subpath {
        return self.unmanaged.subpaths;
    }

    pub fn getCurves(self: *const Path) []const Curve {
        return self.unmanaged.curves;
    }

    pub fn getCurvesRange(self: *const Path, range: RangeU32) []const Curve {
        return self.unmanaged.curves[range.start..range.end];
    }

    pub fn debug(self: *const Path) void {
        std.debug.print("Path\n", .{});
        for (self.unmanaged.curves) |curve| {
            std.debug.print("\t{}\n", .{curve});
        }
    }
};

pub const PathBuilder = struct {
    const SubpathsList = std.ArrayList(Subpath);
    const CurvesList = std.ArrayList(Curve);

    const GlyphPenFunctions = struct {
        fn moveTo(ctx: *anyopaque, point: PointF32) void {
            var po = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            po.moveTo(point) catch {
                po.is_error = true;
            };
        }

        fn lineTo(ctx: *anyopaque, end: PointF32) void {
            var po = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            po.lineTo(end) catch {
                po.is_error = true;
            };
        }

        fn quadTo(ctx: *anyopaque, end: PointF32, control: PointF32) void {
            var po = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            po.quadTo(end, control) catch {
                po.is_error = true;
            };
        }

        fn curveTo(_: *anyopaque, _: PointF32, _: PointF32, _: PointF32) void {
            @panic("PathOutliner does not support curveTo\n");
        }

        fn close(ctx: *anyopaque) void {
            var po = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            po.close() catch {
                po.is_error = true;
            };
        }

        fn transform(ctx: *anyopaque, t: TransformF32) void {
            const po = @as(*PathBuilder, @alignCast(@ptrCast(ctx)));
            for (po.curves.items) |*curve| {
                curve.* = curve.transform(t);
            }
        }
    };

    pub const GlyphPenVTable = .{
        .moveTo = GlyphPenFunctions.moveTo,
        .lineTo = GlyphPenFunctions.lineTo,
        .quadTo = GlyphPenFunctions.quadTo,
        .curveTo = GlyphPenFunctions.curveTo,
        .close = GlyphPenFunctions.close,
        .transform = GlyphPenFunctions.transform,
    };

    subpaths: SubpathsList,
    curves: CurvesList,
    bounds: RectF32 = RectF32{},
    start: ?PointF32 = null,
    location: PointF32 = PointF32{},
    is_error: bool = false,

    pub fn init(allocator: Allocator) Allocator.Error!@This() {
        return @This(){
            .subpaths = SubpathsList.init(allocator),
            .curves = CurvesList.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.subpaths.deinit();
        self.curves.deinit();
    }

    pub fn glyphPen(self: *@This()) text.GlyphPen {
        return text.GlyphPen{
            .ptr = self,
            .vtable = &GlyphPenVTable,
        };
    }

    pub fn createPathAlloc(self: *@This(), allocator: Allocator) Allocator.Error!Path {
        return Path{
            .allocator = allocator,
            .unmanaged = Path.Unmanaged.create(
                try allocator.dupe(Subpath, self.subpaths.items),
                try allocator.dupe(Curve, self.curves.items),
            ),
        };
    }

    pub fn currentSubpath(self: *@This()) !*Subpath {
        return &self.subpaths.items[self.subpaths.items.len - 1];
    }

    pub fn nextSubpath(self: *@This()) !void {
        const ao = try self.subpaths.addOne();
        ao.* = Subpath{
            .curve_offsets = RangeU32{
                .start = @intCast(self.curves.items.len),
                .end = @intCast(self.curves.items.len),
            },
        };
    }

    pub fn moveTo(self: *@This(), point: PointF32) !void {
        self.start = null;

        if (self.curves.items.len > 0) {
            self.curves.items[self.curves.items.len - 1].end_curve = true;
        }
        // set current location to point
        self.location = point;
    }

    pub fn lineTo(self: *@This(), point: PointF32) !void {
        if (self.start == null) {
            self.start = self.location;
            try self.nextSubpath();
        }

        // attempt to add a line curve from current location to point
        const ao = try self.curves.addOne();
        ao.* = Curve{
            .end_curve = false,
            .curve_fn = CurveFn{
                .line = Line{
                    .start = self.location,
                    .end = point,
                },
            },
        };

        (try self.currentSubpath()).curve_offsets.end += 1;
        self.location = point;
    }

    pub fn quadTo(self: *@This(), end: PointF32, control: PointF32) !void {
        if (self.start == null) {
            self.start = self.location;
            try self.nextSubpath();
        }

        // attempt to add a quadratic curve from current location to point
        const ao = try self.curves.addOne();
        ao.* = Curve{
            .end_curve = false,
            .curve_fn = CurveFn{
                .quadratic_bezier = QuadraticBezier{
                    .start = self.location,
                    .end = end,
                    .control = control,
                },
            },
        };

        (try self.currentSubpath()).curve_offsets.end += 1;
        self.location = end;
    }

    /// Closes the current subpath, if there is one
    pub fn close(self: *@This()) !void {
        if (self.start) |start| {
            if (!std.meta.eql(start, self.location)) {
                try self.lineTo(start);
            }

            self.location = start;
            self.start = null;
        }

        if (self.curves.items.len > 0) {
            self.curves.items[self.curves.items.len - 1].end_curve = true;
        }
    }
};
