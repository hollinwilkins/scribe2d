const std = @import("std");
const core = @import("../core/root.zig");
const shape_module = @import("./shape.zig");
const pen_module = @import("./pen.zig");
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
const Path = shape_module.Path;
const PathBuilder = shape_module.PathBuilder;
const PathMetadata = shape_module.PathMetadata;
const Shape = shape_module.Shape;
const Style = pen_module.Style;
const Line = curve_module.Line;
const Arc = curve_module.Arc;
const Intersection = curve_module.Intersection;
const CubicPoints = euler.CubicPoints;
const CubicParams = euler.CubicParams;
const EulerParams = euler.EulerParams;
const EulerSegment = euler.EulerSegment;
const Scene = scene_module.Scene;
const HalfPlanesU16 = msaa.HalfPlanesU16;

pub const FlatPath = struct {
    fill: Style.Fill = Style.Fill{},
    flat_subpath_offsets: RangeU32 = RangeU32{},
    boundary_offsets: RangeU32 = RangeU32{},
    merge_offsets: RangeU32 = RangeU32{},
    span_offsets: RangeU32 = RangeU32{},
};

pub const FlatSubpath = struct {
    flat_curve_offsets: RangeU32 = RangeU32{},
};

pub const FlatCurve = struct {
    line_offsets: RangeU32 = RangeU32{},
    intersection_offsets: RangeU32 = RangeU32{},
};

pub const FillJob = struct {
    // index in the source Shape struct for the curve data
    transform_index: u32 = 0,
    curve_index: u32 = 0,
    flat_curve_index: u32 = 0,
};

