const std = @import("std");
const core = @import("../core/root.zig");
const text_module = @import("../text/root.zig");
const msaa_module = @import("./msaa.zig");
const texture_module = @import("./texture.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const HalfPlanesU16 = msaa_module.HalfPlanesU16;
const IntersectionF32 = core.IntersectionF32;
const TransformF32 = core.TransformF32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const PointI32 = core.PointI32;
const Point = core.Point;
const Line = core.Line;
const Arc = core.Arc;
const QuadraticBezier = core.QuadraticBezier;
const CubicBezier = core.CubicBezier;
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const PointU32 = core.PointU32;
const PointI16 = core.PointI16;
const LineF32 = core.LineF32;
const LineI16 = core.LineI16;
const ArcF32 = core.ArcF32;
const ArcI16 = core.ArcI16;
const QuadraticBezierF32 = core.QuadraticBezierF32;
const QuadraticBezierI16 = core.QuadraticBezierI16;
const CubicBezierF32 = core.CubicBezierF32;
const CubicBezierI16 = core.CubicBezierI16;
const GlyphPen = text_module.GlyphPen;
const Texture = texture_module.Texture;
const Colors = texture_module.Colors;
const ColorF32 = texture_module.ColorF32;
const ColorU8 = texture_module.ColorU8;
const ColorBlend = texture_module.ColorBlend;

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
        // marks final segment in a subpath
        subpath_end: bool = false,

        pub fn size(self: @This()) u32 {
            switch (self.kind) {
                .line_i16 => return @sizeOf(LineI16),
                .line_f32 => return @sizeOf(LineF32),
                .arc_i16 => return @sizeOf(ArcI16),
                .arc_f32 => return @sizeOf(ArcF32),
                .quadratic_bezier_i16 => return @sizeOf(QuadraticBezierI16),
                .quadratic_bezier_f32 => return @sizeOf(QuadraticBezierF32),
                .cubic_bezier_i16 => return @sizeOf(CubicBezierI16),
                .cubic_bezier_f32 => return @sizeOf(CubicBezierF32),
            }
        }

        pub fn pointSize(self: @This()) u32 {
            switch (self.kind) {
                .line_i16 => return @sizeOf(PointI16),
                .line_f32 => return @sizeOf(PointF32),
                .arc_i16 => return @sizeOf(PointI16),
                .arc_f32 => return @sizeOf(PointF32),
                .quadratic_bezier_i16 => return @sizeOf(PointI16),
                .quadratic_bezier_f32 => return @sizeOf(PointF32),
                .cubic_bezier_i16 => return @sizeOf(PointI16),
                .cubic_bezier_f32 => return @sizeOf(PointF32),
            }
        }

        pub fn extendSize(self: @This()) u32 {
            switch (self.kind) {
                .line_i16 => return @sizeOf(LineI16) - @sizeOf(PointI16),
                .line_f32 => return @sizeOf(LineF32) - @sizeOf(PointF32),
                .arc_i16 => return @sizeOf(ArcI16) - @sizeOf(PointI16),
                .arc_f32 => return @sizeOf(ArcF32) - @sizeOf(PointF32),
                .quadratic_bezier_i16 => return @sizeOf(QuadraticBezierI16) - @sizeOf(PointI16),
                .quadratic_bezier_f32 => return @sizeOf(QuadraticBezierF32) - @sizeOf(PointF32),
                .cubic_bezier_i16 => return @sizeOf(CubicBezierI16) - @sizeOf(PointI16),
                .cubic_bezier_f32 => return @sizeOf(CubicBezierF32) - @sizeOf(PointF32),
            }
        }
    };

    pub const Index = packed struct {
        // increments path index by 1 or 0
        // set to 1 for the start of a new path
        // 1-based indexing
        path: u1 = 0,
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

    pub fn isArc(self: @This()) bool {
        return self.segment.kind == .arc_f32 or self.segment.kind == .arc_i16;
    }
};

pub const Style = packed struct {
    comptime {
        std.debug.assert(@sizeOf(Style) <= 32);
    }

    pub const Brush = enum(u3) {
        noop = 0,
        color = 1,

        pub fn offset(self: @This()) u32 {
            return switch (self) {
                .noop => 0,
                .color => @sizeOf(ColorU8),
            };
        }
    };

    pub const FillRule = enum(u1) {
        non_zero = 0,
        even_odd = 1,
    };

    pub const Fill = packed struct {
        rule: FillRule = .non_zero,
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
        return self.flags.fill and self.fill.brush != .noop;
    }

    pub fn isStroke(self: @This()) bool {
        return self.flags.stroke and self.stroke.brush != .noop;
    }
};

pub const BumpAllocator = struct {
    start: u32 = 0,
    end: u32 = 0,
    offset: *std.atomic.Value(u32),

    pub fn bump(self: @This(), n: u32) u32 {
        const next_offset = self.start + self.offset.fetchAdd(n, .acq_rel);
        if (next_offset > self.end) {
            @panic("Bump allocator exceeded bounds.");
        }

        return next_offset;
    }
};

pub fn MonoidFunctions(comptime T: type, comptime M: type) type {
    return struct {
        pub fn expand(tags: []const T, expanded: []M) void {
            std.debug.assert(tags.len > 0);
            std.debug.assert(tags.len == expanded.len);

            var monoid = M.createTag(tags[0]);
            expanded[0] = monoid;
            for (tags[1..], expanded[1..]) |tag, *expanded_monoid| {
                monoid = monoid.combine(M.createTag(tag));
                expanded_monoid.* = monoid;
            }

            if (std.meta.hasFn(M, "reexpand")) {
                M.reexpand(expanded);
            }
        }

        pub fn reduce(tags: []const T) M {
            std.debug.assert(tags.len > 0);

            var monoid = M.createTag(tags[0]);
            for (tags[1..]) |tag| {
                monoid = monoid.combine(M.createTag(tag));
            }

            return monoid;
        }
    };
}

