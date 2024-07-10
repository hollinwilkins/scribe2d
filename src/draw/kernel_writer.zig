const std = @import("std");
const core = @import("../core/root.zig");
const encoding_module = @import("./encoding.zig");
const msaa_module = @import("./msaa.zig");
const mem = std.mem;
const RangeF32 = core.RangeF32;
const RectF32 = core.RectF32;
const RectI32 = core.RectI32;
const PointI32 = core.PointI32;
const LineF32 = core.LineF32;
const PointF32 = core.PointF32;
const IntersectionF32 = core.IntersectionF32;
const Path = encoding_module.Path;
const Subpath = encoding_module.Subpath;
const PathMonoid = encoding_module.PathMonoid;
const FlatSegment = encoding_module.FlatSegment;
const GridIntersection = encoding_module.GridIntersection;
const BoundaryFragment = encoding_module.BoundaryFragment;
const PathOffset = encoding_module.PathOffset;
const FlatSegmentOffset = encoding_module.FlatSegmentOffset;
const SegmentOffset = encoding_module.SegmentOffset;
const BumpAllocator = encoding_module.BumpAllocator;
const Scanner = encoding_module.Scanner;
const HalfPlanesU16 = msaa_module.HalfPlanesU16;

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

pub const SinglePassLineWriterFactory = struct {
    half_planes: *const HalfPlanesU16,
    path_monoids: []const PathMonoid,
    segment_offsets: []const SegmentOffset,
    boundary_fragments: []BoundaryFragment,
    paths: []Path,

    pub fn create(
        self: @This(),
        kind: FlatSegment.Kind,
        segment_index: u32,
        flatten_offset: FlatSegmentOffset,
    ) SinglePassLineWriter {
        _ = flatten_offset;
        const path_monoid = self.path_monoids[segment_index];
        const path = &self.paths[path_monoid.path_index];
        const path_offset = PathOffset.create(
            path_monoid.path_index,
            self.segment_offsets,
            self.paths,
        );
        var bump: BumpAllocator = undefined;

        switch (kind) {
            .fill => {
                bump = BumpAllocator{
                    .start = path_offset.start_fill_boundary_offset,
                    .end = path_offset.end_fill_boundary_offset,
                    .offset = &path.fill_bump,
                };
            },
            else => {
                bump = BumpAllocator{
                    .start = path_offset.start_stroke_boundary_offset,
                    .end = path_offset.end_stroke_boundary_offset,
                    .offset = &path.stroke_bump,
                };
            },
        }

        return SinglePassLineWriter{
            .half_planes = self.half_planes,
            .bump = bump,
            .boundary_fragments = self.boundary_fragments,
        };
    }
};

