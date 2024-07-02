const std = @import("std");
const core = @import("../core/root.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;

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

pub const Encoder = struct {
    const SegmentTagList = std.ArrayListUnmanaged(SegmentTag);
    const TransformList = std.ArrayListUnmanaged(TransformF32.Matrix);
    const StyleList = std.ArrayListUnmanaged(Style);
    const Buffer = std.ArrayListUnmanaged(u8);

    allocator: Allocator,
    segment_tags: SegmentTagList = SegmentTagList{},
    transforms: TransformList = TransformList{},
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
};
