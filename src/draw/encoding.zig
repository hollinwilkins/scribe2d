const std = @import("std");
const core = @import("../core/root.zig");
const encoding_kernel = @import("./encoding_kernel.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const Point = core.Point;
const Line = core.Line;
const Arc = core.Arc;
const QuadraticBezier = core.QuadraticBezier;
const CubicBezier = core.CubicBezier;
const PointF32 = core.PointF32;
const PointI16 = core.PointI16;
const LineF32 = core.LineF32;
const LineI16 = core.LineI16;
const ArcF32 = core.ArcF32;
const ArcI16 = core.ArcI16;
const QuadraticBezierF32 = core.QuadraticBezierF32;
const QuadraticBezierI16 = core.QuadraticBezierI16;
const CubicBezierF32 = core.CubicBezierF32;
const CubicBezierI16 = core.CubicBezierI16;
const KernelConfig = encoding_kernel.KernelConfig;
const SegmentOffsets = encoding_kernel.SegmentOffsets;
const GridIntersection = encoding_kernel.GridIntersection;
const BoundaryFragment = encoding_kernel.BoundaryFragment;
const MergeFragment = encoding_kernel.MergeFragment;
const Span = encoding_kernel.Span;

pub const PathTag = packed struct {
    comptime {
        // make sure SegmentTag fits into a single byte
        std.debug.assert(@sizeOf(@This()) == 1);
    }

    pub const Kind = enum(u3) {
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
        kind: Kind,
        // draw caps if true
        cap: bool = false,
    };

    pub const Index = packed struct {
        // increments path index by 1 or 0
        // set to 1 for the start of a new path
        // 1-based indexing
        path: u1 = 0,
        // increment subpath by 1
        subpath: u1 = 0,
        // increments transform index by 1 or 0
        // set to 1 for a new transform
        transform: u1 = 0,
        // increments the style index by 1 or 0
        style: u1 = 0,
    };

    segment: Segment,
    index: Index = Index{},

    pub fn curve(kind: Kind) @This() {
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
        return self.flags.stroke;
    }
};

pub fn MonoidFunctions(comptime T: type, comptime M: type) type {
    return struct {
        pub fn expand(tags: []const T, expanded: []M) void {
            std.debug.assert(tags.len == expanded.len);

            var monoid = M{};
            for (tags, expanded) |tag, *expanded_monoid| {
                monoid = monoid.combine(M.createTag(tag));
                expanded_monoid.* = monoid;
            }

            if (std.meta.hasFn(M, "fixExpansion")) {
                M.fixExpansion(expanded);
            }
        }
    };
}

pub const PathMonoid = extern struct {
    path_index: u32 = 0,
    subpath_index: u32 = 0,
    segment_index: u32 = 0,
    segment_offset: u32 = 0,
    transform_index: u32 = 0,
    style_index: u32 = 0,
    brush_offset: u32 = 0,

    pub usingnamespace MonoidFunctions(PathTag, @This());

    pub fn createTag(tag: PathTag) @This() {
        const segment = tag.segment;
        const index = tag.index;
        const segment_offset: u32 = switch (segment.kind) {
            .line_f32 => @sizeOf(LineF32) - @sizeOf(PointF32),
            .line_i16 => @sizeOf(LineI16) - @sizeOf(PointI16),
            .arc_f32 => @sizeOf(ArcF32) - @sizeOf(PointF32),
            .arc_i16 => @sizeOf(ArcI16) - @sizeOf(PointI16),
            .quadratic_bezier_f32 => @sizeOf(QuadraticBezierF32) - @sizeOf(PointF32),
            .quadratic_bezier_i16 => @sizeOf(QuadraticBezierI16) - @sizeOf(PointI16),
            .cubic_bezier_f32 => @sizeOf(CubicBezierF32) - @sizeOf(PointF32),
            .cubic_bezier_i16 => @sizeOf(CubicBezierI16) - @sizeOf(PointI16),
        };
        var path_offset: u32 = 0;
        if (index.path == 1) {
            path_offset += switch (segment.kind) {
                .line_f32 => @sizeOf(PointF32),
                .line_i16 => @sizeOf(PointI16),
                .arc_f32 => @sizeOf(PointF32),
                .arc_i16 => @sizeOf(PointI16),
                .quadratic_bezier_f32 => @sizeOf(PointF32),
                .quadratic_bezier_i16 => @sizeOf(PointI16),
                .cubic_bezier_f32 => @sizeOf(PointF32),
                .cubic_bezier_i16 => @sizeOf(PointI16),
            };
        }
        return @This(){
            .path_index = @intCast(index.path),
            .subpath_index = @intCast(index.subpath),
            .segment_index = 1,
            .segment_offset = path_offset + segment_offset,
            .transform_index = @intCast(index.transform),
            .style_index = @intCast(index.style),
        };
    }

    pub fn combine(self: @This(), other: @This()) @This() {
        return @This(){
            .path_index = self.path_index + other.path_index,
            .subpath_index = self.subpath_index + other.subpath_index,
            .segment_index = self.segment_index + other.segment_index,
            .segment_offset = self.segment_offset + other.segment_offset,
            .transform_index = self.transform_index + other.transform_index,
            .style_index = self.style_index + other.style_index,
        };
    }

    pub fn fixExpansion(expanded: []@This()) void {
        for (expanded) |*monoid| {
            monoid.path_index -= 1;
            monoid.segment_index -= 1;
            monoid.transform_index -= 1;
            monoid.style_index -= 1;
        }
    }

    pub fn getSegmentOffset(self: @This(), comptime T: type) u32 {
        return self.segment_offset - @sizeOf(T);
    }
};

pub const Offsets = packed struct {
    start: u32 = 0,
    end: u32 = 0,
};

pub const SegmentData = struct {
    segment_data: []const u8,

    pub fn getSegment(self: @This(), comptime T: type, path_monoid: PathMonoid) T {
        return std.mem.bytesToValue(T, self.segment_data[path_monoid.segment_offset - @sizeOf(T) .. path_monoid.segment_offset]);
    }
};

// Encodes all data needed for a single draw command to the GPU or CPU
// This may need to be a single buffer with a Config
pub const Encoding = struct {
    path_tags: []const PathTag,
    transforms: []const TransformF32.Affine,
    styles: []const Style,
    segment_data: []const u8,
    draw_data: []const u8,

    pub fn createFromBytes(bytes: []const u8) Encoding {
        _ = bytes;
        @panic("TODO: implement this for GPU kernels");
    }

    pub fn getSegment(self: @This(), comptime T: type, path_monoid: PathMonoid) T {
        return std.mem.bytesToValue(T, self.segment_data[path_monoid.segment_offset - @sizeOf(T) .. path_monoid.segment_offset]);
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
    staged_path: bool = false,
    staged_subpath: bool = false,
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
        std.debug.assert(self.styles.items.len > 0);

        var tag2 = tag;

        if (self.transforms.items.len == 0) {
            // need to make sure each segment has an associated transform, even if it's just the identity transform
            try self.encodeTransform(TransformF32.Affine.IDENTITY);
        }

        // TODO: all staged_ can be one staged property packed w/ bools
        if (self.staged_transform) {
            self.staged_transform = false;
            tag2.index.transform = 1;
        }

        if (self.staged_style) {
            self.staged_style = false;
            tag2.index.style = 1;
        }

        if (self.staged_path) {
            self.staged_path = false;
            tag2.index.path = 1;
        }


        if (self.staged_subpath) {
            self.staged_subpath = false;
            tag2.index.subpath = 1;
        }

        (try self.path_tags.addOne(self.allocator)).* = tag2;
    }

    pub fn currentTransform(self: *@This()) ?*TransformF32.Affine {
        if (self.transforms.items.len > 0) {
            return &self.transforms.items[self.transforms.items.len - 1];
        }

        return null;
    }

    pub fn encodeTransform(self: *@This(), affine: TransformF32.Affine) !void {
        if (self.currentTransform()) |current| {
            if (std.meta.eql(current.*, affine)) {
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

    pub fn extendPath(self: *@This(), comptime T: type, kind: ?PathTag.Kind) !*T {
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
        std.debug.assert(!self.staged_path);
        self.staged_path = true;
        const style = self.currentStyle().?;
        return PathEncoder(T).create(self, style.isFill());
    }
};

pub fn PathEncoder(comptime T: type) type {
    const PPoint = Point(T);

    // Extend structs used to extend an open subpath
    const ExtendLine = extern struct {
        const KIND: PathTag.Kind = switch (T) {
            f32 => .line_f32,
            i16 => .line_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
    };

    const ExtendArc = extern struct {
        const KIND: PathTag.Kind = switch (T) {
            f32 => .arc_f32,
            i16 => .arc_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
        p2: PPoint,
    };

    const ExtendQuadraticBezier = extern struct {
        const KIND: PathTag.Kind = switch (T) {
            f32 => .quadratic_bezier_f32,
            i16 => .quadratic_bezier_i16,
            else => @panic("Must provide f32 or i16 as type for PathEncoder\n"),
        };

        p1: PPoint,
        p2: PPoint,
    };

    const ExtendCubicBezier = extern struct {
        const KIND: PathTag.Kind = switch (T) {
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
        start_path_index: usize,
        start_offset: usize,
        is_fill: bool,
        state: State = .start,

        pub fn create(encoder: *Encoder, is_fill: bool) @This() {
            return @This(){
                .encoder = encoder,
                .is_fill = is_fill,
                .start_path_index = @intCast(encoder.path_tags.items.len),
                .start_offset = @intCast(encoder.segment_data.items.len),
            };
        }

        pub fn isEmpty(self: @This()) bool {
            return self.start_offset == self.encoder.segment_data.items.len;
        }

        pub fn finish(self: *@This()) !void {
            if (self.isEmpty() or self.state == .start) {
                return;
            }

            if (self.is_fill) {
                _ = try self.close();
            }
        }

        pub fn close(self: *@This()) !void {
            if (self.state != .draw or self.isEmpty()) {
                return;
            }

            if (self.is_fill) {
                if (self.encoder.currentPathTag()) |tag| {
                    // ensure filled subpaths are closed
                    const start_point = self.encoder.pathSegment(PPoint, self.start_offset).*;
                    const closed = try self.lineTo(start_point);

                    if (closed) {
                        self.encoder.path_tags.items[self.start_path_index].segment.cap = true;
                        tag.segment.cap = true;
                    }
                }
            }

            self.encoder.staged_subpath = false;
        }

        pub fn moveTo(self: *@This(), p0: PPoint) !void {
            switch (self.state) {
                .start => {
                    // add this move_to as a point to the end of the segments buffer
                    (try self.encoder.extendPath(PPoint, null)).* = p0;
                    self.encoder.staged_subpath = true;
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
                    const last_point = self.encoder.pathTailSegment(PPoint).*;

                    if (std.meta.eql(last_point, p1)) {
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
                    const last_point = self.encoder.pathTailSegment(PPoint).*;

                    if (std.meta.eql(last_point, p1) and std.meta.eql(last_point, p2)) {
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

        pub fn quadTo(self: *@This(), p1: PPoint, p2: PPoint) !bool {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p2);
                    return false;
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(PPoint).*;

                    if (std.meta.eql(last_point, p1) and std.meta.eql(last_point, p2)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendQuadraticBezier, ExtendQuadraticBezier.KIND)).* = ExtendQuadraticBezier{
                        .p1 = p1,
                        .p2 = p2,
                    };
                    self.state = .draw;
                    return true;
                },
            }
        }

        pub fn cubicTo(self: *@This(), p1: PPoint, p2: PPoint, p3: PPoint) !bool {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveTo(p3);
                    return false;
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(PPoint).*;

                    if (std.meta.eql(last_point, p1) and std.meta.eql(last_point, p2) and std.meta.eql(last_point, p3)) {
                        return false;
                    }

                    (try self.encoder.extendPath(ExtendCubicBezier, ExtendCubicBezier.KIND)).* = ExtendCubicBezier{
                        .p1 = p1,
                        .p2 = p2,
                        .p3 = p3,
                    };
                    self.state = .draw;
                    return true;
                },
            }
        }
    };
}

pub const CpuRasterizer = struct {
    const PathTagList = std.ArrayListUnmanaged(PathTag);
    const PathMonoidList = std.ArrayListUnmanaged(PathMonoid);
    const SegmentOffsetList = std.ArrayListUnmanaged(SegmentOffsets);
    const LineList = std.ArrayListUnmanaged(LineF32);
    const BoolList = std.ArrayListUnmanaged(bool);
    const Buffer = std.ArrayListUnmanaged(u8);
    const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
    const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);
    const MergeFragmentList = std.ArrayListUnmanaged(MergeFragment);
    const SpanList = std.ArrayListUnmanaged(Span);

    allocator: Allocator,
    config: KernelConfig,
    encoding: Encoding,
    path_monoids: PathMonoidList = PathMonoidList{},
    flat_segment_estimates: SegmentOffsetList = SegmentOffsetList{},
    flat_segment_offsets: SegmentOffsetList = SegmentOffsetList{},
    flat_segment_data: Buffer = Buffer{},
    grid_intersections: GridIntersectionList = GridIntersectionList{},
    boundary_fragments: BoundaryFragmentList = BoundaryFragmentList{},
    merge_fragments: MergeFragmentList = MergeFragmentList{},
    spans: SpanList = SpanList{},

    pub fn init(allocator: Allocator, config: KernelConfig, encoding: Encoding) @This() {
        return @This(){
            .allocator = allocator,
            .config = config,
            .encoding = encoding,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.path_monoids.deinit(self.allocator);
        self.flat_segment_estimates.deinit(self.allocator);
        self.flat_segment_offsets.deinit(self.allocator);
        self.flat_segment_data.deinit(self.allocator);
        self.grid_intersections.deinit(self.allocator);
        self.boundary_fragments.deinit(self.allocator);
        self.merge_fragments.deinit(self.allocator);
        self.spans.deinit(self.allocator);
    }

    pub fn reset(self: *@This()) void {
        self.path_monoids.items.len = 0;
        self.flat_segment_estimates.items.len = 0;
        self.flat_segment_offsets.items.len = 0;
        self.flat_segment_data.items.len = 0;
        self.grid_intersections.items.len = 0;
        self.boundary_fragments.items.len = 0;
        self.merge_fragments.items.len = 0;
        self.spans.items.len = 0;
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
        try self.estimateSegments();
        // allocate the FlatEncoder
        // use the FlatEncoder to flatten the encoding
        try self.flatten();
        // calculate scanline encoding
        try self.kernelRasterize();
    }

    fn expandPathMonoids(self: *@This()) !void {
        const path_monoids = try self.path_monoids.addManyAsSlice(self.allocator, self.encoding.path_tags.len);
        PathMonoid.expand(self.encoding.path_tags, path_monoids);
    }

    fn estimateSegments(self: *@This()) !void {
        const estimator = encoding_kernel.Estimate;
        const flat_segment_estimates = try self.flat_segment_estimates.addManyAsSlice(self.allocator, self.encoding.path_tags.len);
        const range = RangeU32{
            .start = 0,
            .end = @intCast(self.path_monoids.items.len),
        };
        var chunk_iter = range.chunkIterator(self.config.chunk_size);

        while (chunk_iter.next()) |chunk| {
            estimator.estimateSegments(
                self.config,
                self.encoding.path_tags,
                self.path_monoids.items,
                self.encoding.styles,
                self.encoding.transforms,
                self.encoding.segment_data,
                chunk,
                flat_segment_estimates,
            );
        }

        // TODO: expand SegmentEstimate into SegmentOffsets
        const flat_segment_offsets = try self.flat_segment_offsets.addManyAsSlice(self.allocator, flat_segment_estimates.len);
        SegmentOffsets.expand(flat_segment_estimates, flat_segment_offsets);
    }

    fn flatten(self: *@This()) !void {
        const flattener = encoding_kernel.Flatten;
        const last_segment_offsets = self.flat_segment_offsets.getLast();
        const flat_segment_data = try self.flat_segment_data.addManyAsSlice(
            self.allocator,
            last_segment_offsets.fill.lineOffset(),
        );

        const range = RangeU32{
            .start = 0,
            .end = @intCast(self.path_monoids.items.len),
        };
        var chunk_iter = range.chunkIterator(self.config.chunk_size);

        while (chunk_iter.next()) |chunk| {
            flattener.flatten(
                self.config,
                self.encoding.path_tags,
                self.path_monoids.items,
                self.encoding.styles,
                self.encoding.transforms,
                self.encoding.segment_data,
                chunk,
                self.flat_segment_estimates.items,
                self.flat_segment_offsets.items,
                flat_segment_data,
            );
        }
    }

    fn kernelRasterize(self: *@This()) !void {
        const rasterizer = encoding_kernel.Rasterize;
        const last_segment_offsets = self.flat_segment_offsets.getLast();
        const grid_intersections = try self.grid_intersections.addManyAsSlice(self.allocator, last_segment_offsets.fill.intersections);
        const boundary_fragments = try self.boundary_fragments.addManyAsSlice(self.allocator, last_segment_offsets.fill.intersections);
        const merge_fragments = try self.merge_fragments.addManyAsSlice(self.allocator, last_segment_offsets.fill.intersections);
        const spans = try self.spans.addManyAsSlice(self.allocator, last_segment_offsets.fill.intersections / 2 + 1);

        rasterizer.rasterize(
            self.config,
            self.encoding.path_tags,
            self.path_monoids.items,
            self.flat_segment_offsets.items,
            self.flat_segment_data.items,
            grid_intersections,
            boundary_fragments,
            merge_fragments,
            spans,
        );
    }

    pub fn debugPrint(self: @This()) void {
        std.debug.print("============ Path Monoids ============\n", .{});
        for (self.path_monoids.items) |path_monoid| {
            std.debug.print("{}\n", .{path_monoid});
        }
        std.debug.print("======================================\n", .{});

        std.debug.print("============ Path Segments ============\n", .{});
        for (self.encoding.path_tags, self.path_monoids.items, 0..) |path_tag, path_monoid, segment_index| {
            switch (path_tag.segment.kind) {
                .line_f32 => std.debug.print("LineF32: {}\n", .{
                    self.encoding.getSegment(core.LineF32, path_monoid),
                }),
                .arc_f32 => std.debug.print("ArcF32: {}\n", .{
                    self.encoding.getSegment(core.ArcF32, path_monoid),
                }),
                .quadratic_bezier_f32 => std.debug.print("QuadraticBezierF32: {}\n", .{
                    self.encoding.getSegment(core.QuadraticBezierF32, path_monoid),
                }),
                .cubic_bezier_f32 => std.debug.print("CubicBezierF32: {}\n", .{
                    self.encoding.getSegment(core.CubicBezierF32, path_monoid),
                }),
                .line_i16 => std.debug.print("LineI16: {}\n", .{
                    self.encoding.getSegment(core.LineI16, path_monoid),
                }),
                .arc_i16 => std.debug.print("ArcI16: {}\n", .{
                    self.encoding.getSegment(core.ArcI16, path_monoid),
                }),
                .quadratic_bezier_i16 => std.debug.print("QuadraticBezierI16: {}\n", .{
                    self.encoding.getSegment(core.QuadraticBezierI16, path_monoid),
                }),
                .cubic_bezier_i16 => std.debug.print("CubicBezierI16: {}\n", .{
                    self.encoding.getSegment(core.CubicBezierI16, path_monoid),
                }),
            }

            const estimate = self.flat_segment_estimates.items[segment_index];
            std.debug.print("Estimate: {}\n", .{estimate});
            const offset = self.flat_segment_offsets.items[segment_index];
            std.debug.print("Offset: {}\n", .{offset});
            std.debug.print("----------\n", .{});
        }
        std.debug.print("======================================\n", .{});
    }
};

test "encoding path monoids" {
    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.encodeColor(ColorU8{
        .r = 255,
        .g = 255,
        .b = 0,
        .a = 255,
    });
    var style = Style{};
    style.setFill(Style.Fill{
        .brush = .color,
    });
    style.setStroke(Style.Stroke{});
    try encoder.encodeStyle(style);

    var path_encoder = encoder.pathEncoder(f32);
    try path_encoder.moveTo(core.PointF32.create(1.0, 1.0));
    _ = try path_encoder.lineTo(core.PointF32.create(2.0, 2.0));
    _ = try path_encoder.arcTo(core.PointF32.create(3.0, 3.0), core.PointF32.create(4.0, 2.0));
    _ = try path_encoder.lineTo(core.PointF32.create(1.0, 1.0));
    try path_encoder.finish();

    var path_encoder2 = encoder.pathEncoder(i16);
    try path_encoder2.moveTo(core.PointI16.create(10, 10));
    _ = try path_encoder2.lineTo(core.PointI16.create(20, 20));
    _ = try path_encoder2.lineTo(core.PointI16.create(15, 30));
    _ = try path_encoder2.quadTo(core.PointI16.create(33, 44), core.PointI16.create(100, 100));
    _ = try path_encoder2.cubicTo(
        core.PointI16.create(120, 120),
        core.PointI16.create(70, 130),
        core.PointI16.create(22, 22),
    );
    try path_encoder2.finish();

    const encoding = encoder.encode();
    var rasterizer = CpuRasterizer.init(
        std.testing.allocator,
        encoding_kernel.KernelConfig.DEFAULT,
        encoding,
    );
    defer rasterizer.deinit();

    try rasterizer.rasterize();

    rasterizer.debugPrint();
    const path_monoids = rasterizer.path_monoids.items;

    try std.testing.expectEqualDeep(
        core.LineF32.create(core.PointF32.create(1.0, 1.0), core.PointF32.create(2.0, 2.0)),
        encoding.getSegment(core.LineF32, path_monoids[0]),
    );
    try std.testing.expectEqualDeep(
        core.ArcF32.create(
            core.PointF32.create(2.0, 2.0),
            core.PointF32.create(3.0, 3.0),
            core.PointF32.create(4.0, 2.0),
        ),
        encoding.getSegment(core.ArcF32, path_monoids[1]),
    );
    try std.testing.expectEqualDeep(
        core.LineF32.create(core.PointF32.create(4.0, 2.0), core.PointF32.create(1.0, 1.0)),
        encoding.getSegment(core.LineF32, path_monoids[2]),
    );

    try std.testing.expectEqualDeep(
        core.LineI16.create(core.PointI16.create(10, 10), core.PointI16.create(20, 20)),
        encoding.getSegment(core.LineI16, path_monoids[3]),
    );
}