pub const PathMonoid = extern struct {
    path_index: u32 = 0,
    subpath_index: u32 = 0,
    segment_index: u32 = 0,
    segment_offset: u32 = 0,
    transform_index: i32 = 0,
    style_index: i32 = 0,
    brush_offset: u32 = 0,

    pub usingnamespace MonoidFunctions(PathTag, @This());

    pub fn createTag(tag: PathTag) @This() {
        // extend size of the segment offset
        var segment_offset = tag.segment.extendSize();
        // 1 point because the subpath end is not an extension
        // 1 point for the first point of the next subpath
        segment_offset += @as(u32, @intFromBool(tag.segment.subpath_end)) * tag.segment.pointSize() * 2;

        return @This(){
            .path_index = @intCast(tag.index.path),
            .subpath_index = @as(u32, @intFromBool(tag.segment.subpath_end)),
            .segment_index = 1,
            .segment_offset = segment_offset,
            .transform_index = @intCast(tag.index.transform),
            .style_index = @intCast(tag.index.style),
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

    pub fn calculate(self: @This(), path_tag: PathTag) @This() {
        var path_monoid = self;
        path_monoid.path_index -= 1;
        path_monoid.segment_index -= 1;
        path_monoid.style_index -= 1;
        path_monoid.transform_index -= 1;
        // TODO: should support PointI16 too
        path_monoid.segment_offset += @sizeOf(PointF32); // add 1 for the first subpath
        path_monoid.segment_offset -= path_tag.segment.size();
        path_monoid.segment_offset -= @as(u32, @intFromBool(path_tag.segment.subpath_end)) * @sizeOf(PointF32);

        return path_monoid;
    }
};

pub const SegmentMeta = struct {
    segment_index: u32,
    path_tag: PathTag,
    path_monoid: PathMonoid,
};

pub const SegmentData = struct {
    segment_data: []const u8,

    pub fn getSegment(self: @This(), comptime T: type, path_monoid: PathMonoid) T {
        return std.mem.bytesToValue(T, self.segment_data[path_monoid.segment_offset - @sizeOf(T) .. path_monoid.segment_offset]);
    }

    pub fn getSegmentOffset(self: @This(), comptime T: type, offset: u32) T {
        return std.mem.bytesToValue(T, self.segment_data[offset .. offset + @sizeOf(T)]);
    }
};

// Encodes all data needed for a single draw command to the GPU or CPU
// This may need to be a single buffer with a Config
pub const Encoding = struct {
    path_offsets: []const u32,
    path_tags: []const PathTag,
    transforms: []const TransformF32.Affine,
    styles: []const Style,
    segment_data: []const u8,
    draw_data: []const u8,

    pub fn calculateBounds(self: @This()) RectF32 {
        var bounds = RectF32.NONE;
        var next_path_monoid = PathMonoid{};

        for (self.path_tags) |path_tag| {
            next_path_monoid = next_path_monoid.combine(PathMonoid.createTag(path_tag));
            const path_monoid = next_path_monoid.calculate(path_tag);
            const transform = self.getTransform(path_monoid.transform_index);

            switch (path_tag.segment.kind) {
                .line_f32 => {
                    const s = self.getSegment(LineF32, path_monoid).affineTransform(transform);
                    bounds.extendByInPlace(s.p0);
                    bounds.extendByInPlace(s.p1);
                },
                .line_i16 => {
                    const s = self.getSegment(LineI16, path_monoid).cast(f32).affineTransform(transform);
                    bounds.extendByInPlace(s.p0);
                    bounds.extendByInPlace(s.p1);
                },
                .arc_f32 => {
                    const s = self.getSegment(ArcF32, path_monoid).affineTransform(transform);
                    bounds.extendByInPlace(s.p0);
                    bounds.extendByInPlace(s.p1);
                    bounds.extendByInPlace(s.p2);
                },
                .arc_i16 => {
                    const s = self.getSegment(ArcI16, path_monoid).cast(f32).affineTransform(transform);
                    bounds.extendByInPlace(s.p0);
                    bounds.extendByInPlace(s.p1);
                    bounds.extendByInPlace(s.p2);
                },
                .quadratic_bezier_f32 => {
                    const s = self.getSegment(QuadraticBezierF32, path_monoid).affineTransform(transform);
                    bounds.extendByInPlace(s.p0);
                    bounds.extendByInPlace(s.p1);
                    bounds.extendByInPlace(s.p2);
                },
                .quadratic_bezier_i16 => {
                    const s = self.getSegment(QuadraticBezierI16, path_monoid).cast(f32).affineTransform(transform);
                    bounds.extendByInPlace(s.p0);
                    bounds.extendByInPlace(s.p1);
                    bounds.extendByInPlace(s.p2);
                },
                .cubic_bezier_f32 => {
                    const s = self.getSegment(CubicBezierF32, path_monoid).affineTransform(transform);
                    bounds.extendByInPlace(s.p0);
                    bounds.extendByInPlace(s.p1);
                    bounds.extendByInPlace(s.p2);
                    bounds.extendByInPlace(s.p3);
                },
                .cubic_bezier_i16 => {
                    const s = self.getSegment(CubicBezierI16, path_monoid).cast(f32).affineTransform(transform);
                    bounds.extendByInPlace(s.p0);
                    bounds.extendByInPlace(s.p1);
                    bounds.extendByInPlace(s.p2);
                    bounds.extendByInPlace(s.p3);
                },
            }
        }

        return bounds;
    }

    pub fn createFromBytes(bytes: []const u8) Encoding {
        _ = bytes;
        @panic("TODO: implement this for GPU kernels");
    }

    pub fn getSegment(self: @This(), comptime T: type, path_monoid: PathMonoid) T {
        return std.mem.bytesToValue(T, self.segment_data[path_monoid.segment_offset .. path_monoid.segment_offset + @sizeOf(T)]);
    }

    pub fn getStyle(self: @This(), style_index: i32) Style {
        if (self.styles.len > 0 and style_index >= 0) {
            return self.styles[@intCast(style_index)];
        }

        return Style{};
    }

    pub fn getTransform(self: @This(), transform_index: i32) TransformF32.Affine {
        if (self.transforms.len > 0 and transform_index >= 0) {
            return self.transforms[@intCast(transform_index)];
        }

        return TransformF32.Affine.IDENTITY;
    }

    pub fn copyAlloc(self: @This(), allocator: Allocator) !@This() {
        return @This(){
            .path_tags = try allocator.dupe(PathTag, self.path_tags),
            .transforms = try allocator.dupe(TransformF32.Affine, self.transforms),
            .styles = try allocator.dupe(Style, self.styles),
            .segment_data = try allocator.dupe(u8, self.segment_data),
            .draw_data = try allocator.dupe(u8, self.draw_data),
        };
    }
};

// This encoding can get sent to kernels
pub const Encoder = struct {
    pub const StageFlags = struct {
        path: bool = false,
        transform: bool = false,
        style: bool = false,
        draw: u16 = 0,
    };

    const PathTagList = std.ArrayListUnmanaged(PathTag);
    const AffineList = std.ArrayListUnmanaged(TransformF32.Affine);
    const StyleList = std.ArrayListUnmanaged(Style);
    const Buffer = std.ArrayListUnmanaged(u8);
    const OffsetList = std.ArrayListUnmanaged(u32);

    allocator: Allocator,
    bounds: RectF32 = RectF32.NONE,
    path_offsets: OffsetList = OffsetList{},
    path_tags: PathTagList = PathTagList{},
    transforms: AffineList = AffineList{},
    styles: StyleList = StyleList{},
    segment_data: Buffer = Buffer{},
    draw_data: Buffer = Buffer{},
    staged: StageFlags = StageFlags{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.path_offsets.deinit(self.allocator);
        self.path_tags.deinit(self.allocator);
        self.transforms.deinit(self.allocator);
        self.styles.deinit(self.allocator);
        self.segment_data.deinit(self.allocator);
        self.draw_data.deinit(self.allocator);
    }

    pub fn reset(self: *@This()) void {
        self.path_offsets.items.len = 0;
        self.path_tags.items.len = 0;
        self.transforms.items.len = 0;
        self.styles.items.len = 0;
        self.segment_data.items.len = 0;
        self.draw_data.items.len = 0;
    }

    pub fn encode(self: @This()) Encoding {
        return Encoding{
            .path_offsets = self.path_offsets.items,
            .path_tags = self.path_tags.items,
            .transforms = self.transforms.items,
            .styles = self.styles.items,
            .segment_data = self.segment_data.items,
            .draw_data = self.draw_data.items,
        };
    }

    pub fn encodeStaged(self: *@This(), tag: PathTag) PathTag {
        var tag2 = tag;

        if (self.staged.path) {
            self.staged.path = false;
            tag2.index.path = 1;
        }

        if (self.staged.style) {
            self.staged.style = false;
            self.staged.draw = 0;
            tag2.index.style = 1;
        }

        if (self.staged.transform) {
            self.staged.transform = false;
            tag2.index.transform = 1;
        }

        return tag2;
    }

    pub fn unstage(self: *@This()) void {
        self.staged.path = false;

        self.draw_data.items.len -= self.staged.draw;
        self.staged.style = false;
        self.staged.draw = 0;

        self.staged.transform = false;
    }

    pub fn calculateBounds(self: @This()) RectF32 {
        return self.encode().calculateBounds();
    }

    pub fn currentPathTag(self: *@This()) ?*PathTag {
        if (self.path_tags.items.len > 0) {
            return &self.path_tags.items[self.path_tags.items.len - 1];
        }

        return null;
    }

    pub fn encodePathTag(self: *@This(), tag: PathTag) !void {
        const tag2 = self.encodeStaged(tag);
        if (tag2.index.path == 1) {
            (try self.path_offsets.addOne(self.allocator)).* = 1;
        } else {
            self.path_offsets.items[self.path_offsets.items.len - 1] += 1;
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
            } else if (self.staged.transform) {
                current.* = affine;
            }
        }

        (try self.transforms.addOne(self.allocator)).* = affine;
        self.staged.transform = true;
    }

    pub fn currentStyle(self: *@This()) ?*Style {
        if (self.styles.items.len > 0) {
            return &self.styles.items[self.styles.items.len - 1];
        }

        return null;
    }

    pub fn encodeStyle(self: *@This(), style: Style) !void {
        if (self.currentStyle()) |current| {
            if (self.staged.style) {
                current.* = style;
            }
        }

        (try self.styles.addOne(self.allocator)).* = style;
        self.staged.style = true;
    }

    pub fn extendPath(self: *@This(), comptime T: type, kind: ?PathTag.Kind) !*T {
        const bytes = try self.extendPathBytes(kind, @sizeOf(T));
        return @alignCast(@ptrCast(bytes.ptr));
    }

    pub fn extendPathBytes(self: *@This(), kind: ?PathTag.Kind, n: u32) ![]u8 {
        if (kind) |k| {
            try self.encodePathTag(PathTag.curve(k));
        }

        return try self.segment_data.addManyAsSlice(self.allocator, n);
    }

    pub fn dropPath(self: *@This(), comptime T: type) void {
        if (self.segment_data.items.len >= @sizeOf(T)) {
            self.segment_data.items.len -= @sizeOf(T);
        }
    }

    pub fn pathSegment(self: *@This(), comptime T: type, offset: usize) ?*T {
        if (offset + @sizeOf(T) > self.segment_data.items.len) {
            return null;
        }

        return @alignCast(std.mem.bytesAsValue(T, self.segment_data.items[offset .. offset + @sizeOf(T)]));
    }

    pub fn pathTailSegment(self: *@This(), comptime T: type) ?*T {
        if (self.segment_data.items.len < @sizeOf(T)) {
            return null;
        }

        return @alignCast(std.mem.bytesAsValue(T, self.segment_data.items[self.segment_data.items.len - @sizeOf(T) ..]));
    }

    pub fn encodeColor(self: *@This(), color: ColorU8) !void {
        // need to allow encoding color w/ style to avoid errors
        const bytes = (try self.draw_data.addManyAsSlice(self.allocator, @sizeOf(ColorU8)));
        std.mem.bytesAsValue(ColorU8, bytes).* = color;
        self.staged.draw += @sizeOf(ColorU8);
    }

    pub fn pathEncoder(self: *@This(), comptime T: type) PathEncoder(T) {
        std.debug.assert(!self.staged.path);
        self.staged.path = true;
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
        const Self = @This();

        encoder: *Encoder,
        start_path_offset: usize,
        start_subpath_index: usize,
        start_subpath_offset: usize,
        is_fill: bool,
        state: State = .start,

        pub fn create(encoder: *Encoder, is_fill: bool) @This() {
            return @This(){
                .encoder = encoder,
                .is_fill = is_fill,
                .start_path_offset = @intCast(encoder.segment_data.items.len),
                .start_subpath_index = @intCast(encoder.path_tags.items.len),
                .start_subpath_offset = @intCast(encoder.segment_data.items.len),
            };
        }

        pub fn isEmpty(self: @This()) bool {
            return self.start_path_offset == self.encoder.segment_data.items.len;
        }

        pub fn finish(self: *@This()) !void {
            switch (self.state) {
                .start => {
                    // do nothing, there is no data written that needs to be reversed
                },
                .move_to => {
                    // unwind the move_to point
                    self.encoder.dropPath(PPoint);
                },
                .draw => {
                    // finish the current subpath being drawn
                    try self.finishSubpath();
                },
            }

            self.encoder.unstage();
        }

        pub fn currentPoint(self: @This()) PPoint {
            if (self.lastPoint()) |point| {
                return point;
            }

            return PPoint{};
        }

        pub fn lastPoint(self: @This()) ?PPoint {
            if (self.state == .start) {
                return null;
            }

            const point = self.encoder.pathTailSegment(PPoint) orelse return null;
            return point.*;
        }

        pub fn affineTransform(self: *@This(), transform: TransformF32.Affine) void {
            const points = std.mem.bytesAsSlice(PPoint, self.encoder.segment_data.items[self.start_path_offset..]);

            switch (T) {
                f32 => {
                    for (points) |*point| {
                        point.* = point.affineTransform(transform);
                    }
                },
                i16 => {
                    for (points) |*point| {
                        point.* = point.cast(f32).affineTransform(transform).cast(T);
                    }
                },
                else => unreachable,
            }
        }

        pub fn finishSubpath(self: *@This()) !void {
            std.debug.assert(self.state == .draw);

            // SAFETY: if we are in draw, there is a start/end point
            const start_point = self.encoder.pathSegment(PPoint, self.start_subpath_offset).?.*;
            const end_point = self.encoder.pathTailSegment(PPoint).?.*;
            const is_closed = std.meta.eql(start_point, end_point);

            if (self.encoder.currentPathTag()) |path_tag| {
                try self.writeLastSegment();

                if (!is_closed) {
                    // write the first segment at the end
                    // cap the first path_tag in the subpath
                    self.encoder.path_tags.items[self.start_subpath_index].segment.cap = true;
                    // cap the last drawn segment of the subpath
                    path_tag.segment.cap = true;
                }
            }

            self.start_subpath_index = self.encoder.path_tags.items.len;
            self.start_subpath_offset = self.encoder.segment_data.items.len;
        }

        pub fn writeLastSegment(self: *@This()) !void {
            const first_path_tag = self.encoder.path_tags.items[self.start_subpath_index];
            const segment_size = first_path_tag.segment.size();
            const extend_bytes = try self.encoder.extendPathBytes(first_path_tag.segment.kind, segment_size);
            const bytes = self.encoder.segment_data.items[self.start_subpath_offset .. self.start_subpath_offset + segment_size];
            std.mem.copyForwards(u8, extend_bytes, bytes);
            // mark end of subpath on the line we just wrote
            self.encoder.currentPathTag().?.segment.subpath_end = true;
        }

        pub fn moveTo(self: *@This(), x: T, y: T) !void {
            try self.moveToPoint(PPoint.create(x, y));
        }

        pub fn moveToPoint(self: *@This(), p0: PPoint) !void {
            switch (self.state) {
                .start => {
                    // add this move_to as a point to the end of the segments buffer
                    (try self.encoder.extendPath(PPoint, null)).* = p0;
                    self.state = .move_to;
                },
                .move_to => {
                    // update the current cursors position
                    // SAFETY: we only get to the state after pushing a point
                    self.encoder.pathTailSegment(PPoint).?.* = p0;
                },
                .draw => {
                    try self.finishSubpath();
                    (try self.encoder.extendPath(PPoint, null)).* = p0;
                    self.state = .move_to;
                },
            }
        }

        pub fn close(self: *@This()) !void {
            switch (self.state) {
                .start => {
                    return; // do nothing
                },
                .move_to => {
                    return; // do nothing
                },
                .draw => {
                    // SAFETY: we are in draw state
                    const first_point = self.encoder.pathSegment(PPoint, self.start_subpath_offset).?.*;
                    const last_point = self.lastPoint().?;

                    if (!std.meta.eql(first_point, last_point)) {
                        try self.lineToPoint(first_point);
                    }
                },
            }
        }

        pub fn lineTo(self: *@This(), x1: T, y1: T) !void {
            try self.lineToPoint(PPoint.create(x1, y1));
        }

        pub fn lineToPoint(self: *@This(), p1: PPoint) Allocator.Error!void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveToPoint(p1);
                },
                else => {
                    // SAFETY: we are not in start state, so we have written at least one point
                    const last_point = self.encoder.pathTailSegment(PPoint).?.*;

                    if (std.meta.eql(last_point, p1)) {
                        return;
                    }

                    (try self.encoder.extendPath(ExtendLine, ExtendLine.KIND)).* = ExtendLine{
                        .p1 = p1,
                    };
                    self.state = .draw;
                },
            }
        }

        pub fn arcTo(self: *@This(), x1: T, y1: T, x2: T, y2: T) !void {
            try self.arcToPoint(PPoint.create(x1, y1), PPoint.create(x2, y2));
        }

        pub fn arcToPoint(self: *@This(), p1: PPoint, p2: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveToPoint(p2);
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(PPoint).*;

                    if (std.meta.eql(last_point, p1) and std.meta.eql(last_point, p2)) {
                        return;
                    }

                    (try self.encoder.extendPath(ExtendArc, ExtendArc.KIND)).* = ExtendArc{
                        .p1 = p1,
                        .p2 = p2,
                    };
                    self.state = .draw;
                },
            }
        }

        pub fn quadTo(self: *@This(), x1: T, y1: T, x2: T, y2: T) !void {
            try self.quadToPoint(PPoint.create(x1, y1), PPoint.create(x2, y2));
        }

        pub fn quadToPoint(self: *@This(), p1: PPoint, p2: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveToPoint(p2);
                },
                else => {
                    // SAFETY: we are not in start state, so we must have written at least one point
                    const last_point = self.encoder.pathTailSegment(PPoint).?.*;

                    if (std.meta.eql(last_point, p1) and std.meta.eql(last_point, p2)) {
                        return;
                    }

                    (try self.encoder.extendPath(ExtendQuadraticBezier, ExtendQuadraticBezier.KIND)).* = ExtendQuadraticBezier{
                        .p1 = p1,
                        .p2 = p2,
                    };
                    self.state = .draw;
                },
            }
        }

        pub fn cubicTo(self: *@This(), x1: T, y1: T, x2: T, y2: T, x3: T, y3: T) !void {
            try self.cubicToPoint(PPoint.create(x1, y1), PPoint.create(x2, y2), PPoint.create(x3, y3));
        }

        pub fn cubicToPoint(self: *@This(), p1: PPoint, p2: PPoint, p3: PPoint) !void {
            switch (self.state) {
                .start => {
                    // just treat this as a moveTo
                    try self.moveToPoint(p3);
                },
                else => {
                    const last_point = self.encoder.pathTailSegment(PPoint).?.*;

                    if (std.meta.eql(last_point, p1) and std.meta.eql(last_point, p2) and std.meta.eql(last_point, p3)) {
                        return;
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

        pub fn glyphPen(self: *@This()) GlyphPen {
            return GlyphPen{
                .ptr = @ptrCast(self),
                .vtable = GlyphPenVTable,
            };
        }

        const GlyphPenVTable: *const GlyphPen.VTable = &.{
            .moveTo = GlyphPenFunctions.moveTo,
            .lineTo = GlyphPenFunctions.lineTo,
            .quadTo = GlyphPenFunctions.quadTo,
            .curveTo = GlyphPenFunctions.curveTo,
            .open = GlyphPenFunctions.open,
            .close = GlyphPenFunctions.close,
        };

        pub const GlyphPenFunctions = struct {
            fn moveTo(ctx: *anyopaque, point: PointF32) void {
                var b = @as(*Self, @alignCast(@ptrCast(ctx)));
                b.moveToPoint(point) catch {
                    unreachable;
                };
            }

            fn lineTo(ctx: *anyopaque, p1: PointF32) void {
                var b = @as(*Self, @alignCast(@ptrCast(ctx)));
                b.lineToPoint(p1) catch {
                    unreachable;
                };
            }

            fn quadTo(ctx: *anyopaque, p1: PointF32, p2: PointF32) void {
                var b = @as(*Self, @alignCast(@ptrCast(ctx)));
                _ = b.quadToPoint(p1, p2) catch {
                    unreachable;
                };
            }

            fn curveTo(_: *anyopaque, _: PointF32, _: PointF32, _: PointF32) void {
                @panic("PathBuilder does not support curveTo\n");
            }

            fn open(_: *anyopaque) void {
                // do nothing
            }

            fn close(ctx: *anyopaque, bounds: RectF32, ppem: f32) void {
                var b = @as(*Self, @alignCast(@ptrCast(ctx)));
                b.finish() catch @panic("could not finish PathBuilder");

                const scale = (TransformF32{
                    .scale = PointF32{
                        .x = ppem,
                        .y = ppem,
                    },
                }).toAffine();
                const translate_origin = (TransformF32{
                    .translate = PointF32{
                        .x = -bounds.min.x,
                        .y = -bounds.min.y,
                    },
                }).toAffine();
                const t1 = scale.mul(translate_origin);
                const bounds2 = bounds.affineTransform(t1);

                const invert_y = (TransformF32{
                    .scale = PointF32{
                        .x = 1.0,
                        .y = -1.0,
                    },
                }).toAffine();
                const translate_center = (TransformF32{
                    .translate = PointF32{
                        .x = -(bounds2.getWidth() / 2.0),
                        .y = -(bounds2.getHeight() / 2.0),
                    },
                }).toAffine();
                const t2 = invert_y.mul(translate_center).mul(t1);

                b.affineTransform(t2);
            }
        };
    };
}

pub const PathEncoderF32 = PathEncoder(f32);
pub const PathEncoderI16 = PathEncoder(i16);

pub const EncodingCache = struct {
    const EncodingList = std.ArrayListUnmanaged(Encoding);

    arena: std.heap.ArenaAllocator,
    encodings: EncodingList = EncodingList{},

    pub fn init(allocator: Allocator) @This() {
        return @This(){
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
    }

    pub fn reset(self: *@This()) void {
        self.arena.reset(.retain_capacity);
    }

    pub fn addEncoding(self: *@This(), encoding: Encoding) !void {
        (try self.encodings.addOne(self.arena.allocator())).* = try encoding.copyAlloc(self.arena.allocator());
    }
};

pub const AtomicBounds = struct {
    const V = std.atomic.Value(u32);

    min_x: V = V.init(@bitCast(std.math.floatMax(f32))),
    min_y: V = V.init(@bitCast(std.math.floatMax(f32))),
    max_x: V = V.init(@bitCast(std.math.floatMin(f32))),
    max_y: V = V.init(@bitCast(std.math.floatMin(f32))),

    pub fn createRect(rect: *RectF32) *AtomicBounds {
        return std.mem.bytesAsValue(AtomicBounds, std.mem.asBytes(rect));
    }

    pub fn extendBy(self: *@This(), bounds: RectF32) void {
        atomicMin(&self.min_x, bounds.min.x);
        atomicMin(&self.min_y, bounds.min.y);
        atomicMax(&self.max_x, bounds.max.x);
        atomicMax(&self.max_y, bounds.max.y);
    }

    pub fn atomicMin(x: *V, y: f32) void {
        var cur: u32 = x.load(.seq_cst);
        while (true) {
            const min = @min(@as(f32, @bitCast(cur)), y);
            cur = x.cmpxchgWeak(cur, @bitCast(min), .seq_cst, .seq_cst) orelse return;
        }
    }

    pub fn atomicMax(x: *V, y: f32) void {
        var cur: u32 = x.load(.seq_cst);
        while (true) {
            const max = @max(@as(f32, @bitCast(cur)), y);
            cur = x.cmpxchgWeak(cur, @bitCast(max), .seq_cst, .seq_cst) orelse return;
        }
    }
};

pub const Path = struct {
    pub const Bump = std.atomic.Value(u32);

    segment_index: u32 = 0,
    bounds: RectF32 = RectF32{},
    line_offset: PathOffset = PathOffset{},
    boundary_offset: PathOffset = PathOffset{},
    fill_bump: Bump = Bump{ .raw = 0 },
    stroke_bump: Bump = Bump{ .raw = 0 },

    pub fn assertLineAllocations(self: @This()) bool {
        std.debug.assert(self.line_offset.end_fill_offset - self.line_offset.start_fill_offset == self.fill_bump.raw);
        std.debug.assert(self.line_offset.end_stroke_offset - self.line_offset.start_stroke_offset == self.stroke_bump.raw);

        return true;
    }
};

pub const PathOffset = struct {
    start_fill_offset: u32 = 0,
    end_fill_offset: u32 = 0,
    start_stroke_offset: u32 = 0,
    end_stroke_offset: u32 = 0,

    pub fn lineOffset(
        path_index: u32,
        segment_offsets: []const SegmentOffset,
        paths: []const Path,
    ) @This() {
        const path = paths[path_index];
        const start_path_segment_offset = if (path.segment_index > 0) segment_offsets[path.segment_index - 1] else SegmentOffset{};
        var end_path_segment_offset: SegmentOffset = undefined;
        if (path_index + 1 < paths.len) {
            end_path_segment_offset = segment_offsets[paths[path_index + 1].segment_index - 1];
        } else {
            end_path_segment_offset = segment_offsets[segment_offsets.len - 1];
        }

        const start_fill_offset = start_path_segment_offset.fill_offset + start_path_segment_offset.stroke_offset;
        const end_fill_offset = end_path_segment_offset.fill_offset + start_path_segment_offset.stroke_offset;

        const start_stroke_offset = end_fill_offset;
        const end_stroke_offset = end_path_segment_offset.fill_offset + end_path_segment_offset.stroke_offset;

        return @This(){
            .start_fill_offset = start_fill_offset,
            .end_fill_offset = end_fill_offset,
            .start_stroke_offset = start_stroke_offset,
            .end_stroke_offset = end_stroke_offset,
        };
    }

    pub fn lineToBoundaryOffset(
        line_offset: @This(),
        intersection_offsets: []const IntersectionOffset,
    ) @This() {
        const intersection_offset = lineToIntersectionOffset(line_offset, intersection_offsets);

        // subtract one for each line from the intersection offset to get the boundary offset
        return @This(){
            .start_fill_offset = intersection_offset.start_fill_offset - line_offset.start_fill_offset,
            .end_fill_offset = intersection_offset.end_fill_offset - line_offset.end_fill_offset,
            .start_stroke_offset = intersection_offset.start_stroke_offset - line_offset.start_stroke_offset,
            .end_stroke_offset = intersection_offset.end_stroke_offset - line_offset.end_stroke_offset,
        };
    }

    pub fn lineToIntersectionOffset(
        line_offset: @This(),
        intersection_offsets: []const IntersectionOffset,
    ) @This() {
        const start_fill_offset = if (line_offset.start_fill_offset > 0) intersection_offsets[line_offset.start_fill_offset - 1].offset else 0;
        const end_fill_offset = if (line_offset.end_fill_offset > 0) intersection_offsets[line_offset.end_fill_offset - 1].offset else 0;

        const start_stroke_offset = if (line_offset.start_stroke_offset > 0) intersection_offsets[line_offset.start_stroke_offset - 1].offset else 0;
        const end_stroke_offset = if (line_offset.end_stroke_offset > 0) intersection_offsets[line_offset.end_stroke_offset - 1].offset else 0;

        return @This(){
            .start_fill_offset = start_fill_offset,
            .end_fill_offset = end_fill_offset,
            .start_stroke_offset = start_stroke_offset,
            .end_stroke_offset = end_stroke_offset,
        };
    }

    pub fn styleOffset(
        style_index: u32,
        style_offsets: []const SegmentOffset,
    ) @This() {
        const start_style_offset = if (style_index > 0) style_offsets[style_index - 1] else SegmentOffset{};
        const end_style_offset = style_offsets[style_index];

        const start_fill_offset = start_style_offset.fill_offset + start_style_offset.stroke_offset;
        const end_fill_offset = end_style_offset.fill_offset + start_style_offset.stroke_offset;

        const start_stroke_offset = end_fill_offset;
        const end_stroke_offset = end_style_offset.fill_offset + end_style_offset.stroke_offset;

        return @This(){
            .start_fill_offset = start_fill_offset,
            .end_fill_offset = end_fill_offset,
            .start_stroke_offset = start_stroke_offset,
            .end_stroke_offset = end_stroke_offset,
        };
    }
};

pub const SegmentOffset = struct {
    fill_offset: u32 = 0,
    stroke_offset: u32 = 0,

    pub usingnamespace MonoidFunctions(SegmentOffset, @This());

    pub fn createTag(tag: SegmentOffset) @This() {
        return tag;
    }

    pub fn combine(self: @This(), other: @This()) @This() {
        return @This(){
            .fill_offset = self.fill_offset + other.fill_offset,
            .stroke_offset = self.stroke_offset + other.stroke_offset,
        };
    }
};

pub const IntersectionOffset = struct {
    offset: u32 = 0,

    pub usingnamespace MonoidFunctions(IntersectionOffset, @This());

    pub fn createTag(tag: IntersectionOffset) @This() {
        return tag;
    }

    pub fn combine(self: @This(), other: @This()) @This() {
        return @This(){
            .offset = self.offset + other.offset,
        };
    }
};

pub const FlatSegment = struct {
    pub const Kind = enum(u2) {
        fill = 0,
        stroke_front = 1,
        stroke_back = 2,
    };

    kind: Kind,
    segment_index: u32 = 0,
    start_line_data_offset: u32 = 0,
    end_line_data_offset: u32 = 0,
    start_intersection_offset: u32 = 0,
    end_intersection_offset: u32 = 0,
};

pub const Masks = struct {
    vertical_mask0: u16 = 0,
    vertical_sign0: f32 = 0.0,
    vertical_mask1: u16 = 0,
    vertical_sign1: f32 = 0.0,
    horizontal_mask: u16 = 0,
    horizontal_sign: f32 = 0.0,

    pub fn debugPrint(self: @This()) void {
        std.debug.print("-----------\n", .{});
        std.debug.print("V0({}): {b:0>16}\n", .{ self.vertical_sign0, self.vertical_mask0 });
        std.debug.print("V0({}): {b:0>16}\n", .{ self.vertical_sign1, self.vertical_mask1 });
        std.debug.print(" H({}): {b:0>16}\n", .{ self.horizontal_sign, self.horizontal_mask });
        std.debug.print("-----------\n", .{});
    }
};

pub const BoundaryFragment = struct {
    pub const MAIN_RAY: LineF32 = LineF32.create(PointF32{
        .x = 0.0,
        .y = 0.5,
    }, PointF32{
        .x = 1.0,
        .y = 0.5,
    });

    pixel: PointI32,
    masks: Masks,
    intersections: [2]IntersectionF32,
    is_merge: bool = false,
    is_scanline: bool = false,
    main_ray_winding: f32 = 0,
    stencil_mask: u16 = 0,

    pub fn create(
        half_planes: *const HalfPlanesU16,
        pixel_offset: PointI32,
        grid_intersections: [2]*const GridIntersection,
    ) @This() {
        const pixel = grid_intersections[0].pixel.min(grid_intersections[1].pixel);

        // can move diagonally, but cannot move by more than 1 pixel in both directions
        std.debug.assert(@abs(pixel.sub(grid_intersections[0].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[0].pixel).y) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[1].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[1].pixel).y) <= 1);

        const intersections: [2]IntersectionF32 = [2]IntersectionF32{
            IntersectionF32{
                // retain t
                .t = grid_intersections[0].intersection.t,
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = std.math.clamp(@abs(grid_intersections[0].intersection.point.x - @as(f32, @floatFromInt(pixel.x))), 0.0, 1.0),
                    .y = std.math.clamp(@abs(grid_intersections[0].intersection.point.y - @as(f32, @floatFromInt(pixel.y))), 0.0, 1.0),
                },
            },
            IntersectionF32{
                // retain t
                .t = grid_intersections[1].intersection.t,
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = std.math.clamp(@abs(grid_intersections[1].intersection.point.x - @as(f32, @floatFromInt(pixel.x))), 0.0, 1.0),
                    .y = std.math.clamp(@abs(grid_intersections[1].intersection.point.y - @as(f32, @floatFromInt(pixel.y))), 0.0, 1.0),
                },
            },
        };

        std.debug.assert(intersections[0].point.x <= 1.0);
        std.debug.assert(intersections[0].point.y <= 1.0);
        std.debug.assert(intersections[1].point.x <= 1.0);
        std.debug.assert(intersections[1].point.y <= 1.0);

        const masks = calculateMasks(half_planes, intersections);

        return @This(){
            .pixel = pixel.add(pixel_offset),
            .masks = masks,
            .intersections = intersections,
        };
    }

    pub fn calculateMasks(half_planes: *const HalfPlanesU16, intersections: [2]IntersectionF32) Masks {
        var masks = Masks{};
        if (intersections[0].point.x == 0.0 and intersections[1].point.x != 0.0) {
            const vertical_mask = half_planes.getVerticalMask(intersections[0].point.y);

            if (intersections[0].point.y < 0.5) {
                masks.vertical_mask0 = ~vertical_mask;
                masks.vertical_sign0 = -1;
            } else if (intersections[0].point.y > 0.5) {
                masks.vertical_mask0 = vertical_mask;
                masks.vertical_sign0 = 1;
            } else {
                // need two masks and two signs...
                masks.vertical_mask0 = vertical_mask; // > 0.5
                masks.vertical_sign0 = 0.5;
                masks.vertical_mask1 = ~vertical_mask; // < 0.5
                masks.vertical_sign1 = -0.5;
            }
        } else if (intersections[1].point.x == 0.0 and intersections[0].point.x != 0.0) {
            const vertical_mask = half_planes.getVerticalMask(intersections[1].point.y);

            if (intersections[1].point.y < 0.5) {
                masks.vertical_mask0 = ~vertical_mask;
                masks.vertical_sign0 = 1;
            } else if (intersections[1].point.y > 0.5) {
                masks.vertical_mask0 = vertical_mask;
                masks.vertical_sign0 = -1;
            } else {
                // need two masks and two signs...
                masks.vertical_mask0 = vertical_mask; // > 0.5
                masks.vertical_sign0 = -0.5;
                masks.vertical_mask1 = ~vertical_mask; // < 0.5
                masks.vertical_sign1 = 0.5;
            }
        }

        if (intersections[0].point.y > intersections[1].point.y) {
            // crossing top to bottom
            masks.horizontal_sign = 1;
        } else if (intersections[0].point.y < intersections[1].point.y) {
            masks.horizontal_sign = -1;
        }

        if (intersections[0].t > intersections[1].t) {
            masks.horizontal_sign *= -1;
            masks.vertical_sign0 *= -1;
            masks.vertical_sign1 *= -1;
        }

        masks.horizontal_mask = half_planes.getHorizontalMask(intersections[0].point, intersections[1].point);
        return masks;
    }

    pub fn calculateMainRayWinding(self: @This()) f32 {
        const line = LineF32.create(self.intersections[0].point, self.intersections[1].point);
        if (line.intersectHorizontalLine(MAIN_RAY) != null) {
            // curve fragment line cannot be horizontal, so intersection1.y != intersection2.y

            var winding: f32 = 0.0;

            if (self.intersections[0].point.y > self.intersections[1].point.y) {
                winding = 1.0;
            } else if (self.intersections[0].point.y < self.intersections[1].point.y) {
                winding = -1.0;
            }

            if (self.intersections[0].point.y == 0.5 or self.intersections[1].point.y == 0.5) {
                winding *= 0.5;
            }

            return winding;
        }

        return 0.0;
    }

    pub fn maskStencil(
        comptime fill_rule: Style.FillRule,
        merge_boundary_fragments: []const BoundaryFragment,
    ) u16 {
        std.debug.assert(merge_boundary_fragments.len > 0);

        const main_ray_winding = merge_boundary_fragments[0].main_ray_winding;
        var stencil_mask: u16 = 0;

        // calculate stencil mask
        for (0..16) |index| {
            const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
            var bit_winding: f32 = main_ray_winding;

            for (merge_boundary_fragments) |boundary_fragment| {
                const masks = boundary_fragment.masks;
                const vertical_winding0 = masks.vertical_sign0 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask0 & bit_index != 0)));
                const vertical_winding1 = masks.vertical_sign1 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask1 & bit_index != 0)));
                const horizontal_winding = masks.horizontal_sign * @as(f32, @floatFromInt(@intFromBool(masks.horizontal_mask & bit_index != 0)));
                bit_winding += vertical_winding0 + vertical_winding1 + horizontal_winding;
            }

            switch (fill_rule) {
                .non_zero => {
                    stencil_mask |= @as(u16, @intFromBool(@as(i16, @intFromFloat(bit_winding)) != 0)) * bit_index;
                },
                .even_odd => {
                    stencil_mask |= @as(u16, @intCast((@as(i16, @intFromFloat(bit_winding)) & 1))) * bit_index;
                },
            }
        }

        return stencil_mask;
    }

    pub fn getIntensity(self: @This()) f32 {
        return @as(f32, @floatFromInt(@popCount(self.stencil_mask))) / 16.0;
    }

    pub fn debugPrint(self: @This()) void {
        std.debug.print("Pixel({},{}), IsMerge({}), IsScanline({}), MainRayWinding({}), Stencil({b:0>16})\n", .{
            self.pixel.x,
            self.pixel.y,
            self.is_merge,
            self.is_scanline,
            self.main_ray_winding,
            self.stencil_mask,
        });
        std.debug.print("PixelLine(({},{}),({},{}))", .{
            self.intersections[0].point.x,
            self.intersections[0].point.y,
            self.intersections[1].point.x,
            self.intersections[1].point.y,
        });
        self.masks.debugPrint();
    }
};

