const std = @import("std");
const core = @import("../core/root.zig");
const encoding_module = @import("./encoding.zig");
const euler_module = @import("./euler.zig");
const RangeU32 = core.RangeU32;
const PathTag = encoding_module.PathTag;
const PathMonoid = encoding_module.PathMonoid;
const SegmentData = encoding_module.SegmentData;
const Style = encoding_module.Style;
const MonoidFunctions = encoding_module.MonoidFunctions;
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
const CubicPoints = euler_module.CubicPoints;
const CubicParams = euler_module.CubicParams;
const EulerParams = euler_module.EulerParams;
const EulerSegment = euler_module.EulerSegment;

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

pub const EstimateOffsets = packed struct {
    line_offset: u32 = 0,
    intersection_offest: u32 = 0,

    pub usingnamespace MonoidFunctions(SegmentEstimate, @This());

    pub fn createTag(estimates: Estimates) @This() {
        return @This(){
            .line_offset = estimates.lines,
            .intersection_offest = estimates.intersections,
        };
    }

    pub fn mulScalar(self: @This(), scalar: f32) @This() {
        return @This(){
            .line_offset = @intFromFloat(@ceil(@as(f32, @floatFromInt(self.line_offset)) * scalar)),
            .intersection_offest = @intFromFloat(@ceil(@as(f32, @floatFromInt(self.intersection_offest)) * scalar)),
        };
    }

    pub fn combine(self: @This(), other: @This()) @This() {
        return @This(){
            .line_offset = self.line_offset + other.line_offset,
            .intersection_offest = self.intersection_offest + other.intersection_offest,
        };
    }
};

pub const SegmentEstimate = packed struct {
    estimates: Estimates = Estimates{},
    cap_estimates: Estimates = Estimates{},
    join_estimates: Estimates = Estimates{},
    stroke_fudge: f32 = 0.0,
};

pub const SegmentOffsets = packed struct {
    fill: EstimateOffsets = EstimateOffsets{},
    front_stroke: EstimateOffsets = EstimateOffsets{},
    back_stroke: EstimateOffsets = EstimateOffsets{},

    pub usingnamespace MonoidFunctions(SegmentEstimate, @This());

    pub fn createTag(segment_estimate: SegmentEstimate) @This() {
        const fill = EstimateOffsets.createTag(segment_estimate.estimates);
        const stroke = fill.mulScalar(segment_estimate.stroke_fudge);
        const front_stroke = stroke.combine(
            EstimateOffsets.createTag(segment_estimate.cap_estimates),
        ).combine(
            EstimateOffsets.createTag(segment_estimate.join_estimates),
        );
        const back_stroke = front_stroke.combine(stroke);

        return @This(){
            .fill = EstimateOffsets.createTag(segment_estimate.estimates),
            .front_stroke = front_stroke,
            .back_stroke = back_stroke,
        };
    }

    pub fn combine(self: @This(), other: @This()) @This() {
        return @This(){
            .fill = self.fill.combine(other.fill),
            .front_stroke = self.front_stroke.combine(other.front_stroke),
            .back_stroke = self.back_stroke.combine(other.back_stroke),
        };
    }
};

