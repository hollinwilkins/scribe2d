const std = @import("std");
const text = @import("../text/root.zig");
const core = @import("../core/root.zig");
const curve_module = @import("./curve.zig");
const path_module = @import("./path.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const Shape = curve_module.Shape;
const Curve = curve_module.Curve;
const CurveFn = curve_module.CurveFn;
const Line = curve_module.Line;
const QuadraticBezier = curve_module.QuadraticBezier;
const SequenceU32 = core.SequenceU32;
const Path = path_module.Path;

pub const Pen = struct {
    const ShapesList = std.ArrayList(Shape);
    const CurvesList = std.ArrayList(Curve);

    const TextOutlinerFunctions = struct {
        fn moveTo(ctx: *anyopaque, x: f32, y: f32) void {
            var po = @as(*Pen, @alignCast(@ptrCast(ctx)));
            po.moveTo(PointF32{ .x = x, .y = y }) catch {
                po.is_error = true;
            };
        }

        fn lineTo(ctx: *anyopaque, x: f32, y: f32) void {
            var po = @as(*Pen, @alignCast(@ptrCast(ctx)));
            po.lineTo(PointF32{ .x = x, .y = y }) catch {
                po.is_error = true;
            };
        }

        fn quadTo(ctx: *anyopaque, x1: f32, y1: f32, x: f32, y: f32) void {
            var po = @as(*Pen, @alignCast(@ptrCast(ctx)));
            po.quadTo(PointF32{ .x = x, .y = y }, PointF32{ .x = x1, .y = y1 }) catch {
                po.is_error = true;
            };
        }

        fn curveTo(_: *anyopaque, _: f32, _: f32, _: f32, _: f32, _: f32, _: f32) void {
            @panic("PathOutliner does not support curveTo\n");
        }

        fn close(ctx: *anyopaque) void {
            var po = @as(*Pen, @alignCast(@ptrCast(ctx)));
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

    shapes: ShapesList,
    curves: CurvesList,
    bounds: RectF32 = RectF32{},
    start: ?PointF32 = null,
    location: PointF32 = PointF32{},
    is_error: bool = false,

    pub fn init(allocator: Allocator) Allocator.Error!@This() {
        return @This(){
            .shapes = ShapesList.init(allocator),
            .curves = CurvesList.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.shapes.deinit();
        self.curves.deinit();
    }

    pub fn textOutliner(self: *@This()) text.TextOutliner {
        return text.TextOutliner{
            .ptr = self,
            .vtable = &TextOutlinerVTable,
        };
    }

    pub fn createPathAlloc(self: *@This(), allocator: Allocator) Allocator.Error!Path {
        try self.close();
        return Path{
            .allocator = allocator,
            .unmanaged = Path.Unmanaged.create(
                try allocator.dupe(Shape, self.shapes.items),
                try allocator.dupe(Curve, self.curves.items),
            ),
        };
    }

    pub fn currentShape(self: *@This()) !*Shape {
        if (self.shapes.items.len == 0) {
            return self.nextShape();
        }

        return &self.shapes.items[self.shapes.items.len - 1];
    }

    pub fn nextShape(self: *@This()) !*Shape {
        const ao = try self.shapes.addOne();
        ao.* = Shape{ .curve_offsets = RangeU32{
            .start = @intCast(self.shapes.items.len),
            .end = @intCast(self.shapes.items.len),
        } };

        return ao;
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
            _ = try self.nextShape();
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

        (try self.currentShape()).curve_offsets.end += 1;
        self.location = point;
    }

    pub fn quadTo(self: *@This(), point: PointF32, control: PointF32) !void {
        if (self.start == null) {
            self.start = self.location;
            _ = try self.nextShape();
        }

        // attempt to add a quadratic curve from current location to point
        const ao = try self.curves.addOne();
        ao.* = Curve{
            .end_curve = false,
            .curve_fn = CurveFn{
                .quadratic_bezier = QuadraticBezier{
                    .start = self.location,
                    .end = point,
                    .control = control,
                },
            },
        };

        (try self.currentShape()).curve_offsets.end += 1;
        self.location = point;
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
