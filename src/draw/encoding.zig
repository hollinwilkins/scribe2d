const std = @import("std");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const Point = core.Point;
const Line = core.Line;
const Arc = core.Arc;
const LineF32 = core.LineF32;
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
        kind: SegmentKind = .line_f32,
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

    segment: Segment = Segment{},
    index: Index = Index{},

    pub fn curve(kind: SegmentKind) @This() {
        return @This(){
            .segment = Segment{
                .kind = kind,
            },
        };
    }
};

pub fn Color(comptime T: type) type {
    return struct {
        r: T = 0,
        g: T = 0,
        b: T = 0,
        a: T = 0,
    };
}

pub const ColorF32 = Color(f32);
pub const ColorU8 = Color(u8);

pub const Style = packed struct {
    comptime {
        std.debug.assert(@sizeOf(Style) <= 32);
    }

    pub const Brush = enum(u1) {
        noop,
        color,

        pub fn offset(self: @This()) u32 {
            return switch (self) {
                .noop => 0,
                .color => @sizeOf(ColorU8),
            };
        }
    };

    pub const FillRule = enum(u2) {
        even_odd = 1,
        non_zero = 2,
    };

    pub const Fill = packed struct {
        rule: FillRule = .even_odd,
        brush: Brush = .noop,
    };

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

    pub const Stroke = packed struct {
        width: f32 = 1.0,
        join: Join = .round,
        start_cap: Cap = .round,
        end_cap: Cap = .round,
        miter_limit: f16 = 4.0,
        // encode dash in the stroke, because we will want to expand it using kernels
        dash: bool = false,
        brush: Brush = .noop,
    };

    pub const Flags = packed struct {
        fill: bool = false,
        stroke: bool = false,
    };

    flags: Flags = Flags{},
    fill: Fill = Fill{},
    stroke: Stroke = Stroke{},

    pub fn setFill(self: *@This(), new_fill: Fill) void {
        self.flags.fill = true;
        self.fill = new_fill;
    }

    pub fn setStroke(self: *@This(), new_stroke: Stroke) void {
        self.flags.stroke = true;
        self.stroke = new_stroke;
    }

    pub fn isFill(self: @This()) bool {
        return self.flags.fill;
    }

    pub fn isStroke(self: @This()) bool {
        self.flags.stroke;
    }
};

pub const PathMonid = extern struct {
    path_index: u32 = 0,
    segment_index: u32 = 0,
    segment_offset: u32 = 0,
    transform_index: u32 = 0,
    style_index: u32 = 0,
    brush_offset: u32 = 0,

    pub fn createTag(tag: PathTag) @This() {
        const segment = tag.tag.segment;
        const index = tag.tag.index;
        const segment_offset: u32 = switch (segment.kind) {
            .none => unreachable,
            .line_f32 => @sizeOf(Point(f32)),
            .line_i16 => @sizeOf(Point(i16)),
            .arc_f32 => @sizeOf(Point(f32)) * 2,
            .arc_i16 => @sizeOf(Point(i16)) * 2,
            .quadratic_bezier_f32 => @sizeOf(Point(f32)) * 2,
            .quadratic_bezier_i16 => @sizeOf(Point(i16)) * 2,
            .cubic_bezier_f32 => @sizeOf(Point(f32)) * 3,
            .cubic_bezier_i16 => @sizeOf(Point(i16)) * 3,
        };
        return @This(){
            .segment_index = 1,
            .segment_offset = segment_offset,
            .path_index = @intCast(index.path),
            .transform_index = @intCast(index.transform),
            .style_index = @intCast(index.style),
        };
    }

    pub fn combine(self: @This(), other: @This()) @This() {
        return @This(){
            .path_index = self.path_index + other.path_index,
            .segment_index = self.segment_index + other.segment_index,
            .segment_offset = self.segment_offset + other.segment_offset,
            .transform_index = self.transform_index + other.transform_index,
            .style_index = self.style_index + other.style_index,
        };
    }

    pub fn expandTags(tags: []const PathTag, expanded: []PathMonid) void {
        std.debug.assert(tags.len == expanded.len);

        var monoid = PathMonid{};
        for (tags, expanded) |tag, *expanded_monoid| {
            monoid = monoid.combine(PathMonid.createTag(tag));
            expanded_monoid.* = monoid;
        }
    }
};

