const std = @import("std");
const core = @import("../core/root.zig");
const encoding_module = @import("./encoding.zig");
const RangeU32 = core.RangeU32;
const PathTag = encoding_module.PathTag;
const PathMonoid = encoding_module.PathMonoid;
const SegmentData = encoding_module.SegmentData;
const TransformF32 = core.TransformF32;
const PointF32 = core.PointF32;
const LineF32 = core.LineF32;
const LineI16 = core.LineI16;
const ArcF32 = core.ArcF32;
const ArcI16 = core.ArcI16;
const QuadraticBezierF32 = core.QuadraticBezierF32;
const QuadraticBezierI16 = core.QuadraticBezierI16;
const CubicBezierF32 = core.CubicBezierF32;
const CubicBezierI16 = core.CubicBezierI16;

pub const KernelConfig = struct {
    pub const DEFAULT: @This() = init(@This(){});

    parallelism: u8 = 8,
    chunk_size: u8 = 8,

    k1_threshold: f32 = 1e-3,
    distance_threshold: f32 = 1e-3,
    break1: f32 = 0.8,
    break2: f32 = 1.25,
    break3: f32 = 2.1,
    sin_scale: f32 = 1.0976991822760038,
    quad_a1: f32 = 0.6406,
    quad_b1: f32 = -0.81,
    quad_c1: f32 = 0.9148117935952064,
    quad_a2: f32 = 0.5,
    quad_b2: f32 = -0.156,
    quad_c2: f32 = 0.16145779359520596,
    robust_eps: f32 = 2e-7,

    derivative_threshold: f32 = 1e-6,
    derivative_threshold_pow2: f32 = 0.0,
    derivative_eps: f32 = 1e-6,
    error_tolerance: f32 = 0.125,
    subdivision_limit: f32 = 1.0 / 65536.0,

    tangent_threshold: f32 = 1e-6,
    tangent_threshold_pow2: f32 = 0.0,
    min_theta: f32 = 0.0001,
    min_theta2: f32 = 1e-6,

    pub fn init(config: @This()) @This() {
        return @This(){
            .parallelism = config.parallelism,
            .chunk_size = config.chunk_size,
            .arcs_enabled = config.arcs_enabled,

            .k1_threshold = config.k1_threshold,
            .distance_threshold = config.distance_threshold,
            .break1 = config.break1,
            .break2 = config.break2,
            .break3 = config.break3,
            .sin_scale = config.sin_scale,
            .quad_a1 = config.quad_a1,
            .quad_b1 = config.quad_b1,
            .quad_c1 = config.quad_c1,
            .quad_a2 = config.quad_a2,
            .quad_b2 = config.quad_b2,
            .quad_c2 = config.quad_c2,
            .robust_eps = config.robust_eps,

            .derivative_threshold = config.derivative_threshold,
            .derivative_threshold_pow2 = std.math.pow(f32, config.derivative_threshold, 2.0),
            .derivative_eps = config.derivative_eps,
            .error_tolerance = config.error_tolerance,
            .subdivision_limit = config.subdivision_limit,

            .tangent_threshold = config.tangent_threshold,
            .tangent_threshold_pow2 = std.math.pow(f32, config.tangent_threshold, 2.0),
            .min_theta = config.min_theta,
            .min_theta2 = config.min_theta2,
        };
    }
};

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
    const VIRTUAL_INTERSECTIONS: u32 = 2;
    const INTERSECTION_FUDGE: u32 = 2;

    pub fn estimate(
        config: KernelConfig,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        segment_data: []const u8,
        range: RangeU32,
        // outputs
        estimates: []SegmentEstimate,
    ) void {
        _ = config;
        _ = segment_data;
        _ = estimates;
        for (range.start..range.end) |index| {
            const path_tag = path_tags[index];
            const path_monoid = path_monoids[index];
            // const estimate = &estimates[index];

            _ = path_tag;
            _ = path_monoid;
            // _ = estimate;
        }
    }

    fn estimateCurveBase(
        path_tag: PathTag,
        path_monoid: PathMonoid,
        transform: TransformF32.Affine,
        segment_data: SegmentData,
    ) u32 {
        var se = SegmentEstimate{};

        switch (path_tag.segment.kind) {
            .line_f32 => {
                const line = segment_data.getSegment(LineF32, path_monoid).affineTransform(transform);
                se.lines += 1;
                se.intersections += estimateLineIntersections(line);
            },
            .line_i16 => {
                const line = segment_data.getSegment(LineI16, path_monoid).cast(f32).affineTransform(transform);
                se.lines += 1;
                se.intersections += estimateLineIntersections(line);
            },
            .arc_f32 => {
                const arc = segment_data.getSegment(ArcF32, path_monoid).affineTransform(transform);
                se.lines += estimateArcLines(arc);
                se.intersections += estimateLineIntersections(arc);
            },
            .arc_i16 => {
                const arc = segment_data.getSegment(ArcI16, path_monoid).cast(f32).affineTransform(transform);
                se.lines += estimateArcLines(arc);
                se.intersections += estimateLineIntersections(arc);
            },
            .quadratic_bezier_f32 => {
                const qb = segment_data.getSegment(QuadraticBezierF32, path_monoid).affineTransform(transform);
                se.lines += estimateQuadraticBezierLines(qb);
                se.intersections += estimateQuadraticBezierIntersections(qb);
            },
            .quadratic_bezier_i16 => {
                const qb = segment_data.getSegment(QuadraticBezierF32, path_monoid).cast(f32).affineTransform(transform);
                se.lines += estimateQuadraticBezierLines(qb);
                se.intersections += estimateQuadraticBezierIntersections(qb);
            },
            .cubic_bezier_f32 => {
                const cb = segment_data.getSegment(CubicBezierF32, path_monoid).affineTransform(transform);
                se.lines += estimateCubicBezierLines(cb);
                se.intersections += estimateQuadraticBezierIntersections(cb);
            },
            .cubic_bezier_i16 => {
                const cb = segment_data.getSegment(CubicBezierI16, path_monoid).cast(f32).affineTransform(transform);
                se.lines += estimateCubicBezierLines(cb);
                se.intersections += estimateQuadraticBezierIntersections(cb);
            },
        }

        return se;
    }

    // fn estimateCurveCap(
    //     config: KernelConfig,
    //     curve: shape_module.Curve,
    //     stroke: Style.Stroke,
    //     scaled_width: f32,
    // ) u32 {
    //     switch (curve.cap) {
    //         .start => {
    //             return estimateStrokeCap(config, stroke.start_cap, scaled_width);
    //         },
    //         .end => {
    //             return estimateStrokeCap(config, stroke.end_cap, scaled_width);
    //         },
    //         .none => {
    //             return 0;
    //         },
    //     }
    // }

    // fn estimateStrokeCap(config: KernelConfig, cap: Style.Cap, scaled_width: f32) u32 {
    //     switch (cap) {
    //         .butt => {
    //             return @as(u32, @intFromFloat(LineEstimatorImpl.estimateLineLengthItems(scaled_width)));
    //         },
    //         .square => {
    //             var items = @as(u32, @intFromFloat(LineEstimatorImpl.estimateLineLengthItems(scaled_width)));
    //             items += 2 * @as(u32, @intFromFloat(LineEstimatorImpl.estimateLineLengthItems(0.5 * scaled_width)));
    //             return items;
    //         },
    //         .round => {
    //             const arc_estimate: ArcEstimate = LineEstimatorImpl.estimateArc(config, scaled_width);
    //             return arc_estimate.items;
    //         },
    //     }
    // }

    // fn estimateStrokeJoin(config: KernelConfig, join: Style.Join, scaled_width: f32, miter_limit: f32) u32 {
    //     const inner_estimate = @as(u32, @intFromFloat(LineEstimatorImpl.estimateLineLengthItems(scaled_width)));
    //     var outer_estimate: u32 = 0;

    //     switch (join) {
    //         .bevel => {
    //             outer_estimate += @as(u32, @intFromFloat(LineEstimatorImpl.estimateLineLengthItems(scaled_width)));
    //         },
    //         .miter => {
    //             const max_miter_len = scaled_width * miter_limit;
    //             outer_estimate += @as(u32, @intFromFloat(LineEstimatorImpl.estimateLineLengthItems(max_miter_len))) * 2;
    //         },
    //         .round => {
    //             const arc_estimate: ArcEstimate = LineEstimatorImpl.estimateArc(config, scaled_width);
    //             outer_estimate += @as(u32, @intFromFloat(LineEstimatorImpl.estimateLineLengthItems(arc_estimate.length))) * arc_estimate.items;
    //         },
    //     }

    //     return @max(inner_estimate, outer_estimate);
    // }

    pub fn estimateArcLines(arc: ArcF32) u32 {
        _ = arc;
    }

    pub fn estimateQuadraticBezierLines(quadratic_bezier: QuadraticBezierF32) u32 {
        _ = quadratic_bezier;
    }

    pub fn estimateCubicBezierLines(cubic_bezier: CubicBezierF32) u32 {
        _ = cubic_bezier;
    }

    pub fn estimateLineIntersections(line: LineF32) u32 {
        const dxdy = line.p1.sub(line.p0);
        const intersections: u32 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        return @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;
    }

    pub fn estimateArcIntersections(arc: ArcF32) u32 {
        _ = arc;
        // const dxdy = p1.sub(p0);
        // const intersections: u32 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        // return @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;
    }

    pub fn estimateQuadraticBezierIntersections(quadratic_bezier: QuadraticBezierF32) u32 {
        _ = quadratic_bezier;
        // const dxdy = p1.sub(p0);
        // const intersections: u32 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        // return @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;
    }

    pub fn estimateCubicBezierIntersections(cubic_bezier: CubicBezierF32) u32 {
        _ = cubic_bezier;
        // const dxdy = p1.sub(p0);
        // const intersections: u32 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        // return @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;
    }
};

pub const Flatten = struct {
    pub fn fill(
        config: KernelConfig,
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
        _ = config;
        _ = path_tags;
        _ = path_monoids;
        _ = segment_data;
        _ = range;
        _ = flat_path_mask;
        _ = flat_path_tags;
        _ = flat_path_monoids;
        _ = flat_segment_data;
    }

    pub fn stroke(
        config: KernelConfig,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        segment_data: []const u8,
        range: RangeU32,
        // outputs
        // true if path is used, false to ignore
        flat_path_mask: []bool,
        flat_path_tags: []PathTag, // 2x path_tags for left/right
        flat_path_monoids: []PathMonoid, // 2x path_tags for left/right
        flat_segment_data: []u8,
    ) void {
        _ = config;
        _ = path_tags;
        _ = path_monoids;
        _ = segment_data;
        _ = range;
        _ = flat_path_mask;
        _ = flat_path_tags;
        _ = flat_path_monoids;
        _ = flat_segment_data;
    }
};

pub const Rasterize = struct {
    // scanlineFill(
    //   path_masks,
    //   path_tags,
    //   path_monoids,
    //   segment data,
    //   grid_intersections,
    //   boundary_fragments,
    //   merge_fragments,
    //   spans,
    // )
};
