const std = @import("std");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const Point = core.Point;
const Line = core.Line;
const Arc = core.Arc;
const QuadraticBezier = core.QuadraticBezier;
const CubicBezier = core.CubicBezier;

pub const SegmentTag = packed struct {
    comptime {
        // make sure SegmentTag fits into a single byte
        std.debug.assert(@sizeOf(@This()) == 1);
    }

    pub const PATH: SegmentTag = SegmentTag{
        .path = 1,
    };
    pub const TRANSFORM: SegmentTag = SegmentTag{
        .transform = 1,
    };
    pub const STYLE: SegmentTag = SegmentTag{
        .style = 1,
    };

    pub const Kind = enum(u4) {
        none,
        line_f32,
        arc_f32,
        quadratic_bezier_f32,
        cubic_bezier_f32,
        line_i16,
        arc_i16,
        quadratic_bezier_i16,
        cubic_bezier_i16,
    };

    // what kind of segment is this
    kind: Kind = .none,
    // marks end of a subpath
    subpath_end: bool = false,
    // increments path index by 1 or 0
    // set to 1 for the start of a new path
    path: u1 = 0,
    // increments transform index by 1 or 0
    // set to 1 for a new transform
    transform: u1 = 0,
    // increments the style index by 1 or 0
    style: u1 = 0,

    pub fn curve(kind: Kind) @This() {
        return @This(){
            .kind = kind,
        };
    }
};

pub const Style = packed struct {
    pub const Join = enum(u2) {
        bevel,
        miter,
        round,
    };

    pub const Cap = enum(u2) {
        butt,
        square,
        round,
    };

    pub const Dash = packed struct {
        dash: [4]f32 = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
        dash_offset: f32 = 0.0,
    };

    pub const Stroke = packed struct {
        width: f32 = 1.0,
        join: Join = .round,
        start_cap: Cap = .round,
        end_cap: Cap = .round,
        miter_limit: f16 = 4.0,
        // encode dash in the stroke, because we will want to expand it using kernels
        dash: Dash = Dash{},
    };

    fill: bool = false,
    stroke: ?Stroke = null,
};

// Encodes all data needed for a single draw command to the GPU or CPU
pub const Encoding = struct {
    segment_tags: []const SegmentTag,
    transforms: []const TransformF32.Affine,
    styles: []const Style,
    segments: []const u8,

    pub fn createFromBytes(bytes: []const u8) Encoding {
        _ = bytes;
        @panic("TODO: implement this for GPU kernels");
    }
};

// This encoding can get sent to kernels
pub const Encoder = struct {
    const SegmentTagList = std.ArrayListUnmanaged(SegmentTag);
    const AffineList = std.ArrayListUnmanaged(TransformF32.Affine);
    const StyleList = std.ArrayListUnmanaged(Style);
    const Buffer = std.ArrayListUnmanaged(u8);

    allocator: Allocator,
    segment_tags: SegmentTagList = SegmentTagList{},
    transforms: AffineList = AffineList{},
    styles: StyleList = StyleList{},
    segments: Buffer = Buffer{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.segment_tags.deinit(self.allocator);
        self.transforms.deinit(self.allocator);
        self.styles.deinit(self.allocator);
        self.segments.deinit(self.allocator);
    }

    pub fn encode(self: @This()) Encoding {
        return Encoding{
            .segment_tags = self.segment_tags.items,
            .transforms = self.transforms.items,
            .styles = self.styles.items,
            .segments = self.segments.items,
        };
    }

    pub fn currentSegmentTag(self: *@This()) ?*SegmentTag {
        if (self.segment_tags.items.len > 0) {
            return self.segment_tags.items[self.segment_tags.items.len - 1];
        }

        return null;
    }

    pub fn encodeSegmentTag(self: *@This(), tag: SegmentTag) !void {
        (try self.segment_tags.addOne()).* = tag;
    }

    pub fn currentAffine(self: *@This()) ?*TransformF32.Affine {
        if (self.transforms.items.len > 0) {
            return self.transforms.items[self.transforms.items.len - 1];
        }

        return null;
    }

    pub fn encodeAffine(self: *@This(), affine: TransformF32.Affine) !bool {
        if (self.currentAffine()) |current| {
            if (std.meta.eql(current, affine)) {
                return false;
            }
        }

        (try self.transforms.addOne()).* = affine;
        try self.encodeSegmentTag(SegmentTag.TRANSFORM);
        return true;
    }

    pub fn currentStyle(self: *@This()) ?*Style {
        if (self.styles.items.len > 0) {
            return self.styles.items[self.styles.items.len - 1];
        }

        return null;
    }

    pub fn encodeStyle(self: *@This(), style: Style) !bool {
        if (self.currentStyle()) |current| {
            if (std.meta.eql(current, style)) {
                return false;
            }
        }

        (try self.styles.addOne()).* = style;
        try self.encodeSegmentTag(SegmentTag.STYLE);
        return true;
    }

    pub fn extendSegment(self: *@This(), comptime T: type, kind: ?SegmentTag.Kind) !*T {
        if (kind) |k| {
            try self.encodeSegmentTag(SegmentTag.curve(k));
        }

        const bytes = try self.segments.addManyAsSlice(self.allocator, @sizeOf(T));
        return std.mem.bytesAsValue(T, bytes);
    }

    pub fn segmentTail(self: *@This(), comptime T: type) *T {
        return std.mem.bytesAsValue(T, self.segments.items[self.segments.items.len - @sizeOf(T) ..]);
    }
};

