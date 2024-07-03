const core = @import("../core/root.zig");
const encoding_module = @import("./encoding.zig");
const RangeU32 = core.RangeU32;
const PathTag = encoding_module.PathTag;
const PathMonoid = encoding_module.PathMonoid;

pub const SegmentEstimate = packed struct {
    lines: u16 = 0,
    intersections: u16 = 0,
    cap_lines: u16 = 0,
    join_lines: u16 = 0,

    pub fn combine(self: @This(), other: @This()) @This() {
        return @This(){
            .lines = self.lines + other.lines,
            .intersections = self.intersections + other.intersections,
            .cap_lines = self.cap_lines + other.cap_lines,
            .join_lines = self.join_lines + other.join_lines,
        };
    }
};

pub const Estimate = struct {
    pub fn fillEstimate(
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        segment_data: []const u8,
        range: RangeU32,
        // outputs
        estimates: []SegmentEstimate,
    ) void {
        _ = segment_data;
        for (range.start..range.end) |index| {
            const path_tag = path_tags[index];
            const path_monoid = path_monoids[index];
            const estimate = &estimates[index];

            _ = path_tag;
            _ = path_monoid;
            _ = estimate;
        }
    }

    pub fn strokeEstimate(
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        segment_data: []const u8,
        range: RangeU32, // range over a path
        // outputs
        estimates: []SegmentEstimate, // 2x size of path_tags for left/right
    ) void {
        _ = segment_data;
        for (range.start..range.end) |index| {
            const path_tag = path_tags[index];
            const path_monoid = path_monoids[index];
            const estimate = &estimates[index];

            _ = path_tag;
            _ = path_monoid;
            _ = estimate;
        }
    }

    pub fn flattenFill(
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        segment_data: []const u8,
        range: RangeU32,
        // outputs
        // true if path is used, false to ignore
        flat_path_mask: []bool,
        flat_path_tags: []PathTag,
        flat_path_monoids: []PathMonoid,
        flat_segment_data: []u8,
    ) void {
        _ = path_tags;
        _ = path_monoids;
        _ = segment_data;
        _ = range;
        _ = flat_path_mask;
        _ = flat_path_tags;
        _ = flat_path_monoids;
        _ = flat_segment_data;
    }

    pub fn flattenStroke(
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        segment_data: []const u8,
        range: RangeU32,
        // outputs
        // true if path is used, false to ignore
        flat_path_mask: []bool,
        flat_path_tags: []PathTag, // 2x path_tags for left/right
        flat_path_monoids: []PathMonoid,  // 2x path_tags for left/right
        flat_segment_data: []u8,
    ) void {
        _ = path_tags;
        _ = path_monoids;
        _ = segment_data;
        _ = range;
        _ = flat_path_mask;
        _ = flat_path_tags;
        _ = flat_path_monoids;
        _ = flat_segment_data;
    }

    // scanlineFill(
    //   masks,
    //   tags,
    //   monoids,
    //   segment data,
    //   grid_intersections,
    //   boundary_fragments,
    //   merge_fragments,
    //   spans,
    // )
};
