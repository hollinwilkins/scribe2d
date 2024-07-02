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

pub const PathTag = packed struct {
    comptime {
        // make sure SegmentTag fits into a single byte
        std.debug.assert(@sizeOf(@This()) == 1);
    }

    pub const PATH: @This() = @This(){
        .index = Index{ .path = 1 },
    };
    pub const TRANSFORM: @This() = @This(){
        .transform = Index{ .path = 1 },
    };
    pub const STYLE: @This() = @This(){
        .style = Index{ .path = 1 },
    };

    pub const Kind = enum(u1) {
        segment = 0,
        index = 1,
    };

    pub const SegmentKind = enum(u3) {
        line_f32,
        arc_f32,
        quadratic_bezier_f32,
        cubic_bezier_f32,
        line_i16,
        arc_i16,
        quadratic_bezier_i16,
        cubic_bezier_i16,
    };

    pub const Segment = packed struct {
        // what kind of segment is this
        kind: SegmentKind = .none,
        // marks end of a subpath
        subpath_end: bool = false,
        // draw caps if true
        cap: bool = false,
    };

    pub const Index = packed struct {
        // increments path index by 1 or 0
        // set to 1 for the start of a new path
        path: u1 = 0,
        // increments transform index by 1 or 0
        // set to 1 for a new transform
        transform: u1 = 0,
        // increments the style index by 1 or 0
        style: u1 = 0,
    };

    kind: Kind,
    tag: packed union {
        segment: Segment,
        index: Index,
    },

    pub fn curve(kind: SegmentKind) @This() {
        return @This(){
            .segment = Segment{
                .kind = kind,
            },
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
    path_tags: []const PathTag,
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
    const PathTagList = std.ArrayListUnmanaged(PathTag);
    const AffineList = std.ArrayListUnmanaged(TransformF32.Affine);
    const StyleList = std.ArrayListUnmanaged(Style);
    const Buffer = std.ArrayListUnmanaged(u8);

    allocator: Allocator,
    path_tags: PathTagList = PathTagList{},
    transforms: AffineList = AffineList{},
    styles: StyleList = StyleList{},
    segments: Buffer = Buffer{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.path_tags.deinit(self.allocator);
        self.transforms.deinit(self.allocator);
        self.styles.deinit(self.allocator);
        self.segments.deinit(self.allocator);
    }

    pub fn encode(self: @This()) Encoding {
        return Encoding{
            .path_tags = self.path_tags.items,
            .transforms = self.transforms.items,
            .styles = self.styles.items,
            .segments = self.segments.items,
        };
    }

    pub fn currentPathTag(self: *@This()) ?*PathTag {
        if (self.path_tags.items.len > 0) {
            return self.path_tags.items[self.path_tags.items.len - 1];
        }

        return null;
    }

    pub fn encodePathTag(self: *@This(), tag: PathTag) !void {
        (try self.path_tags.addOne()).* = tag;
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
        try self.encodePathTag(PathTag.TRANSFORM);
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
        try self.encodePathTag(PathTag.STYLE);
        return true;
    }

    pub fn extendPath(self: *@This(), comptime T: type, kind: ?PathTag.SegmentKind) !*T {
        if (kind) |k| {
            try self.encodePathTag(PathTag.curve(k));
        }

        const bytes = try self.segments.addManyAsSlice(self.allocator, @sizeOf(T));
        return std.mem.bytesAsValue(T, bytes);
    }

    pub fn pathSegment(self: *@This(), comptime T: type, offset: usize) *T {
        return std.mem.bytesAsValue(T, self.segments.items[offset - @sizeOf(T) ..]);
    }

    pub fn pathTailSegment(self: *@This(), comptime T: type) *T {
        return std.mem.bytesAsValue(T, self.segments.items[self.segments.items.len - @sizeOf(T) ..]);
    }
};

pub fn PathEncoder(comptime T: type) type {
    const PPoint = Point(T);

    // Extend structs used to extend an open subpath
    const ExtendLine = extern struct {
        const KIND: PathTag.SegmentKind = switch (T) {
            f32 => .line_f32,
            i16 => .line_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
    };

    const ExtendArc = extern struct {
        const KIND: PathTag.SegmentKind = switch (T) {
            f32 => .arc_f32,
            i16 => .arc_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
        p2: PPoint,
    };

    const ExtendQuadraticBezier = extern struct {
        const KIND: PathTag.SegmentKind = switch (T) {
            f32 => .quadratic_bezier_f32,
            i16 => .quadratic_bezier_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
        p2: PPoint,
    };

    const ExtendCubicBezier = extern struct {
        const KIND: PathTag.SegmentKind = switch (T) {
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
        start_offset: usize,
        state: State = .start,

        pub fn create(encoder: *Encoder) @This() {
            return @This(){
                .encoder = encoder,
                .start_index = encoder.segments.items.len,
            };
        }

        pub fn deinit(self: *@This()) !void {
            if (self.encoder.currentStyle()) |style| {
                if (style.fill) {
                    try self.close();
                }
            }
        }

        pub fn isEmpty(self: @This()) bool {
            return self.start_offset == self.encoder.segments.items.len;
        }

        pub fn close(self: *@This()) !bool {
            if (self.isEmpty()) {
                return;
            }

            if (self.encoder.currentStyle()) |style| {
                if (style.fill) {
                    if (self.encoder.currentPathTag()) |tag| {
                        // ensure filled subpaths are closed
                        const start_point = self.encoder.pathSegment(PPoint, self.start_offset);
                        const closed = try self.lineTo(start_point.*);

                        if (closed) {
                            std.debug.assert(tag.kind == .segment);
                            tag.tag.segment.cap = true;
                        }

                        return closed;
                    }
                }
            }

            return false;
        }

        pub fn moveTo(self: *@This(), p0: PPoint) !void {
            switch (self.state) {
                .start => {
                    // add this move_to as a point to the end of the segments buffer
                    (try self.encoder.extendPath(PPoint, null)).* = p0;
                    self.state = .move_to;
                },
                .move_to => {
                    // update the current cursors position
                    (try self.encoder.pathTailSegment(PPoint, null)).* = p0;
                },
                .draw => {
                    try self.close();
                    (try self.encoder.extendPath(PPoint, null)).* = p0;
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
                else => {
                    const last_point = self.encoder.pathTailSegment(PPoint);

                    if (std.meta.eql(last_point.*, p1)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendLine, ExtendLine.KIND)).* = ExtendLine{
                        .p1 = p1,
                    };
                    self.state = .draw;
                },
            }
        }

        pub fn arcTo(self: *@This(), p1: PPoint, p2: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p2);
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(PPoint);

                    if (std.meta.eql(last_point.*, p1) and std.meta.eql(last_point.*, p2)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendArc, ExtendArc.KIND)).* = ExtendArc{
                        .p1 = p1,
                        .p2 = p2,
                    };
                    self.state = .draw;
                },
            }
        }

        pub fn quadTo(self: *@This(), p1: PPoint, p2: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p2);
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(PPoint);

                    if (std.meta.eql(last_point.*, p1) and std.meta.eql(last_point.*, p2)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendQuadraticBezier, ExtendQuadraticBezier.KIND)).* = ExtendQuadraticBezier{
                        .p1 = p1,
                        .p2 = p2,
                    };
                    self.state = .draw;
                },
            }
        }

        pub fn cubicTo(self: *@This(), p1: PPoint, p2: PPoint, p3: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p3);
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(PPoint);

                    if (std.meta.eql(last_point.*, p1) and std.meta.eql(last_point.*, p2) and std.meta.eql(last_point.*, p3)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendCubicBezier, ExtendCubicBezier.KIND)).* = ExtendCubicBezier{
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                    };
                    self.state = .draw;
                },
            }
        }
    };
}
