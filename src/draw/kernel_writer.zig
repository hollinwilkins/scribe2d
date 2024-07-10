const std = @import("std");
const core = @import("../core/root.zig");
const encoding_module = @import("./encoding.zig");
const mem = std.mem;
const RectF32 = core.RectF32;
const LineF32 = core.LineF32;
const PointF32 = core.PointF32;
const Path = encoding_module.Path;
const Subpath = encoding_module.Subpath;
const PathMonoid = encoding_module.PathMonoid;
const FlatSegment = encoding_module.FlatSegment;
const FlatSegmentOffset = encoding_module.FlatSegmentOffset;
const SegmentOffset = encoding_module.SegmentOffset;

pub const SimpleLineWriterFactory = struct {
    flat_segments: []FlatSegment,
    line_data: []u8,

    pub fn create(
        self: @This(),
        kind: FlatSegment.Kind,
        segment_index: u32,
        flatten_offset: FlatSegmentOffset,
    ) SimpleLineWriter {
        var flat_segment: *FlatSegment = undefined;

        switch (kind) {
            .fill => {
                flat_segment = &self.flat_segments[flatten_offset.fill_flat_segment_index];
                flat_segment.* = FlatSegment{
                    .kind = .fill,
                    .segment_index = segment_index,
                    .start_line_data_offset = flatten_offset.start_fill_line_offset,
                    .end_line_data_offset = flatten_offset.end_fill_line_offset,
                    .start_intersection_offset = flatten_offset.start_fill_intersection_offset,
                    .end_intersection_offset = flatten_offset.end_fill_intersection_offset,
                };
            },
            .stroke_front => {
                flat_segment = &self.flat_segments[flatten_offset.front_stroke_flat_segment_index];
                flat_segment.* = FlatSegment{
                    .kind = .stroke_front,
                    .segment_index = segment_index,
                    .start_line_data_offset = flatten_offset.start_front_stroke_line_offset,
                    .end_line_data_offset = flatten_offset.end_front_stroke_line_offset,
                    .start_intersection_offset = flatten_offset.start_front_stroke_intersection_offset,
                    .end_intersection_offset = flatten_offset.end_front_stroke_intersection_offset,
                };
            },
            .stroke_back => {
                flat_segment = &self.flat_segments[flatten_offset.back_stroke_flat_segment_index];
                flat_segment.* = FlatSegment{
                    .kind = .stroke_back,
                    .segment_index = segment_index,
                    .start_line_data_offset = flatten_offset.start_back_stroke_line_offset,
                    .end_line_data_offset = flatten_offset.end_back_stroke_line_offset,
                    .start_intersection_offset = flatten_offset.start_back_stroke_intersection_offset,
                    .end_intersection_offset = flatten_offset.end_back_stroke_intersection_offset,
                };
            },
        }

        return SimpleLineWriter{
            .flat_segment = flat_segment,
            .line_data = self.line_data[flat_segment.start_line_data_offset..flat_segment.end_line_data_offset],
        };
    }
};

pub const SimpleLineWriter = struct {
    flat_segment: *FlatSegment,
    line_data: []u8,
    bounds: RectF32 = RectF32.NONE,
    lines: u32 = 0,
    offset: u32 = 0,
    debug: bool = false,

    pub fn write(self: *@This(), line: LineF32) void {
        if (std.meta.eql(line.p0, line.p1)) {
            return;
        }

        self.lines += 1;
        if (self.offset == 0) {
            self.addPoint(line.p0);
            self.addPoint(line.p1);
            return;
        }

        const last_point = self.lastPoint();
        std.debug.assert(std.meta.eql(last_point, line.p0));
        self.addPoint(line.p1);
    }

    fn lastPoint(self: @This()) PointF32 {
        return std.mem.bytesToValue(PointF32, self.line_data[self.offset - @sizeOf(PointF32) .. self.offset]);
    }

    fn addPoint(self: *@This(), point: PointF32) void {
        self.bounds.extendByInPlace(point);
        std.mem.bytesAsValue(PointF32, self.line_data[self.offset .. self.offset + @sizeOf(PointF32)]).* = point;
        self.offset += @sizeOf(PointF32);

        if (self.debug) {
            std.debug.print("WritePoint: {}\n", .{point});
        }
    }

    pub fn close(self: *@This()) void {
        self.flat_segment.end_line_data_offset = self.flat_segment.start_line_data_offset + self.offset;
    }
};
