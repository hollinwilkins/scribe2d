const std = @import("std");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const Line = core.Line;
const Arc = core.Arc;
const QuadraticBezier = core.QuadraticBezier;
const CubicBezier = core.CubicBezier;

pub const SegmentTag = packed struct {
    pub const Bits = enum(u1) {
        float32,
        int16,
    };

    pub const Kind = enum(u2) {
        line,
        arc,
        quadratic_bezier,
        cubic_bezier,
    };

    // bit encoding of points for this segment
    bits: Bits,
    // what kind of segment is this
    kind: Kind,
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
};

pub const Style = packed struct {};

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

    pub fn currentAffine(self: @This()) ?TransformF32.Affine {
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
        return true;
    }

    pub fn currentStyle(self: @This()) ?Style {
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
        return true;
    }

    pub fn extendSegment(self: *@This(), n: usize) ![]u8 {
        return try self.segments.addManyAsSlice(self.allocator, n);
    }
};