pub const Estimate = struct {
    const VIRTUAL_INTERSECTIONS: u16 = 2;
    const INTERSECTION_FUDGE: u16 = 2;
    const RSQRT_OF_TOL: f64 = 2.2360679775; // tol = 0.2

    pub const RoundArcEstimate = struct {
        lines: u16 = 0,
        length: f32 = 0.0,
    };

    pub fn estimateSegments(
        config: KernelConfig,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        styles: []const Style,
        transforms: []const TransformF32.Affine,
        segment_data: []const u8,
        range: RangeU32,
        // outputs
        estimates: []SegmentEstimate,
    ) void {
        for (range.start..range.end) |index| {
            const path_tag = path_tags[index];
            const path_monoid = path_monoids[index];
            const style = styles[path_monoid.style_index];
            const transform = transforms[path_monoid.transform_index];
            const sd = SegmentData{
                .segment_data = segment_data,
            };

            estimates[index] = estimateSegment(
                config,
                path_tag,
                path_monoid,
                style,
                transform,
                sd,
            );
        }
    }

    fn estimateSegment(
        config: KernelConfig,
        path_tag: PathTag,
        path_monoid: PathMonoid,
        style: Style,
        transform: TransformF32.Affine,
        segment_data: SegmentData,
    ) SegmentEstimate {
        var se = SegmentEstimate{};

        if (style.isStroke()) {
            // TODO: this still seems wrong
            const scale = transform.getScale() * 0.5;
            const stroke = style.stroke;
            const scaled_width = @max(1.0, stroke.width) * scale;
            se.cap_estimates = estimateCap(config, path_tag, stroke, scaled_width);
            se.join_estimates = estimateJoin(config, stroke, scaled_width);
            se.stroke_fudge = @max(1.0, std.math.sqrt(scaled_width));
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
                se.estimates = estimateArc(config, arc);
            },
            .arc_i16 => {
                const arc = segment_data.getSegment(ArcI16, path_monoid).cast(f32).affineTransform(transform);
                se.estimates = estimateArc(config, arc);
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
                se.estimates = estimateCubicBezier(cb);
            },
            .cubic_bezier_i16 => {
                const cb = segment_data.getSegment(CubicBezierI16, path_monoid).cast(f32).affineTransform(transform);
                se.estimates = estimateCubicBezier(cb);
            },
        }

        return se;
    }

    pub fn estimateJoin(config: KernelConfig, stroke: Style.Stroke, scaled_width: f32) Estimates {
        switch (stroke.join) {
            .bevel => {
                return Estimates{
                    .lines = 1,
                    .intersections = estimateLineWidthIntersections(scaled_width),
                };
            },
            .miter => {
                const MITER_FUDGE: u16 = 2;
                return Estimates{
                    .lines = 2,
                    .intersections = estimateLineWidthIntersections(scaled_width) * 2 * MITER_FUDGE,
                };
            },
            .round => {
                const arc_estimate = estimateRoundArc(config, scaled_width);
                return Estimates{
                    .lines = arc_estimate.lines,
                    .intersections = estimateLineWidthIntersections(arc_estimate.length),
                };
            },
        }
    }

    pub fn estimateCap(config: KernelConfig, path_tag: PathTag, stroke: Style.Stroke, scaled_width: f32) Estimates {
        if (path_tag.segment.cap) {
            const is_end_cap = path_tag.segment.subpath_end;
            const cap = if (is_end_cap) stroke.end_cap else stroke.start_cap;

            switch (cap) {
                .butt => {
                    return Estimates{
                        .lines = 1,
                        .intersections = estimateLineWidthIntersections(scaled_width),
                    };
                },
                .square => {
                    return Estimates{
                        .lines = 3,
                        .intersections = estimateLineWidthIntersections(scaled_width) * 2,
                    };
                },
                .round => {
                    const arc_estimate = estimateRoundArc(config, scaled_width);
                    return Estimates{
                        .lines = arc_estimate.lines,
                        .intersections = estimateLineWidthIntersections(arc_estimate.length),
                    };
                },
            }
        }

        return Estimates{};
    }

    pub fn estimateLineWidth(scaled_width: f32) Estimates {
        return Estimates{
            .lines = 1,
            .intersections = estimateLineWidthIntersections(scaled_width),
        };
    }

    pub fn estimateLineWidthIntersections(scaled_width: f32) u16 {
        const dxdy = PointF32{
            .x = scaled_width,
            .y = scaled_width,
        };

        const intersections: u16 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        return @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;
    }

    pub fn estimateLine(line: LineF32) Estimates {
        const dxdy = line.p1.sub(line.p0);
        var intersections: u16 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        intersections = @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;

        return Estimates{
            .lines = 1,
            .intersections = intersections,
        };
    }

    pub fn estimateArc(config: KernelConfig, arc: ArcF32) Estimates {
        const width = arc.p0.sub(arc.p1).length() + arc.p2.sub(arc.p1).length();
        const arc_estimate = estimateRoundArc(config, width);

        return Estimates{
            .lines = arc_estimate.lines,
            .intersections = estimateLineWidthIntersections(arc_estimate.length),
        };
    }

    pub fn estimateQuadraticBezier(quadratic_bezier: QuadraticBezierF32) Estimates {
        const lines = @as(u16, @intFromFloat(Wang.quadratic(
            @floatCast(RSQRT_OF_TOL),
            quadratic_bezier.p0,
            quadratic_bezier.p1,
            quadratic_bezier.p2,
        )));
        const intersections = estimateStepCurveIntersections(
            QuadraticBezierF32,
            quadratic_bezier,
            quadratic_bezier.p0,
            quadratic_bezier.p2,
            lines,
        );

        return Estimates{
            .lines = lines,
            .intersections = intersections,
        };
    }

    pub fn estimateCubicBezier(cubic_bezier: CubicBezierF32) Estimates {
        const lines = @as(u16, @intFromFloat(Wang.cubic(
            @floatCast(RSQRT_OF_TOL),
            cubic_bezier.p0,
            cubic_bezier.p1,
            cubic_bezier.p2,
            cubic_bezier.p3,
        )));
        const intersections = estimateStepCurveIntersections(
            CubicBezierF32,
            cubic_bezier,
            cubic_bezier.p0,
            cubic_bezier.p2,
            lines,
        );

        return Estimates{
            .lines = lines,
            .intersections = intersections,
        };
    }

    pub fn estimateStepCurveIntersections(comptime T: type, curve: T, start: PointF32, end: PointF32, samples: u16) u16 {
        var intersections: u16 = 0;
        const step = 1.0 / @as(f32, @floatFromInt(samples));

        var p0 = start;
        for (0..samples - 1) |i| {
            const p1 = curve.apply(@as(f32, @floatFromInt(i)) * step);
            intersections += estimateLineWidthIntersections(p1.sub(p0).length());
            p0 = p1;
        }

        const p1 = end;
        intersections += estimateLineWidthIntersections(p1.sub(p0).length());

        return intersections;
    }

    fn estimateRoundArc(config: KernelConfig, scaled_width: f32) RoundArcEstimate {
        const radius = @max(config.error_tolerance, scaled_width * 0.5);
        const theta = @max(config.min_theta2, (2.0 * std.math.acos(1.0 - config.error_tolerance / radius)));
        const arc_lines = @max(2, @as(u16, @intFromFloat(@ceil((std.math.pi / 2.0) / theta))));

        return RoundArcEstimate{
            .lines = arc_lines,
            .length = 2.0 * std.math.sin(theta) * radius,
        };
    }

    pub const Wang = struct {
        // The curve degree term sqrt(n * (n - 1) / 8) specialized for cubics:
        //
        //    sqrt(3 * (3 - 1) / 8)
        //
        const SQRT_OF_DEGREE_TERM_CUBIC: f32 = 0.86602540378;

        // The curve degree term sqrt(n * (n - 1) / 8) specialized for quadratics:
        //
        //    sqrt(2 * (2 - 1) / 8)
        //
        const SQRT_OF_DEGREE_TERM_QUAD: f32 = 0.5;

        pub fn quadratic(rsqrt_of_tol: f32, p0: PointF32, p1: PointF32, p2: PointF32) f32 {
            const v = p1.add(p0).add(p2).mulScalar(-2.0);
            const m = v.length();
            return @ceil(SQRT_OF_DEGREE_TERM_QUAD * std.math.sqrt(m) * rsqrt_of_tol);
        }

        pub fn cubic(rsqrt_of_tol: f32, p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32) f32 {
            const v1 = p1.add(p0).add(p2).mulScalar(-2.0);
            const v2 = p2.add(p1).add(p3).mulScalar(-2.0);
            const m = @max(v1.length(), v2.length());
            return @ceil(SQRT_OF_DEGREE_TERM_CUBIC * std.math.sqrt(m) * rsqrt_of_tol);
        }
    };
};