pub const StrokeJob = struct {
    // index in the source Shape struct for the curve data
    transform_index: u32 = 0,
    style_index: u32 = 0,
    subpath_index: u32 = 0,
    curve_index: u32 = 0,
    left_flat_curve_index: u32 = 0,
    right_flat_curve_index: u32 = 0,
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

pub const Soup = struct {
    pub const FlatPathList = std.ArrayListUnmanaged(FlatPath);
    pub const FlatSubpathList = std.ArrayListUnmanaged(FlatSubpath);
    pub const FlatCurveList = std.ArrayListUnmanaged(FlatCurve);
    pub const EstimateList = std.ArrayListUnmanaged(u32);
    pub const FillJobList = std.ArrayListUnmanaged(FillJob);
    pub const StrokeJobList = std.ArrayListUnmanaged(StrokeJob);
    pub const LineList = std.ArrayListUnmanaged(Line);
    pub const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
    pub const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);
    pub const MergeFragmentList = std.ArrayListUnmanaged(MergeFragment);
    pub const SpanList = std.ArrayListUnmanaged(Span);

    allocator: Allocator,
    flat_paths: FlatPathList = FlatPathList{},
    flat_subpaths: FlatSubpathList = FlatSubpathList{},
    flat_curves: FlatCurveList = FlatCurveList{},
    flat_curve_estimates: EstimateList = EstimateList{},
    base_estimates: EstimateList = EstimateList{},
    fill_jobs: FillJobList = FillJobList{},
    stroke_jobs: StrokeJobList = StrokeJobList{},
    lines: LineList = LineList{},
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
        self.flat_paths.deinit(self.allocator);
        self.flat_subpaths.deinit(self.allocator);
        self.flat_curves.deinit(self.allocator);
        self.flat_curve_estimates.deinit(self.allocator);
        self.base_estimates.deinit(self.allocator);
        self.fill_jobs.deinit(self.allocator);
        self.stroke_jobs.deinit(self.allocator);
        self.lines.deinit(self.allocator);
        self.grid_intersections.deinit(self.allocator);
        self.boundary_fragments.deinit(self.allocator);
        self.merge_fragments.deinit(self.allocator);
        self.spans.deinit(self.allocator);
    }

    pub fn addFlatPath(self: *@This()) !*FlatPath {
        const path = try self.flat_paths.addOne(self.allocator);
        path.* = FlatPath{};
        return path;
    }

    pub fn openFlatPathSubpaths(self: @This(), flat_path: *FlatPath) void {
        flat_path.flat_subpath_offsets.start = @intCast(self.flat_subpaths.items.len);
    }

    pub fn openFlatPathBoundaries(self: *@This(), flat_path: *FlatPath) void {
        flat_path.boundary_offsets.start = @intCast(self.boundary_fragments.items.len);
    }

    pub fn openFlatPathMerges(self: *@This(), flat_path: *FlatPath) void {
        flat_path.merge_offsets.start = @intCast(self.merge_fragments.items.len);
    }

    pub fn openFlatPathSpans(self: *@This(), flat_path: *FlatPath) void {
        flat_path.span_offsets.start = @intCast(self.spans.items.len);
    }

    pub fn closeFlatPathSubpaths(self: @This(), flat_path: *FlatPath) void {
        flat_path.flat_subpath_offsets.end = @intCast(self.flat_subpaths.items.len);
    }

    pub fn closeFlatPathBoundaries(self: *@This(), flat_path: *FlatPath) void {
        flat_path.boundary_offsets.end = @intCast(self.boundary_fragments.items.len);
    }

    pub fn closeFlatPathMerges(self: *@This(), flat_path: *FlatPath) void {
        flat_path.merge_offsets.end = @intCast(self.merge_fragments.items.len);
    }

    pub fn closeFlatPathSpans(self: *@This(), flat_path: *FlatPath) void {
        flat_path.span_offsets.end = @intCast(self.spans.items.len);
    }

    pub fn addFlatSubpath(self: *@This()) !*FlatSubpath {
        const subpath = try self.flat_subpaths.addOne(self.allocator);
        subpath.* = FlatSubpath{};
        return subpath;
    }

    pub fn openFlatSubpathCurves(self: @This(), flat_subpath: *FlatSubpath) void {
        flat_subpath.flat_curve_offsets.start = @intCast(self.flat_curves.items.len);
    }

    pub fn closeFlatSubpathCurves(self: @This(), flat_subpath: *FlatSubpath) void {
        flat_subpath.flat_curve_offsets.end = @intCast(self.flat_curves.items.len);
    }

    pub fn addFlatCurve(self: *@This()) !*FlatCurve {
        const curve = try self.flat_curves.addOne(self.allocator);
        curve.* = FlatCurve{};
        return curve;
    }

    pub fn openFlatCurveItems(self: *@This(), curve: *FlatCurve) void {
        curve.line_offsets.start = @intCast(self.lines.items.len);
    }

    pub fn openFlatCurveIntersections(self: *@This(), curve: *FlatCurve) void {
        curve.intersection_offsets.start = @intCast(self.grid_intersections.items.len);
    }

    pub fn closeFlatCurveItems(self: *@This(), curve: *FlatCurve) void {
        curve.line_offsets.end = @intCast(self.lines.items.len);
    }

    pub fn closeFlatCurveIntersections(self: *@This(), curve: *FlatCurve) void {
        curve.intersection_offsets.end = @intCast(self.grid_intersections.items.len);
    }

    pub fn addFlatCurveEstimate(self: *@This()) !*u32 {
        return try self.flat_curve_estimates.addOne(self.allocator);
    }

    pub fn addFlatCurveEstimates(self: *@This(), n: usize) ![]u32 {
        return try self.flat_curve_estimates.addManyAsSlice(self.allocator, n);
    }

    pub fn addBaseEstimate(self: *@This()) !*u32 {
        return try self.base_estimates.addOne(self.allocator);
    }

    pub fn addBaseEstimates(self: *@This(), n: usize) ![]u32 {
        return try self.base_estimates.addManyAsSlice(self.allocator, n);
    }

    pub fn addLine(self: *@This()) !*Line {
        return try self.lines.addOne(self.allocator);
    }

    pub fn addLines(self: *@This(), n: usize) ![]Line {
        return try self.lines.addManyAsSlice(self.allocator, n);
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

    pub fn addSpans(self: *@This(), n: usize) ![]Span {
        return try self.spans.addManyAsSlice(self.allocator, n);
    }

    pub fn assertFlatSubpaths(self: @This()) bool {
        for (self.flat_subpaths.items) |flat_subpath| {
            const flat_curves = self.flat_curves.items[flat_subpath.flat_curve_offsets.start..flat_subpath.flat_curve_offsets.end];
            for (flat_curves, 0..) |flat_curve, flat_curve_index| {
                const lines = self.lines.items[flat_curve.line_offsets.start..flat_curve.line_offsets.end];
                for (lines, 0..) |line, line_index| {
                    const next_line_index = line_index + 1;
                    var next_line: Line = undefined;

                    if (next_line_index >= lines.len) {
                        // next line is in the next flat curve
                        const next_flat_curve = flat_curves[(flat_curve_index + 1) % flat_curves.len];
                        next_line = self.lines.items[next_flat_curve.line_offsets.start];
                    } else {
                        next_line = lines[next_line_index];
                    }

                    const end_point = line.end;
                    const start_point = next_line.start;
                    if (!std.meta.eql(start_point, end_point)) {
                        std.debug.assert(false);
                        return false;
                    }
                }
            }
        }

        return true;
    }
};
