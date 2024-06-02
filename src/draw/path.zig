const std = @import("std");
const text = @import("../text/root.zig");
const core = @import("../core/root.zig");
const curve_module = @import("./curve.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const RangeF32 = core.RangeF32;
const Curve = curve_module.Curve;
const Line = curve_module.Line;
const QuadraticBezier = curve_module.QuadraticBezier;

pub const Path = struct {
    pub const Unmanaged = struct {
        curves: []const Curve,

        pub fn deinit(self: Unmanaged, allocator: Allocator) void {
            allocator.free(self.curves);
        }
    };

    allocator: Allocator,
    unmanaged: Unmanaged,

    pub fn deinit(self: Path) void {
        self.unmanaged.deinit(self.allocator);
    }

    pub fn getCurves(self: *const Path) []const Curve {
        return self.unmanaged.curves;
    }

    pub fn debug(self: *const Path) void {
        std.debug.print("Path\n", .{});
        for (self.unmanaged.curves) |curve| {
            std.debug.print("\t{}\n", .{curve});
        }
    }
};

pub const PathOutliner = struct {
    const CurvesList = std.ArrayList(Curve);

    const TextOutlinerFunctions = struct {
        fn moveTo(ctx: *anyopaque, x: f32, y: f32) void {
            var po = @as(*PathOutliner, @alignCast(@ptrCast(ctx)));
            po.moveTo(PointF32{ .x = x, .y = y }) catch {
                po.is_error = true;
            };
        }

        fn lineTo(ctx: *anyopaque, x: f32, y: f32) void {
            var po = @as(*PathOutliner, @alignCast(@ptrCast(ctx)));
            po.lineTo(PointF32{ .x = x, .y = y }) catch {
                po.is_error = true;
            };
        }

        fn quadTo(ctx: *anyopaque, x1: f32, y1: f32, x: f32, y: f32) void {
            var po = @as(*PathOutliner, @alignCast(@ptrCast(ctx)));
            po.quadTo(PointF32{ .x = x, .y = y }, PointF32{ .x = x1, .y = y1 }) catch {
                po.is_error = true;
            };
        }

        fn curveTo(_: *anyopaque, _: f32, _: f32, _: f32, _: f32, _: f32, _: f32) void {
            @panic("PathOutliner does not support curveTo\n");
        }

        fn close(ctx: *anyopaque) void {
            var po = @as(*PathOutliner, @alignCast(@ptrCast(ctx)));
            po.close() catch {
                po.is_error = true;
            };
        }
    };

    pub const TextOutlinerVTable = .{
        .moveTo = TextOutlinerFunctions.moveTo,
        .lineTo = TextOutlinerFunctions.lineTo,
        .quadTo = TextOutlinerFunctions.quadTo,
        .curveTo = TextOutlinerFunctions.curveTo,
        .close = TextOutlinerFunctions.close,
    };

    curves: CurvesList,
    bounds: RectF32 = RectF32{},
    start: ?PointF32 = null,
    location: PointF32 = PointF32{},
    is_error: bool = false,

    pub fn init(allocator: Allocator) Allocator.Error!PathOutliner {
        return PathOutliner{
            .curves = CurvesList.init(allocator),
        };
    }

    pub fn deinit(self: *PathOutliner) void {
        self.curves.deinit();
    }

    pub fn textOutliner(self: *PathOutliner) text.TextOutliner {
        return text.TextOutliner{
            .ptr = self,
            .vtable = &TextOutlinerVTable,
        };
    }

    pub fn createPathAlloc(self: *PathOutliner, allocator: Allocator) Allocator.Error!Path {
        return Path{
            .allocator = allocator,
            .unmanaged = Path.Unmanaged{
                .curves = try allocator.dupe(Curve, self.curves.items),
            },
        };
    }

    pub fn moveTo(self: *PathOutliner, point: PointF32) !void {
        self.start = null;

        // set current location to point
        self.location = point;
    }

    pub fn lineTo(self: *PathOutliner, point: PointF32) !void {
        // attempt to add a line curve from current location to point
        const ao = try self.curves.addOne();
        ao.* = Curve{
            .line = Line{
                .start = self.location,
                .end = point,
            },
        };

        if (self.start == null) {
            self.start = self.location;
        }
        self.location = point;
    }

    pub fn quadTo(self: *PathOutliner, point: PointF32, control: PointF32) !void {
        // attempt to add a quadratic curve from current location to point
        const ao = try self.curves.addOne();
        ao.* = Curve{
            .quadratic_bezier = QuadraticBezier{
                .start = self.location,
                .end = point,
                .control = control,
            },
        };

        if (self.start == null) {
            self.start = self.location;
        }
        self.location = point;
    }

    /// Closes the current subpath, if there is one
    pub fn close(self: *PathOutliner) !void {
        if (self.start) |start| {
            if (std.meta.eql(start, self.location)) {
                try self.lineTo(start);
            }

            self.location = start;
            self.start = null;
        }
    }
};
