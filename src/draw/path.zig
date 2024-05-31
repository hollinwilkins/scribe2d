const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = @import("../root.zig").RectF32;
const PointF32 = @import("../root.zig").PointF32;
const Outliner = @import("./Outliner.zig");

pub const Segment = union(Kind) {
    pub const Kind = enum(u16) {
        line,
        quadratic_bezier,
        cubic_bezier,
        curve,
        elliptical,
    };

    pub const Line = struct {
        start: PointF32, // start point
        end: PointF32, // end point
    };

    pub const QuadraticBezier = struct {
        start: PointF32, // start point
        end: PointF32, // end point
        control: PointF32, // control point
    };

    pub const CubicBezier = struct {
        start: PointF32, // start point
        end: PointF32, // end point
        control1: PointF32, // control point 1
        control2: PointF32, // control point 2
    };

    line: Line,
    quadratic_bezier: QuadraticBezier,
    cubic_bezier: CubicBezier,
    curve: void,
    elliptical: void,
};

pub const Path = struct {
    pub const Unmanaged = struct {
        segments: []const Segment,

        pub fn deinit(self: Unmanaged, allocator: Allocator) void {
            allocator.free(self.segments);
        }
    };

    allocator: Allocator,
    unmanaged: Unmanaged,

    pub fn deinit(self: Path) void {
        self.unmanaged.deinit(self.allocator);
    }

    pub fn segments(self: *const Path) []const Segment {
        return self.unmanaged.segments;
    }
};

pub const PathOutliner = struct {
    const SegmentsList = std.ArrayList(Segment);

    const OutlinerFunctions = struct {
        fn moveTo(ctx: *anyopaque, x: f32, y: f32) void {
            @as(*PathOutliner, @alignCast(@ptrCast(ctx))).moveTo(PointF32{ .x = x, .y = y });
        }

        fn lineTo(ctx: *anyopaque, x: f32, y: f32) void {
            @as(*PathOutliner, @alignCast(@ptrCast(ctx))).lineTo(PointF32{ .x = x, .y = y });
        }

        fn quadTo(ctx: *anyopaque, x1: f32, y1: f32, x: f32, y: f32) void {
            @as(*PathOutliner, @alignCast(@ptrCast(ctx))).quadTo(PointF32{ .x = x, .y = y }, PointF32{ .x = x1, .y = y1 });
        }

        fn curveTo(_: *anyopaque, _: f32, _: f32, _: f32, _: f32, _: f32, _: f32) void {
            @panic("PathOutliner does not support curveTo\n");
        }

        fn close(ctx: *anyopaque) void {
            @as(*PathOutliner, @alignCast(@ptrCast(ctx))).close();
        }
    };

    pub const OutlinerVTable = .{
        .moveTo = OutlinerFunctions.moveTo,
        .lineTo = OutlinerFunctions.lineTo,
        .quadTo = OutlinerFunctions.quadTo,
        .curveTo = OutlinerFunctions.curveTo,
        .close = OutlinerFunctions.close,
    };

    segments: SegmentsList,
    bounds: RectF32 = RectF32{},
    start: ?PointF32 = null,
    location: PointF32 = PointF32{},

    pub fn init(allocator: Allocator) Allocator.Error!PathOutliner {
        return PathOutliner{
            .segments = SegmentsList.init(allocator),
        };
    }

    pub fn deinit(self: *PathOutliner) void {
        self.segments.deinit();
    }

    pub fn outliner(self: *PathOutliner) Outliner {
        return Outliner{
            .ptr = self,
            .vtable = &OutlinerVTable,
        };
    }

    pub fn createPathAlloc(self: *PathOutliner, allocator: Allocator) Allocator.Error!Path {
        return Path{
            .allocator = allocator,
            .unmanaged = Path.Unmanaged{
                .segments = try allocator.dupe(Segment, self.segments.items),
            },
        };
    }

    pub fn moveTo(self: *PathOutliner, point: PointF32) void {
        // make sure to close any current subpath
        self.close();

        // set current location to point
        self.location = point;
    }

    pub fn lineTo(self: *PathOutliner, point: PointF32) !void {
        // attempt to add a line segment from current location to point
        const ao = try self.segments.addOne();
        ao.* = Segment{
            .line = Segment.Line{
                .start = self.location,
                .end = point,
            },
        };

        self.location = point;
    }

    pub fn quadTo(self: *PathOutliner, point: PointF32, control: PointF32) !void {
        // attempt to add a quadratic segment from current location to point
        const ao = try self.segments.addOne();
        ao.* = Segment{
            .line = Segment.QuadraticBezier{
                .start = self.location,
                .end = point,
                .control = control,
            },
        };

        self.location = point;
    }

    /// Closes the current subpath, if there is one
    pub fn close(self: *PathOutliner) !void {
        if (self.start) |start| {
            if (self.location) |end| {
                if (start != end) {
                    try self.lineTo(start);
                }

                self.location = start;
                self.start = null;
            }
        }
    }
};