pub fn PathEncoder(comptime T: type) type {
    const PPoint = Point(T);

    // Extend structs used to extend an open subpath
    const ExtendLine = extern struct {
        const KIND: SegmentTag.Kind = switch (T) {
            f32 => .line_f32,
            i16 => .line_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
    };

    const ExtendArc = extern struct {
        const KIND: SegmentTag.Kind = switch (T) {
            f32 => .arc_f32,
            i16 => .arc_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
        p2: PPoint,
    };

    const ExtendQuadraticBezier = extern struct {
        const KIND: SegmentTag.Kind = switch (T) {
            f32 => .quadratic_bezier_f32,
            i16 => .quadratic_bezier_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
        p2: PPoint,
    };

    const ExtendCubicBezier = extern struct {
        const KIND: SegmentTag.Kind = switch (T) {
            f32 => .cubic_bezier_f32,
            i16 => .cubic_bezier_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
        p2: PPoint,
        p3: PPoint,
    };

    const State = enum {
        start,
        move_to,
        draw,
    };

    return struct {
        encoder: *Encoder,
        state: State = .start,

        pub fn deinit(self: *@This()) void {
            if (self.encoder.currentStyle()) |style| {
                if (style.fill) {
                    self.close();
                }
            }
        }

        pub fn moveTo(self: *@This(), p0: PPoint) !void {
            switch (self.state) {
                .start => {
                    // add this move_to as a point to the end of the segments buffer
                    (try self.encoder.extendSegment(PPoint, null)).* = p0;
                    self.state = .move_to;
                },
                .move_to => {
                    // update the current cursors position
                    (try self.encoder.segmentTail(PPoint, null)).* = p0;
                },
                .draw => {
                    (try self.encoder.extendSegment(PPoint, null)).* = p0;
                    self.state = .move_to;
                },
            }
        }

        pub fn lineTo(self: *@This(), p1: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p1);
                },
                .move_to => {
                    (try self.encoder.extendSegment(ExtendLine, ExtendLine.KIND)).* = ExtendLine{
                        .p1 = p1,
                    };
                    self.state = .draw;
                },
                .draw => {
                    (try self.encoder.extendSegment(ExtendLine, ExtendLine.KIND)).* = ExtendLine{
                        .p1 = p1,
                    };
                },
            }
        }

        pub fn arcTo(self: *@This(), p1: PPoint, p2: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p2);
                },
                .move_to => {
                    (try self.encoder.extendSegment(ExtendArc, ExtendArc.KIND)).* = ExtendArc{
                        .p1 = p1,
                        .p2 = p2,
                    };
                    self.state = .draw;
                },
                .draw => {
                    (try self.encoder.extendSegment(ExtendArc, ExtendArc.KIND)).* = ExtendArc{
                        .p1 = p1,
                        .p2 = p2,
                    };
                },
            }
        }

        pub fn quadTo(self: *@This(), p1: PPoint, p2: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p2);
                },
                .move_to => {
                    (try self.encoder.extendSegment(ExtendQuadraticBezier, ExtendQuadraticBezier.KIND)).* = ExtendQuadraticBezier{
                        .p1 = p1,
                        .p2 = p2,
                    };
                    self.state = .draw;
                },
                .draw => {
                    (try self.encoder.extendSegment(ExtendQuadraticBezier, ExtendQuadraticBezier.KIND)).* = ExtendQuadraticBezier{
                        .p1 = p1,
                        .p2 = p2,
                    };
                },
            }
        }

        pub fn cubicTo(self: *@This(), p1: PPoint, p2: PPoint, p3: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p2);
                },
                .move_to => {
                    (try self.encoder.extendSegment(ExtendCubicBezier, ExtendCubicBezier.KIND)).* = ExtendCubicBezier{
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                    };
                    self.state = .draw;
                },
                .draw => {
                    (try self.encoder.extendSegment(ExtendCubicBezier, ExtendCubicBezier.KIND)).* = ExtendCubicBezier{
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                    };
                },
            }
        }
    };
}
