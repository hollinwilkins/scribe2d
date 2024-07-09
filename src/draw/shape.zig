const std = @import("std");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Point = core.Point;

pub const Segment = enum {
    move_to,
    line,
    arc,
    quadratic_bezier,
    cubic_bezier,
};

pub const ShapePrimitive = enum(u1) {
    float32,
    int16,
};

pub fn Shape(comptime T: type) type {
    return struct {
        const PRIMITIVE: ShapePrimitive = switch (T) {
            f32 => .float32,
            i16 => .int16,
        };

        segments: []const Segment,
        segment_data: []const u8,
    };
}

pub fn Shaper(comptime T: type) type {
    const P = Point(T);
    const S = Shape(T);

    return struct {
        const SegmentList = std.ArrayListUnmanaged(Segment);
        const Buffer = std.ArrayListUnmanaged(u8);

        allocator: Allocator,
        state: State = .start,
        segments: SegmentList = SegmentList{},
        segment_data: Buffer = Buffer{},

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.segments.deinit(self.allocator);
            self.segment_data.deinit(self.allocator);
        }

        pub fn toShape(self: @This()) S {
            return Shape(T){
                .segments = self.segments.items,
                .segment_data = self.segment_data.items,
            };
        }

        pub fn encodeSegment(self: *@This(), segment: Segment) !void {
            (try self.segments.addOne(self.allocator)).* = segment;
        }

        pub fn moveTo(self: *@This(), point: P) !void {
            switch (self.state) {
                .start => {
                    (try self.extendPath(P, null)).* = point;
                    self.state = .move_to;
                },
                .move_to => {
                    self.pathTailSegment(P).* = point;
                },
                .draw => {
                    (try self.extendPath(P, .move_to)).* = point;
                    self.state = .move_to;
                },
            }
        }

        pub fn lineTo(self: *@This(), p1: P) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p1);
                    return false;
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(P).*;

                    if (std.meta.eql(last_point, p1)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendLine, ExtendLine.SEGMENT)).* = ExtendLine{
                        .p1 = p1,
                    };
                    self.state = .draw;
                    return true;
                },
            }
        }

        pub fn arcTo(self: *@This(), p1: P, p2: P) !bool {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p2);
                    return false;
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(P).*;

                    if (std.meta.eql(last_point, p1) and std.meta.eql(last_point, p2)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendArc, ExtendArc.SEGMENT)).* = ExtendArc{
                        .p1 = p1,
                        .p2 = p2,
                    };
                    self.state = .draw;
                    return true;
                },
            }
        }

        pub fn quadTo(self: *@This(), p1: P, p2: P) !bool {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p2);
                    return false;
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(P).*;

                    if (std.meta.eql(last_point, p1) and std.meta.eql(last_point, p2)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendQuadraticBezier, ExtendQuadraticBezier.SEGMENT)).* = ExtendQuadraticBezier{
                        .p1 = p1,
                        .p2 = p2,
                    };
                    self.state = .draw;
                    return true;
                },
            }
        }

        pub fn cubicTo(self: *@This(), p1: P, p2: P, p3: P) !bool {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p3);
                    return false;
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(P).*;

                    if (std.meta.eql(last_point, p1) and std.meta.eql(last_point, p2) and std.meta.eql(last_point, p3)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendCubicBezier, ExtendCubicBezier.SEGMENT)).* = ExtendCubicBezier{
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                    };
                    self.state = .draw;
                    return true;
                },
            }
        }

        pub fn extendPath(self: *@This(), comptime E: type, segment: ?Segment) !*T {
            if (segment) |s| {
                try self.encodeSegment(s);
            }

            const bytes = try self.segment_data.addManyAsSlice(self.allocator, @sizeOf(E));
            return @alignCast(std.mem.bytesAsValue(E, bytes));
        }

        pub fn pathTailSegment(self: *@This(), comptime E: type) *E {
            return @alignCast(std.mem.bytesAsValue(E, self.segment_data.items[self.segment_data.items.len - @sizeOf(E) ..]));
        }

        pub const State = enum {
            start,
            move_to,
            draw,
        };

        pub const ExtendLine = struct {
            pub const SEGMENT: Segment = .line;

            p1: P,
        };

        pub const ExtendArc = struct {
            pub const SEGMENT: Segment = .arc;

            p1: P,
            p2: P,
        };

        pub const ExtendQuadraticBezier = struct {
            pub const SEGMENT: Segment = .quadratic_bezier;

            p1: P,
            p2: P,
        };

        pub const ExtendCubicBezier = struct {
            pub const SEGMENT: Segment = .cubic_bezier;

            p1: P,
            p2: P,
            p3: P,
        };
    };
}