// Encodes all data needed for a single draw command to the GPU or CPU
pub const Encoding = struct {
    path_tags: []const PathTag,
    transforms: []const TransformF32.Affine,
    styles: []const Style,
    segment_data: []const u8,
    brush_data: []const u8,

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
    segment_data: Buffer = Buffer{},
    draw_data: Buffer = Buffer{},
    staged_transform: bool = false,
    staged_style: bool = false,

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.path_tags.deinit(self.allocator);
        self.transforms.deinit(self.allocator);
        self.styles.deinit(self.allocator);
        self.segment_data.deinit(self.allocator);
        self.draw_data.deinit(self.allocator);
    }

    pub fn encode(self: @This()) Encoding {
        return Encoding{
            .path_tags = self.path_tags.items,
            .transforms = self.transforms.items,
            .styles = self.styles.items,
            .segment_data = self.segment_data.items,
            .draw_data = self.draw_data.items,
        };
    }

    pub fn currentPathTag(self: *@This()) ?*PathTag {
        if (self.path_tags.items.len > 0) {
            return &self.path_tags.items[self.path_tags.items.len - 1];
        }

        return null;
    }

    pub fn encodePathTag(self: *@This(), tag: PathTag) !void {
        var tag2 = tag;

        if (self.staged_transform) {
            self.staged_transform = false;
            tag2.index.transform = 1;
        }

        if (self.staged_style) {
            self.staged_style = false;
            tag2.index.style = 1;
        }

        (try self.path_tags.addOne(self.allocator)).* = tag2;
    }

    pub fn currentTransform(self: *@This()) ?*TransformF32.Affine {
        if (self.transforms.items.len > 0) {
            return self.transforms.items[self.transforms.items.len - 1];
        }

        return null;
    }

    pub fn encodeTransform(self: *@This(), affine: TransformF32.Affine) !void {
        if (self.currentTransform()) |current| {
            if (std.meta.eql(current, affine)) {
                return;
            } else if (self.staged_transform) {
                current.* = affine;
            }
        }

        (try self.transforms.addOne(self.allocator)).* = affine;
        self.staged_transform = true;
    }

    pub fn currentStyle(self: *@This()) ?*Style {
        if (self.styles.items.len > 0) {
            return &self.styles.items[self.styles.items.len - 1];
        }

        return null;
    }

    pub fn encodeStyle(self: *@This(), style: Style) !void {
        if (self.currentStyle()) |current| {
            if (std.meta.eql(current.*, style)) {
                return;
            } else if (self.staged_style) {
                current.* = style;
            }
        }

        (try self.styles.addOne(self.allocator)).* = style;
        self.staged_style = true;
    }

    pub fn extendPath(self: *@This(), comptime T: type, kind: ?PathTag.SegmentKind) !*T {
        if (kind) |k| {
            try self.encodePathTag(PathTag.curve(k));
        }

        const bytes = try self.segment_data.addManyAsSlice(self.allocator, @sizeOf(T));
        return @alignCast(std.mem.bytesAsValue(T, bytes));
    }

    pub fn pathSegment(self: *@This(), comptime T: type, offset: usize) *T {
        return @alignCast(std.mem.bytesAsValue(T, self.segment_data.items[offset .. offset + @sizeOf(T)]));
    }

    pub fn pathTailSegment(self: *@This(), comptime T: type) *T {
        return @alignCast(std.mem.bytesAsValue(T, self.segment_data.items[self.segment_data.items.len - @sizeOf(T) ..]));
    }

    pub fn encodeColor(self: *@This(), color: ColorU8) !void {
        const bytes = (try self.draw_data.addManyAsSlice(self.allocator, @sizeOf(ColorU8)));
        std.mem.bytesAsValue(ColorU8, bytes).* = color;
    }

    pub fn pathEncoder(self: *@This(), comptime T: type) PathEncoder(T) {
        const style = self.currentStyle().?;
        return PathEncoder(T).create(self, style.isFill());
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
        is_fill: bool,
        state: State = .start,

        pub fn create(encoder: *Encoder, is_fill: bool) @This() {
            return @This(){
                .encoder = encoder,
                .is_fill = is_fill,
                .start_offset = @intCast(encoder.segment_data.items.len),
            };
        }

        pub fn isEmpty(self: @This()) bool {
            return self.start_offset == self.encoder.segment_data.items.len;
        }

        pub fn finish(self: *@This()) !void {
            if (self.state == .start) {
                return;
            }

            if (self.is_fill) {
                _ = try self.close();
            }

            try self.encoder.encodePathTag(PathTag.PATH);
        }

        pub fn close(self: *@This()) !void {
            if (self.state != .draw or self.isEmpty()) {
                return;
            }

            if (self.is_fill) {
                if (self.encoder.currentPathTag()) |tag| {
                    // ensure filled subpaths are closed
                    const start_point = self.encoder.pathSegment(PPoint, self.start_offset);
                    const closed = try self.lineTo(start_point.*);

                    if (closed) {
                        tag.segment.cap = true;
                    }
                }
            }
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
                    self.encoder.pathTailSegment(PPoint).* = p0;
                },
                .draw => {
                    try self.close();
                    (try self.encoder.extendPath(PPoint, null)).* = p0;
                    self.state = .move_to;
                },
            }
        }

        pub fn lineTo(self: *@This(), p1: PPoint) Allocator.Error!bool {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p1);
                    return false;
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
                    return true;
                },
            }
        }

        pub fn arcTo(self: *@This(), p1: PPoint, p2: PPoint) !bool {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p2);
                    return false;
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
                    return true;
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