pub const Flatten = struct {
    pub fn flatten(
        config: KernelConfig,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        styles: []const Style,
        transforms: []const TransformF32.Affine,
        segment_data: []const u8,
        segment_estimates: []const SegmentEstimate,
        segment_offsets: []const SegmentOffsets,
        range: RangeU32,
        // outputs
        // true if path is used, false to ignore
        flat_path_mask: []bool,
        flat_path_tags: []PathTag, // 2x path_tags for left/right
        flat_path_monoids: []PathMonoid, // 2x path_tags for left/right
        flat_segment_data: []u8,
    ) void {
        _ = flat_path_mask;
        _ = flat_path_tags;
        _ = flat_path_monoids;
        _ = transforms;

        for (range.start..range.end) |index| {
            const path_monoid = path_monoids[index];
            const style = styles[path_monoid.style_index];

            if (style.isFill()) {
                fill(
                    config,
                    index,
                    path_tags,
                    path_monoids,
                    segment_estimates,
                    segment_offsets,
                    transforms,
                    segment_data,
                    flat_segment_data,
                );
            }

            if (style.isStroke()) {}
        }
    }

    // pub fn fill(
    //     config: KernelConfig,
    //     segment_index: usize,
    //     path_tags: []const PathTag,
    //     path_monoids: []const PathMonoid,
    //     segment_estimates: []const SegmentEstimate,
    //     segment_offsets: []const SegmentOffsets,
    //     transforms: []const TransformF32.Affine,
    //     segment_data: []const u8,
    //     flat_segment_data: []u8,
    // ) void {
    //     const se = segment_estimates[segment_index];
    //     const so =segment_offsets[segment_index];
    //     var writer = Writer{
    //         .segment_data = flat_segment_data.segment_data[so.fill.line_offset..so.fill.line_offset + se.cap_estimates],
    //     };

    //     // const cubic_points = getCubicPoints(
    //     //     curve,
    //     //     points[curve.point_offsets.start..curve.point_offsets.end],
    //     // );
    // }

    fn flattenEuler(
        config: KernelConfig,
        cubic_points: CubicBezierF32,
        transform: TransformF32.Matrix,
        offset: f32,
        start_point: PointF32,
        end_point: PointF32,
        writer: *Writer,
    ) void {
        const p0 = transform.apply(cubic_points.point0);
        const p1 = transform.apply(cubic_points.point1);
        const p2 = transform.apply(cubic_points.point2);
        const p3 = transform.apply(cubic_points.point3);
        const scale = 0.5 * transform.getScale();

        var t_start: PointF32 = undefined;
        var t_end: PointF32 = undefined;
        if (offset == 0.0) {
            t_start = p0;
            t_end = p3;
        } else {
            t_start = start_point;
            t_end = end_point;
        }

        // Drop zero length lines. This is an exact equality test because dropping very short
        // line segments may result in loss of watertightness. The parallel curves of zero
        // length lines add nothing to stroke outlines, but we still may need to draw caps.
        if (std.meta.eql(p0, p1) and std.meta.eql(p0, p2) and std.meta.eql(p0, p3)) {
            return;
        }

        var t0_u: u32 = 0;
        var dt: f32 = 1.0;
        var last_p = p0;
        var last_q = p1.sub(p0);

        // We want to avoid near zero derivatives, so the general technique is to
        // detect, then sample a nearby t value if it fails to meet the threshold.
        if (last_q.lengthSquared() < config.derivative_threshold_pow2) {
            last_q = evaluateCubicAndDeriv(p0, p1, p2, p3, config.derivative_eps).derivative;
        }
        var last_t: f32 = 0.0;
        var lp0 = t_start;

        while (true) {
            const t0 = @as(f32, @floatFromInt(t0_u)) * dt;
            if (t0 == 1.0) {
                break;
            }
            var t1 = t0 + dt;
            const this_p0 = last_p;
            const this_q0 = last_q;
            const cd1 = evaluateCubicAndDeriv(p0, p1, p2, p3, t1);
            var this_p1 = cd1.point;
            var this_q1 = cd1.derivative;
            if (this_q1.lengthSquared() < config.derivative_threshold_pow2) {
                const cd2 = evaluateCubicAndDeriv(p0, p1, p2, p3, t1 - config.derivative_eps);
                const new_p1 = cd2.point;
                const new_q1 = cd2.derivative;
                this_q1 = new_q1;

                // Change just the derivative at the endpoint, but also move the point so it
                // matches the derivative exactly if in the interior.
                if (t1 < 1.0) {
                    this_p1 = new_p1;
                    t1 -= config.derivative_eps;
                }
            }
            const actual_dt = t1 - last_t;
            const cubic_params = CubicParams.create(this_p0, this_p1, this_q0, this_q1, actual_dt);
            if (cubic_params.err * scale <= config.error_tolerance or dt <= config.subdivision_limit) {
                const euler_params = EulerParams.create(cubic_params.th0, cubic_params.th1);
                const es = EulerSegment{
                    .p0 = this_p0,
                    .p1 = this_p1,
                    .params = euler_params,
                };

                const k0 = es.params.k0 - 0.5 * es.params.k1;
                const k1 = es.params.k1;

                // compute forward integral to determine number of subdivisions
                const normalized_offset = offset / cubic_params.chord_len;
                const dist_scaled = normalized_offset * es.params.ch;

                // The number of subdivisions for curvature = 1
                const scale_multiplier = 0.5 * std.math.sqrt1_2 * std.math.sqrt((scale * cubic_params.chord_len / (es.params.ch * config.error_tolerance)));
                var a: f32 = 0.0;
                var b: f32 = 0.0;
                var integral: f32 = 0.0;
                var int0: f32 = 0.0;

                var n_frac: f32 = undefined;
                var robust: EspcRobust = undefined;

                if (@abs(k1) < config.k1_threshold) {
                    const k = k0 + 0.5 * k1;
                    n_frac = std.math.sqrt(@abs(k * (k * dist_scaled + 1.0)));
                    robust = .low_k1;
                } else if (@abs(dist_scaled) < config.distance_threshold) {
                    a = k1;
                    b = k0;
                    int0 = b * std.math.sqrt(@abs(b));
                    const int1 = (a + b) * std.math.sqrt(@abs(a + b));
                    integral = int1 - int0;
                    n_frac = (2.0 / 3.0) * integral / a;
                    robust = .low_dist;
                } else {
                    a = -2.0 * dist_scaled * k1;
                    b = -1.0 - 2.0 * dist_scaled * k0;
                    int0 = EspcRobust.intApproximation(config, b);
                    const int1 = EspcRobust.intApproximation(config, a + b);
                    integral = int1 - int0;
                    const k_peak = k0 - k1 * b / a;
                    const integrand_peak = std.math.sqrt(@abs(k_peak * (k_peak * dist_scaled + 1.0)));
                    const scaled_int = integral * integrand_peak / a;
                    n_frac = scaled_int;
                    robust = .normal;
                }

                const n = std.math.clamp(@ceil(n_frac * scale_multiplier), 1.0, 100.0);

                // Flatten line segments
                std.debug.assert(!std.math.isNan(n));
                for (0..@intFromFloat(n)) |i| {
                    var lp1: PointF32 = undefined;

                    if (i == (@as(usize, @intFromFloat(n)) - 1) and t1 == 1.0) {
                        lp1 = t_end;
                    } else {
                        const t = @as(f32, @floatFromInt(i + 1)) / n;

                        var s: f32 = undefined;
                        switch (robust) {
                            .low_k1 => {
                                s = t;
                            },
                            .low_dist => {
                                const c = std.math.cbrt(integral * t + int0);
                                const inv = c * @abs(c);
                                s = (inv - b) / a;
                            },
                            .normal => {
                                const inv = EspcRobust.intInvApproximation(config, integral * t + int0);
                                s = (inv - b) / a;
                                // TODO: probably shouldn't have to do this, it differs from Vello
                                s = std.math.clamp(s, 0.0, 1.0);
                            },
                        }
                        lp1 = es.applyOffset(s, normalized_offset);
                    }

                    const l0 = if (offset >= 0.0) lp0 else lp1;
                    const l1 = if (offset >= 0.0) lp1 else lp0;
                    const line = Line.create(transform.apply(l0), transform.apply(l1));
                    writer.write(line);

                    lp0 = lp1;
                }

                last_p = this_p1;
                last_q = this_q1;
                last_t = t1;

                // Advance segment to next range. Beginning of segment is the end of
                // this one. The number of trailing zeros represents the number of stack
                // frames to pop in the recursive version of adaptive subdivision, and
                // each stack pop represents doubling of the size of the range.
                t0_u += 1;
                const shift: u5 = @intCast(@ctz(t0_u));
                t0_u >>= shift;
                dt *= @as(f32, @floatFromInt(@as(u32, 1) << shift));
            } else {
                // Subdivide; halve the size of the range while retaining its start.
                t0_u *|= 2;
                dt *= 0.5;
            }
        }
    }

    pub const EspcRobust = enum(u8) {
        normal = 0,
        low_k1 = 1,
        low_dist = 2,

        pub fn intApproximation(config: KernelConfig, x: f32) f32 {
            const y = @abs(x);
            var a: f32 = undefined;

            if (y < config.break1) {
                a = std.math.sin(config.sin_scale * y) * (1.0 / config.sin_scale);
            } else if (y < config.break2) {
                a = (std.math.sqrt(8.0) / 3.0) * (y - 1.0) * std.math.sqrt(@abs(y - 1.0)) + (std.math.pi / 4.0);
            } else {
                var qa: f32 = undefined;
                var qb: f32 = undefined;
                var qc: f32 = undefined;

                if (y < config.break3) {
                    qa = config.quad_a1;
                    qb = config.quad_b1;
                    qc = config.quad_c1;
                } else {
                    qa = config.quad_a2;
                    qb = config.quad_b2;
                    qc = config.quad_c2;
                }

                a = qa * y * y + qb * y + qc;
            }

            return std.math.copysign(a, x);
        }

        pub fn intInvApproximation(config: KernelConfig, x: f32) f32 {
            const y = @abs(x);
            var a: f32 = undefined;

            if (y < 0.7010707591262915) {
                a = std.math.asin(x * config.sin_scale * (1.0 / config.sin_scale));
            } else if (y < 0.903249293595206) {
                const b = y - (std.math.pi / 4.0);
                const u = std.math.copysign(std.math.pow(f32, @abs(b), 2.0 / 3.0), b);
                a = u * std.math.cbrt(@as(f32, 9.0 / 8.0)) + 1.0;
            } else {
                var u: f32 = undefined;
                var v: f32 = undefined;
                var w: f32 = undefined;

                if (y < 2.038857793595206) {
                    const B: f32 = 0.5 * config.quad_b1 / config.quad_a1;
                    u = B * B - config.quad_c1 / config.quad_a1;
                    v = 1.0 / config.quad_a1;
                    w = B;
                } else {
                    const B: f32 = 0.5 * config.quad_b2 / config.quad_a2;
                    u = B * B - config.quad_c2 / config.quad_a2;
                    v = 1.0 / config.quad_a2;
                    w = B;
                }

                a = std.math.sqrt(u + v * y) - w;
            }

            return std.math.copysign(a, x);
        }
    };

    pub const CubicAndDeriv = struct {
        point: PointF32,
        derivative: PointF32,
    };

    // Evaluate both the point and derivative of a cubic bezier.
    pub fn evaluateCubicAndDeriv(p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32, t: f32) CubicAndDeriv {
        const m: f32 = 1.0 - t;
        const mm = m * m;
        const mt = m * t;
        const tt = t * t;
        // p = p0 * (mm * m) + (p1 * (3.0 * mm) + p2 * (3.0 * mt) + p3 * tt) * t;
        const p = p0.mulScalar(mm * m).add(p1.mulScalar(3.0 * mm).add(p2.mulScalar(3.0 * mt)).add(p3.mulScalar(tt)).mulScalar(t));
        // q = (p - p0) * mm + (p2 - p1) * (2.0 * mt) + (p3 - p2) * tt;
        const q = p.sub(p0).mulScalar(mm).add(p2.sub(p1).mulScalar(2.0 * mt)).add(p3.sub(p2).mulScalar(tt));

        return CubicAndDeriv{
            .point = p,
            .derivative = q,
        };
    }

    pub fn getCubicPoints(path_tag: PathTag, path_monoid: PathMonoid, segment_data: SegmentData) CubicBezierF32 {
        var cubic_points = CubicBezierF32{};

        switch (path_tag.segment.kind) {
            .line_f32 => {
                const line = segment_data.getSegment(LineF32, path_monoid);
                cubic_points.point0 = line.p0;
                cubic_points.point1 = line.p1;
                cubic_points.point3 = cubic_points.point1;
                cubic_points.point2 = cubic_points.point3.lerp(cubic_points.point0, 1.0 / 3.0);
                cubic_points.point1 = cubic_points.point0.lerp(cubic_points.point3, 1.0 / 3.0);
            },
            .line_i16 => {
                const line = segment_data.getSegment(LineI16, path_monoid).cast(f32);
                cubic_points.point0 = line.p0;
                cubic_points.point1 = line.p1;
                cubic_points.point3 = cubic_points.point1;
                cubic_points.point2 = cubic_points.point3.lerp(cubic_points.point0, 1.0 / 3.0);
                cubic_points.point1 = cubic_points.point0.lerp(cubic_points.point3, 1.0 / 3.0);
            },
            .quadratic_bezier_f32 => {
                const qb = segment_data.getSegment(QuadraticBezierF32, path_monoid);
                cubic_points.point0 = qb.p0;
                cubic_points.point1 = qb.p1;
                cubic_points.point2 = qb.p2;
                cubic_points.point3 = cubic_points.point2;
                cubic_points.point2 = cubic_points.point1.lerp(cubic_points.point2, 1.0 / 3.0);
                cubic_points.point1 = cubic_points.point1.lerp(cubic_points.point0, 1.0 / 3.0);
            },
            .quadratic_bezier_i16 => {
                const qb = segment_data.getSegment(QuadraticBezierI16, path_monoid).cast(f32);
                cubic_points.point0 = qb.p0;
                cubic_points.point1 = qb.p1;
                cubic_points.point2 = qb.p2;
                cubic_points.point3 = cubic_points.point2;
                cubic_points.point2 = cubic_points.point1.lerp(cubic_points.point2, 1.0 / 3.0);
                cubic_points.point1 = cubic_points.point1.lerp(cubic_points.point0, 1.0 / 3.0);
            },
            .cubic_bezier_f32 => {
                cubic_points = segment_data.getSegment(CubicBezierF32, path_monoid);
            },
            .cubic_bezier_i16 => {
                cubic_points = segment_data.getSegment(CubicBezierI16, path_monoid).cast(f32);
            },
        }

        return cubic_points;
    }

    pub const NeighborSegment = struct {
        tangent: PointF32,
    };

    pub fn cubicStartTangent(config: KernelConfig, p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32) PointF32 {
        const d01 = p1.sub(p0);
        const d02 = p2.sub(p0);
        const d03 = p3.sub(p0);

        if (d01.lengthSquared() > config.robust_eps) {
            return d01;
        } else if (d02.lengthSquared() > config.robust_eps) {
            return d02;
        } else {
            return d03;
        }
    }

    fn cubicEndTangent(config: KernelConfig, p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32) PointF32 {
        const d23 = p3.sub(p2);
        const d13 = p3.sub(p1);
        const d03 = p3.sub(p0);
        if (d23.lengthSquared() > config.robust_eps) {
            return d23;
        } else if (d13.lengthSquared() > config.robust_eps) {
            return d13;
        } else {
            return d03;
        }
    }

    // fn readNeighborSegment(
    //     config: KernelConfig,
    //     curves: []const Curve,
    //     points: []const PointF32,
    //     curve_range: RangeU32,
    //     index: u32,
    // ) NeighborSegment {
    //     const index_shifted = (index - curve_range.start) % curve_range.size() + curve_range.start;
    //     const curve = curves[index_shifted];
    //     const cubic_points = getCubicPoints(curve, points[curve.point_offsets.start..curve.point_offsets.end]);
    //     const tangent = cubicStartTangent(
    //         config,
    //         cubic_points.point0,
    //         cubic_points.point1,
    //         cubic_points.point2,
    //         cubic_points.point3,
    //     );

    //     return NeighborSegment{
    //         .tangent = tangent,
    //     };
    // }

    const Writer = struct {
        segment_data: []u8,
        offset: usize = 0,

        pub fn addPoint(self: *@This(), point: PointF32) void {
            std.mem.bytesAsValue(PointF32, self.segment_data[self.offset .. self.offset + @sizeOf(PointF32)]).* = point;
            self.offset += @sizeOf(PointF32);
        }

        pub fn lineTo(self: *@This(), point: PointF32) void {
            self.addPoint(point);
        }
    };
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
