const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const soup_pen = @import("./soup_pen.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const scene_module = @import("./scene.zig");
const msaa = @import("./msaa.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const PointI32 = core.PointI32;
const RangeI32 = core.RangeI32;
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;
const PathMetadata = path_module.PathMetadata;
const Paths = path_module.Paths;
const Style = soup_pen.Style;
const Line = curve_module.Line;
const Arc = curve_module.Arc;
const Intersection = curve_module.Intersection;
const CubicPoints = euler.CubicPoints;
const CubicParams = euler.CubicParams;
const EulerParams = euler.EulerParams;
const EulerSegment = euler.EulerSegment;
const Scene = scene_module.Scene;
const HalfPlanesU16 = msaa.HalfPlanesU16;

pub const PathRecord = struct {
    fill: Style.Fill = Style.Fill{},
    subpath_offsets: RangeU32 = RangeU32{},
    boundary_offsets: RangeU32 = RangeU32{},
    merge_offsets: RangeU32 = RangeU32{},
    span_offsets: RangeU32 = RangeU32{},
};

pub const SubpathRecord = struct {
    curve_offsets: RangeU32 = RangeU32{},
    intersection_offsets: RangeU32 = RangeU32{},
};

pub const CurveRecord = struct {
    item_offsets: RangeU32 = RangeU32{},
};

pub const FillJob = struct {
    // index in the source Paths struct for the curve data
    metadata_index: u32 = 0,
    source_curve_index: u32 = 0,
    curve_index: u32 = 0,
};

pub const StrokeJob = struct {
    // index in the source Paths struct for the curve data
    metadata_index: u32 = 0,
    source_subpath_index: u32 = 0,
    source_curve_index: u32 = 0,
    left_curve_index: u32 = 0,
    right_curve_index: u32 = 0,
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
        std.debug.print("V0: {b:0>16}\n", .{self.vertical_mask0});
        std.debug.print("V0: {b:0>16}\n", .{self.vertical_mask1});
        std.debug.print(" H: {b:0>16}\n", .{self.horizontal_mask});
        std.debug.print("-----------\n", .{});
    }
};

pub const BoundaryFragment = struct {
    pub const MAIN_RAY: Line = Line.create(PointF32{
        .x = 0.0,
        .y = 0.5,
    }, PointF32{
        .x = 1.0,
        .y = 0.5,
    });

    pixel: PointI32,
    intersections: [2]Intersection,

    pub fn create(grid_intersections: [2]*const GridIntersection) @This() {
        const pixel = grid_intersections[0].pixel.min(grid_intersections[1].pixel);

        // can move diagonally, but cannot move by more than 1 pixel in both directions
        std.debug.assert(@abs(pixel.sub(grid_intersections[0].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[0].pixel).y) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[1].pixel).x) <= 1);
        std.debug.assert(@abs(pixel.sub(grid_intersections[1].pixel).y) <= 1);

        const intersections: [2]Intersection = [2]Intersection{
            Intersection{
                // retain t
                .t = grid_intersections[0].intersection.t,
                // float component of the intersection points, range [0.0, 1.0]
                .point = PointF32{
                    .x = std.math.clamp(@abs(grid_intersections[0].intersection.point.x - @as(f32, @floatFromInt(pixel.x))), 0.0, 1.0),
                    .y = std.math.clamp(@abs(grid_intersections[0].intersection.point.y - @as(f32, @floatFromInt(pixel.y))), 0.0, 1.0),
                },
            },
            Intersection{
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
        return @This(){
            .pixel = pixel,
            .intersections = intersections,
        };
    }

    pub fn calculateMasks(self: @This(), half_planes: *const HalfPlanesU16) Masks {
        var masks = Masks{};
        if (self.intersections[0].point.x == 0.0 and self.intersections[1].point.x != 0.0) {
            const vertical_mask = half_planes.getVerticalMask(self.intersections[0].point.y);

            if (self.intersections[0].point.y < 0.5) {
                masks.vertical_mask0 = ~vertical_mask;
                masks.vertical_sign0 = -1;
            } else if (self.intersections[0].point.y > 0.5) {
                masks.vertical_mask0 = vertical_mask;
                masks.vertical_sign0 = 1;
            } else {
                // need two masks and two signs...
                masks.vertical_mask0 = vertical_mask; // > 0.5
                masks.vertical_sign0 = 0.5;
                masks.vertical_mask1 = ~vertical_mask; // < 0.5
                masks.vertical_sign1 = -0.5;
            }
        } else if (self.intersections[1].point.x == 0.0 and self.intersections[0].point.x != 0.0) {
            const vertical_mask = half_planes.getVerticalMask(self.intersections[1].point.y);

            if (self.intersections[1].point.y < 0.5) {
                masks.vertical_mask0 = ~vertical_mask;
                masks.vertical_sign0 = 1;
            } else if (self.intersections[1].point.y > 0.5) {
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

        if (self.intersections[0].point.y > self.intersections[1].point.y) {
            // crossing top to bottom
            masks.horizontal_sign = 1;
        } else if (self.intersections[0].point.y < self.intersections[1].point.y) {
            masks.horizontal_sign = -1;
        }

        if (self.intersections[0].t > self.intersections[1].t) {
            masks.horizontal_sign *= -1;
            masks.vertical_sign0 *= -1;
            masks.vertical_sign1 *= -1;
        }

        masks.horizontal_mask = half_planes.getHorizontalMask(self.getLine());
        return masks;
    }

    pub fn getLine(self: @This()) Line {
        return Line.create(self.intersections[0].point, self.intersections[1].point);
    }

    pub fn calculateMainRayWinding(self: @This()) f32 {
        if (self.getLine().intersectHorizontalLine(MAIN_RAY) != null) {
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
};

pub const MergeFragment = struct {
    pixel: PointI32,
    main_ray_winding: f32 = 0.0,
    winding: [16]f32 = [_]f32{0.0} ** 16,
    stencil_mask: u16 = 0,
    boundary_offsets: RangeU32 = RangeU32{},

    pub fn getIntensity(self: @This()) f32 {
        return @as(f32, @floatFromInt(@popCount(self.stencil_mask))) / 16.0;
    }
};

pub const Span = struct {
    y: i32 = 0,
    x_range: RangeI32 = RangeI32{},
};

pub const GridIntersection = struct {
    intersection: Intersection,
    pixel: PointI32,

    pub fn create(intersection: Intersection) @This() {
        return @This(){
            .intersection = intersection,
            .pixel = PointI32{
                .x = @intFromFloat(intersection.point.x),
                .y = @intFromFloat(intersection.point.y),
            },
        };
    }
};

pub fn Soup(comptime T: type) type {
    return struct {
        pub const PathRecordList = std.ArrayListUnmanaged(PathRecord);
        pub const SubpathRecordList = std.ArrayListUnmanaged(SubpathRecord);
        pub const CurveRecordList = std.ArrayListUnmanaged(CurveRecord);
        pub const EstimateList = std.ArrayListUnmanaged(u32);
        pub const FillJobList = std.ArrayListUnmanaged(FillJob);
        pub const StrokeJobList = std.ArrayListUnmanaged(StrokeJob);
        pub const ItemList = std.ArrayListUnmanaged(T);
        pub const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
        pub const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);
        pub const MergeFragmentList = std.ArrayListUnmanaged(MergeFragment);
        pub const SpanList = std.ArrayListUnmanaged(Span);

        allocator: Allocator,
        path_records: PathRecordList = PathRecordList{},
        subpath_records: SubpathRecordList = SubpathRecordList{},
        curve_records: CurveRecordList = CurveRecordList{},
        curve_estimates: EstimateList = EstimateList{},
        base_estimates: EstimateList = EstimateList{},
        fill_jobs: FillJobList = FillJobList{},
        stroke_jobs: StrokeJobList = StrokeJobList{},
        items: ItemList = ItemList{},
        grid_intersections: GridIntersectionList = GridIntersectionList{},
        boundary_fragments: BoundaryFragmentList = BoundaryFragmentList{},
        merge_fragments: MergeFragmentList = MergeFragmentList{},
        spans: SpanList = SpanList{},

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.path_records.deinit(self.allocator);
            self.subpath_records.deinit(self.allocator);
            self.curve_records.deinit(self.allocator);
            self.curve_estimates.deinit(self.allocator);
            self.base_estimates.deinit(self.allocator);
            self.fill_jobs.deinit(self.allocator);
            self.stroke_jobs.deinit(self.allocator);
            self.items.deinit(self.allocator);
            self.grid_intersections.deinit(self.allocator);
            self.boundary_fragments.deinit(self.allocator);
            self.merge_fragments.deinit(self.allocator);
            self.spans.deinit(self.allocator);
        }

        pub fn addPathRecord(self: *@This()) !*PathRecord {
            const path = try self.path_records.addOne(self.allocator);
            path.* = PathRecord{};
            return path;
        }

        pub fn openPathSubpaths(self: @This(), path_record: *PathRecord) void {
            path_record.subpath_offsets = RangeU32{
                .start = @intCast(self.subpath_records.items.len),
                .end = @intCast(self.subpath_records.items.len),
            };
        }

        pub fn openPathBoundaries(self: *@This(), path_record: *PathRecord) void {
            path_record.boundary_offsets.start = @intCast(self.boundary_fragments.items.len);
        }

        pub fn openPathMerges(self: *@This(), path_record: *PathRecord) void {
            path_record.merge_offsets.start = @intCast(self.merge_fragments.items.len);
        }

        pub fn openPathSpans(self: *@This(), path_record: *PathRecord) void {
            path_record.span_offsets.start = @intCast(self.spans.items.len);
        }

        pub fn closePathSubpaths(self: @This(), path_record: *PathRecord) void {
            path_record.subpath_offsets.end = @intCast(self.subpath_records.items.len);
        }

        pub fn closePathBoundaries(self: *@This(), path_record: *PathRecord) void {
            path_record.boundary_offsets.end = @intCast(self.boundary_fragments.items.len);
        }

        pub fn closePathMerges(self: *@This(), path_record: *PathRecord) void {
            path_record.merge_offsets.end = @intCast(self.merge_fragments.items.len);
        }

        pub fn closePathSpans(self: *@This(), path_record: *PathRecord) void {
            path_record.span_offsets.end = @intCast(self.spans.items.len);
        }

        pub fn addSubpath(self: *@This()) !*SubpathRecord {
            const subpath = try self.subpath_records.addOne(self.allocator);
            subpath.* = SubpathRecord{};
            return subpath;
        }

        pub fn openSubpathCurves(self: @This(), subpath_record: *SubpathRecord) void {
            subpath_record.curve_offsets = RangeU32{
                .start = @intCast(self.curve_records.items.len),
                .end = @intCast(self.curve_records.items.len),
            };
        }

        pub fn openSubpathIntersections(self: *@This(), subpath_record: *SubpathRecord) void {
            subpath_record.intersection_offsets.start = @intCast(self.grid_intersections.items.len);
        }

        pub fn closeSubpathCurves(self: @This(), subpath_record: *SubpathRecord) void {
            subpath_record.curve_offsets.end = @intCast(self.curve_records.items.len);
        }

        pub fn closeSubpathIntersections(self: *@This(), subpath_record: *SubpathRecord) void {
            subpath_record.intersection_offsets.end = @intCast(self.grid_intersections.items.len);
        }

        pub fn addCurve(self: *@This()) !*CurveRecord {
            const curve = try self.curve_records.addOne(self.allocator);
            curve.* = CurveRecord{};
            return curve;
        }

        pub fn openCurveItems(self: *@This(), curve_record: *CurveRecord) void {
            curve_record.item_offsets = RangeU32{
                .start = @intCast(self.items.items.len),
                .end = @intCast(self.items.items.len),
            };
        }

        pub fn closeCurveItems(self: *@This(), curve_record: *CurveRecord) void {
            curve_record.item_offsets.end = @intCast(self.items.items.len);
        }

        pub fn addCurveEstimate(self: *@This()) !*u32 {
            return try self.curve_estimates.addOne(self.allocator);
        }

        pub fn addCurveEstimates(self: *@This(), n: usize) ![]u32 {
            return try self.curve_estimates.addManyAsSlice(self.allocator, n);
        }

        pub fn addBaseEstimate(self: *@This()) !*u32 {
            return try self.base_estimates.addOne(self.allocator);
        }

        pub fn addBaseEstimates(self: *@This(), n: usize) ![]u32 {
            return try self.base_estimates.addManyAsSlice(self.allocator, n);
        }

        pub fn addItem(self: *@This()) !*T {
            return try self.items.addOne(self.allocator);
        }

        pub fn addItems(self: *@This(), n: usize) ![]T {
            return try self.items.addManyAsSlice(self.allocator, n);
        }

        pub fn addFillJob(self: *@This()) !*FillJob {
            return try self.fill_jobs.addOne(self.allocator);
        }

        pub fn addFillJobs(self: *@This(), n: usize) ![]FillJob {
            return try self.fill_jobs.addManyAsSlice(self.allocator, n);
        }

        pub fn addStrokeJob(self: *@This()) !*FillJob {
            return try self.stroke_jobs.addOne(self.allocator);
        }

        pub fn addStrokeJobs(self: *@This(), n: usize) ![]StrokeJob {
            return try self.stroke_jobs.addManyAsSlice(self.allocator, n);
        }

        pub fn addGridIntersection(self: *@This()) !*GridIntersection {
            return try self.grid_intersections.addOne(self.allocator);
        }

        pub fn addGridIntersections(self: *@This(), n: usize) ![]GridIntersection {
            return try self.grid_intersections.addManyAsSlice(self.allocator, n);
        }

        pub fn addBoundaryFragment(self: *@This()) !*BoundaryFragment {
            return try self.boundary_fragments.addOne(self.allocator);
        }

        pub fn addBoundaryFragments(self: *@This(), n: usize) ![]BoundaryFragment {
            return try self.boundary_fragments.addManyAsSlice(self.allocator, n);
        }

        pub fn addMergeFragment(self: *@This()) !*MergeFragment {
            return try self.merge_fragments.addOne(self.allocator);
        }

        pub fn addMergeFragments(self: *@This(), n: usize) ![]MergeFragment {
            return try self.merge_fragments.addManyAsSlice(self.allocator, n);
        }

        pub fn addSpan(self: *@This()) !*Span {
            return try self.spans.addOne(self.allocator);
        }

        pub fn addSpans(self: *@This(), n: usize) !*Span {
            return try self.spans.addManyAsSlice(self.allocator, n);
        }
    };
}

pub const LineSoup = Soup(Line);