pub const FlatEncoding = struct {
    lines: []const Line,
};

pub const FlatEncoder = struct {
    const LineList = std.ArrayListUnmanaged(LineF32);

    allocator: Allocator,
    lines: LineList = LineList{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.lines.deinit(self.allocator);
    }

    pub fn reset(self: *@This()) void {
        self.lines.items.len = 0;
    }

    pub fn encode(self: @This()) FlatEncoding {
        return FlatEncoding{
            .lines = self.lines.items,
        };
    }
};

pub const ScanlineEncoding = struct {};

pub const ScanlineEncoder = struct {};

pub const CpuRasterizer = struct {
    const PathMonoidList = std.ArrayListUnmanaged(PathMonid);

    allocator: Allocator,
    encoding: Encoding,
    path_monoids: PathMonoidList = PathMonoidList{},
    flat_encoder: FlatEncoder,

    pub fn init(allocator: Allocator, encoding: Encoding) @This() {
        return @This(){
            .allocator = allocator,
            .encoding = encoding,
            .flat_encoder = FlatEncoder.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.path_monoids.deinit(self.allocator);
    }

    pub fn reset(self: *@This()) void {
        self.path_monoids.items.len = 0;
        self.flat_encoder.reset();
    }

    pub fn setEncoding(self: *@This(), encoding: Encoding) void {
        self.encoding = encoding;
    }

    pub fn rasterize(self: *@This()) !void {
        // reset the rasterizer
        self.reset();
        // expand path monoids
        try self.expandPathMonoids();
        // estimate FlatEncoder memory requirements
        try self.estimateFlatEncoding();
        // allocate the FlatEncoder
        // use the FlatEncoder to flatten the encoding
        // estimate the ScanlineEncoding
        // use the FlatEncoding to calculate ScanlineEncoding
        // use the ScanlineEncoding to rasterize pixels
    }

    fn expandPathMonoids(self: *@This()) !void {
        self.path_monoids = try self.path_monoids.addManyAsSlice(self.allocator, self.encoding.path_tags.len);
        PathMonid.expandTags(self.encoding.path_tags, self.path_monoids);
    }

    fn estimateFlatEncoding(self: *@This()) !void {
        _ = self;

        // need to estimate memory and set fills
    }

    fn flatten(self: *@This(), encoding: Encoding) !void {
        _ = self;
        _ = encoding;
    }

    fn estimateScanlineEncoding(self: *@This()) !void {
        _ = self;
    }

    fn rasterizeScanlineEncoding(self: *@This()) !void {
        _ = self;
    }
};