pub const SinglePassLineWriter = struct {
    const GRID_POINT_TOLERANCE: f32 = 1e-6;

    half_planes: *const HalfPlanesU16,
    bump: BumpAllocator,
    boundary_fragments: []BoundaryFragment,
    bounds: RectF32 = RectF32.NONE,
    lines: u32 = 0,
    debug: bool = true,
    previous_point: ?PointF32 = null,
    previous_grid_intersection: ?GridIntersection = null,

    pub fn write(self: *@This(), line: LineF32) void {
        if (std.meta.eql(line.p0, line.p1)) {
            return;
        }

        if (self.debug) {
            std.debug.print("WriteLine: {}\n", .{line});
        }

        // intersect
        // boundary

        self.intersect(line);

        self.lines += 1;
    }

    fn intersect(self: *@This(), line: LineF32) void {
        const start_point: PointF32 = line.apply(0.0);
        const end_point: PointF32 = line.apply(1.0);
        const bounds_f32: RectF32 = RectF32.create(start_point, end_point);
        const bounds: RectI32 = RectI32.create(PointI32{
            .x = @intFromFloat(@ceil(bounds_f32.min.x)),
            .y = @intFromFloat(@ceil(bounds_f32.min.y)),
        }, PointI32{
            .x = @intFromFloat(@floor(bounds_f32.max.x)),
            .y = @intFromFloat(@floor(bounds_f32.max.y)),
        });
        const scan_bounds = RectF32.create(PointF32{
            .x = @floatFromInt(bounds.min.x - 1),
            .y = @floatFromInt(bounds.min.y - 1),
        }, PointF32{
            .x = @floatFromInt(bounds.max.x + 1),
            .y = @floatFromInt(bounds.max.y + 1),
        });

        const start_intersection = GridIntersection.create((IntersectionF32{
            .t = 0.0,
            .point = start_point,
        }).fitToGrid());
        const end_intersection = GridIntersection.create((IntersectionF32{
            .t = 1.0,
            .point = end_point,
        }).fitToGrid());

        const min_x = start_intersection.intersection.point.x < end_intersection.intersection.point.x;
        const min_y = start_intersection.intersection.point.y < end_intersection.intersection.point.y;
        var start_x: f32 = if (min_x) @floor(start_intersection.intersection.point.x) else @ceil(start_intersection.intersection.point.x);
        var end_x: f32 = if (min_x) @ceil(end_intersection.intersection.point.x) else @floor(end_intersection.intersection.point.x);
        var start_y: f32 = if (min_y) @floor(start_intersection.intersection.point.y) else @ceil(start_intersection.intersection.point.y);
        var end_y: f32 = if (min_y) @ceil(end_intersection.intersection.point.y) else @floor(end_intersection.intersection.point.y);
        const inc_x: f32 = if (min_x) 1.0 else -1.0;
        const inc_y: f32 = if (min_y) 1.0 else -1.0;

        if (start_x == start_intersection.intersection.point.x) {
            start_x += inc_x;
        }

        if (end_x == end_intersection.intersection.point.x) {
            end_x -= inc_x;
        }

        if (start_y == start_intersection.intersection.point.y) {
            start_y += inc_y;
        }

        if (end_y == end_intersection.intersection.point.y) {
            end_y -= inc_y;
        }

        var scanner = Scanner{
            .x_range = RangeF32{
                .start = start_x,
                .end = end_x,
            },
            .y_range = RangeF32{
                .start = start_y,
                .end = end_y,
            },
            .inc_x = inc_x,
            .inc_y = inc_y,
        };

        self.writeIntersection(start_intersection);

        var start_x_intersection: GridIntersection = start_intersection;
        var start_y_intersection: GridIntersection = start_intersection;
        var start_scan_x = scanner.x_range.start;
        var start_scan_y = scanner.y_range.start;
        while (scanner.nextX()) |x| {
            if (scanX(x, line, scan_bounds)) |x_intersection| {
                scan_y: {
                    if (@abs(start_scan_y - x_intersection.intersection.point.y) > 1.0) {
                        while (scanner.nextY()) |y| {
                            if (scanY(y, line, scan_bounds)) |y_intersection| {
                                self.writeIntersection(y_intersection);
                                start_scan_y = y;
                                start_y_intersection = y_intersection;
                            }

                            const next_y = scanner.peekNextY();
                            if (min_y and next_y >= x_intersection.intersection.point.y) {
                                break :scan_y;
                            } else if (!min_y and next_y <= x_intersection.intersection.point.y) {
                                break :scan_y;
                            }
                        }
                    }
                }

                self.writeIntersection(x_intersection);
                start_scan_x = x;
                start_x_intersection = x_intersection;
            }
        }

        while (scanner.nextY()) |y| {
            if (scanY(y, line, scan_bounds)) |y_intersection| {
                self.writeIntersection(y_intersection);
                start_scan_y = y;
                start_y_intersection = y_intersection;
            }
        }

        self.writeIntersection(end_intersection);
    }

    fn writeIntersection(self: *@This(), grid_intersection: GridIntersection) void {
        if (self.debug) {
            std.debug.print("GridIntersection({},{}), T({}), Intersection({},{})\n", .{
                grid_intersection.pixel.x,
                grid_intersection.pixel.y,
                grid_intersection.intersection.t,
                grid_intersection.intersection.point.x,
                grid_intersection.intersection.point.y,
            });
        }

        if (self.previous_grid_intersection) |*previous| {
            if (grid_intersection.intersection.point.approxEqAbs(previous.intersection.point, GRID_POINT_TOLERANCE)) {
                // skip if exactly the same point
                self.previous_grid_intersection = grid_intersection;
                return;
            }

            {
                self.writeBoundaryFragment(BoundaryFragment.create(
                    self.half_planes,
                    [_]*const GridIntersection{
                        previous,
                        &grid_intersection,
                    },
                ));
            }

            self.previous_grid_intersection = grid_intersection;
        } else {
            self.previous_grid_intersection = grid_intersection;
            return;
        }
    }

    fn writeBoundaryFragment(self: *@This(), boundary_fragment: BoundaryFragment) void {
        if (self.debug) {
            std.debug.print("BoundaryFragment({},{})\n", .{
                boundary_fragment.pixel.x,
                boundary_fragment.pixel.y,
            });
        }

        const boundary_fragment_index = self.bump.bump(1);
        self.boundary_fragments[boundary_fragment_index] = boundary_fragment;
    }

    fn scanX(
        grid_x: f32,
        line: LineF32,
        scan_bounds: RectF32,
    ) ?GridIntersection {
        const scan_line = LineF32.create(
            PointF32{
                .x = grid_x,
                .y = scan_bounds.min.y,
            },
            PointF32{
                .x = grid_x,
                .y = scan_bounds.max.y,
            },
        );

        if (line.intersectVerticalLine(scan_line)) |intersection| {
            return GridIntersection.create(intersection.fitToGrid());
        }

        return null;
    }

    fn scanY(
        grid_y: f32,
        line: LineF32,
        scan_bounds: RectF32,
    ) ?GridIntersection {
        const scan_line = LineF32.create(
            PointF32{
                .x = scan_bounds.min.x,
                .y = grid_y,
            },
            PointF32{
                .x = scan_bounds.max.x,
                .y = grid_y,
            },
        );

        if (line.intersectHorizontalLine(scan_line)) |intersection| {
            return GridIntersection.create(intersection.fitToGrid());
        }

        return null;
    }

    pub fn close(self: *@This()) void {
        _ = self;
        // do nothing
    }
};