pub const GridIntersection = struct {
    intersection: IntersectionF32,
    pixel: PointI32,

    pub fn create(intersection: IntersectionF32) @This() {
        return @This(){
            .intersection = intersection,
            .pixel = PointI32{
                .x = @intFromFloat(intersection.point.x),
                .y = @intFromFloat(intersection.point.y),
            },
        };
    }

    pub fn fitToGrid(self: @This()) @This() {
        return create(self.intersection.fitToGrid());
    }

    pub fn reverse(self: @This()) @This() {
        var intersection2 = self.intersection;
        intersection2.t = 1.0 - self.intersection.t;

        return GridIntersection{
            .intersection = intersection2,
            .pixel = self.pixel,
        };
    }
};

pub const LineIterator = struct {
    line_data: []const u8,
    offset: u32 = 0,

    pub fn next(self: *@This()) ?LineF32 {
        const end_offset = self.offset + @sizeOf(PointF32);
        if (end_offset >= self.line_data.len) {
            return null;
        }

        const line = std.mem.bytesToValue(LineF32, self.line_data[self.offset..end_offset]);
        self.offset += @sizeOf(PointF32);
        return line;
    }
};

pub const Scanner = struct {
    x_range: RangeF32,
    y_range: RangeF32,
    inc_x: f32,
    inc_y: f32,

    pub fn nextX(self: *@This()) ?f32 {
        if (self.inc_x < 0.0) {
            if (self.x_range.end - self.x_range.start > 0) {
                return null;
            }
        } else {
            if (self.x_range.end - self.x_range.start < 0) {
                return null;
            }
        }

        const next = self.x_range.start;
        self.x_range.start += self.inc_x;
        return next;
    }

    pub fn nextY(self: *@This()) ?f32 {
        if (self.inc_y < 0.0) {
            if (self.y_range.end - self.y_range.start > 0) {
                return null;
            }
        } else {
            if (self.y_range.end - self.y_range.start < 0) {
                return null;
            }
        }

        const next = self.y_range.start;
        self.y_range.start += self.inc_y;
        return next;
    }

    pub fn peekNextY(self: *@This()) f32 {
        return self.y_range.start;
    }
};
