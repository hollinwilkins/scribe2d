const std = @import("std");
const core = @import("../core/root.zig");
const encoding_module = @import("./encoding.zig");
const RangeU32 = core.RangeU32;
const PathTag = encoding_module.PathTag;
const PathMonoid = encoding_module.PathMonoid;
const SegmentData = encoding_module.SegmentData;
const Style = encoding_module.Style;
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

pub const Estimates = packed struct {
    lines: u16 = 0,
    intersections: u16 = 0,

    pub fn combine(self: @This(), other: @This()) @This() {
        return @This(){
            .lines = self.lines + other.lines,
            .intersections = self.intersections + other.intersections,
        };
    }
};

pub const SegmentEstimate = packed struct {
    estimates: Estimates = Estimates{},
    cap_estimates: Estimates = Estimates{},
    join_estimates: Estimates = Estimates{},

    pub fn combine(self: @This(), other: @This()) @This() {
        return @This(){
            .estimates = self.estimates.combine(other.estimates),
            .cap_estimates = self.estimates.combine(other.cap_estimates),
            .join_estimates = self.estimates.combine(other.join_estimates),
        };
    }
};

pub const Estimate = struct {
    const VIRTUAL_INTERSECTIONS: u32 = 2;
    const INTERSECTION_FUDGE: u32 = 2;

    pub const RoundArcEstimate = struct {
        items: u32 = 0,
        length: f32 = 0.0,
    };

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
        config: KernelConfig,
        path_tag: PathTag,
        path_monoid: PathMonoid,
        style: Style,
        transform: TransformF32.Affine,
        segment_data: SegmentData,
    ) u32 {
        var se = SegmentEstimate{};

        if (style.isStroke()) {
            const stroke = style.stroke;
            const scaled_width = @max(1.0, stroke.width) * transform.getScale();
            se.cap_lines += estimateCapLines(config, path_tag, style.stroke, scaled_width);
            se.join_lines += estimateJoinLines(config, style.stroke, scaled_width);
        }

        switch (path_tag.segment.kind) {
            .line_f32 => {
                const line = segment_data.getSegment(LineF32, path_monoid).affineTransform(transform);
                se.estimates = estimateLine(line);
            },
            .line_i16 => {
                const line = segment_data.getSegment(LineI16, path_monoid).cast(f32).affineTransform(transform);
                se.estimates = estimateLine(line);
            },
            .arc_f32 => {
                const arc = segment_data.getSegment(ArcF32, path_monoid).affineTransform(transform);
                se.estimates = estimateArc(arc);
            },
            .arc_i16 => {
                const arc = segment_data.getSegment(ArcI16, path_monoid).cast(f32).affineTransform(transform);
                se.estimates = estimateArc(arc);
            },
            .quadratic_bezier_f32 => {
                const qb = segment_data.getSegment(QuadraticBezierF32, path_monoid).affineTransform(transform);
                se.estimates = estimateQuadraticBezier(qb);
            },
            .quadratic_bezier_i16 => {
                const qb = segment_data.getSegment(QuadraticBezierF32, path_monoid).cast(f32).affineTransform(transform);
                se.estimates = estimateQuadraticBezier(qb);
            },
            .cubic_bezier_f32 => {
                const cb = segment_data.getSegment(CubicBezierF32, path_monoid).affineTransform(transform);
                se.estimates = estimateQuadraticBezier(cb);
            },
            .cubic_bezier_i16 => {
                const cb = segment_data.getSegment(CubicBezierI16, path_monoid).cast(f32).affineTransform(transform);
                se.estimates = estimateQuadraticBezier(cb);
            },
        }

        return se;
    }

    pub fn estimateJoinLines(config: KernelConfig, stroke: Style.Stroke, scaled_width: f32) u32 {
        switch (stroke.join) {
            .bevel => {
                return 1;
            },
            .miter => {
                return 2;
            },
            .round => {
                return estimateRoundArc(config, scaled_width).items;
            },
        }
    }

    pub fn estimateCapLines(config: KernelConfig, path_tag: PathTag, stroke: Style.Stroke, scaled_width: f32) u32 {
        if (path_tag.segment.cap) {
            const is_end_cap = path_tag.segment.subpath_end;
            const cap = if (is_end_cap) stroke.end_cap else stroke.start_cap;

            switch (cap) {
                .butt => {
                    return 1;
                },
                .square => {
                    return 3;
                },
                .round => {
                    return estimateRoundArc(config, scaled_width).items;
                },
            }
        }
    }

    pub fn estimateLineWidth(scaled_width: f32) Estimates {
        const dxdy = PointF32{
            .x = scaled_width,
            .y = scaled_width,
        };
        var intersections: u32 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        intersections = @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;

        return Estimates{
            .lines = 1,
            .intersections = intersections,
        };
    }

    pub fn estimateLine(line: LineF32) Estimates {
        const dxdy = line.p1.sub(line.p0);
        var intersections: u32 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        intersections = @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;

        return Estimates{
            .lines = 1,
            .intersections = intersections,
        };
    }

    pub fn estimateArc(arc: ArcF32) Estimates {
        _ = arc;
        return Estimates{};
    }

    pub fn estimateQuadraticBezier(quadratic_bezier: QuadraticBezierF32) Estimates {
        _ = quadratic_bezier;
        return Estimates{};
    }

    pub fn estimateCubicBezier(cubic_bezier: CubicBezierF32) Estimates {
        _ = cubic_bezier;
        return Estimates{};
    }

    fn estimateRoundArc(config: KernelConfig, scaled_width: f32) RoundArcEstimate {
        const radius = @max(config.error_tolerance, scaled_width * 0.5);
        const theta = @max(config.min_theta2, (2.0 * std.math.acos(1.0 - config.error_tolerance / radius)));
        const arc_lines = @max(2, @as(u32, @intFromFloat(@ceil((std.math.pi / 2.0) / theta))));

        return RoundArcEstimate{
            .items = arc_lines,
            .length = 2.0 * std.math.sin(theta) * radius,
        };
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
