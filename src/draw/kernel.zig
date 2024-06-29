const std = @import("std");
const core = @import("../core/root.zig");
const soup_module = @import("./soup.zig");
const shape_module = @import("./shape.zig");
const euler_module = @import("./euler.zig");
const curve_module = @import("./curve.zig");
const pen_module = @import("./soup_pen.zig");
const TransformF32 = core.TransformF32;
const PointF32 = core.PointF32;
const RangeU32 = core.RangeU32;
const FlatPath = soup_module.FlatPath;
const FlatSubpath = soup_module.FlatSubpath;
const FlatCurve = soup_module.FlatCurve;
const Path = shape_module.Path;
const Subpath = shape_module.Subpath;
const Curve = shape_module.Curve;
const CubicPoints = euler_module.CubicPoints;
const CubicParams = euler_module.CubicParams;
const EulerParams = euler_module.EulerParams;
const EulerSegment = euler_module.EulerSegment;
const Line = curve_module.Line;
const Style = pen_module.Style;

pub const KernelConfig = struct {
    pub const DEFAULT: @This() = init(@This(){});

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

pub fn Kernel(comptime T: type) type {
    const Writer = struct {
        items: []T,
        index: usize = 0,

        pub fn write(self: *@This(), item: T) void {
            if (item.isEmpty()) {
                return;
            }

            self.items[self.index] = item;
            self.index += 1;
        }
    };

    return struct {
        pub fn flattenFill(
            // input uniform
            config: KernelConfig,
            // input buffers
            transforms: []const TransformF32.Matrix,
            curves: []const Curve,
            points: []const PointF32,
            // job parameters
            transform_index: u32,
            curve_index: u32,
            flat_curve_index: u32,
            // write destination
            flat_curves: []FlatCurve,
            items: []T,
        ) void {
            const transform = transforms[transform_index];
            const curve = curves[curve_index];
            const flat_curve = flat_curves[flat_curve_index];
            const fill_items = items[flat_curve.item_offsets.start..flat_curve.item_offsets.end];
            const cubic_points = getCubicPoints(
                curve,
                points[curve.point_offsets.start..curve.point_offsets.end],
            );

            var writer = Writer{
                .items = fill_items,
            };
            flattenEuler(
                config,
                cubic_points,
                transform,
                0.0,
                cubic_points.point0,
                cubic_points.point3,
                &writer,
            );

            flat_curves[flat_curve_index].item_offsets.end = flat_curve.item_offsets.start + @as(u32, @intCast(writer.index));
        }

        pub fn flattenStroke(
            // input uniform
            config: KernelConfig,
            // input buffers
            transforms: []const TransformF32.Matrix,
            styles: []const Style,
            subpaths: []const Subpath,
            curves: []const Curve,
            points: []const PointF32,
            // job parameters
            transform_index: u32,
            style_index: u32,
            curve_index: u32,
            subpath_index: u32,
            left_flat_curve_index: u32,
            right_flat_curve_index: u32,
            // write destination
            flat_curves: []FlatCurve,
            items: []T,
        ) void {
            const transform = transforms[transform_index];
            const curve = curves[curve_index];
            const left_flat_curve = flat_curves[left_flat_curve_index];
            const right_flat_curve = flat_curves[right_flat_curve_index];
            const cubic_points = getCubicPoints(
                curve,
                points[curve.point_offsets.start..curve.point_offsets.end],
            );
            const left_stroke_items = items[left_flat_curve.item_offsets.start..left_flat_curve.item_offsets.end];
            const right_stroke_items = items[right_flat_curve.item_offsets.start..right_flat_curve.item_offsets.end];
            var left_writer = Writer{
                .items = left_stroke_items,
            };
            var right_writer = Writer{
                .items = right_stroke_items,
            };
            const style = styles[style_index];
            const stroke = style.stroke.?;

            const offset = 0.5 * stroke.width;
            const offset_point = PointF32{
                .x = offset,
                .y = offset,
            };

            const curve_range = subpaths[subpath_index].curve_offsets;
            const neighbor = readNeighborSegment(config, curves, points, curve_range, curve_index + 1);
            var tan_prev = cubicEndTangent(config, cubic_points.point0, cubic_points.point1, cubic_points.point2, cubic_points.point3);
            var tan_next = neighbor.tangent;
            var tan_start = cubicStartTangent(config, cubic_points.point0, cubic_points.point1, cubic_points.point2, cubic_points.point3);

            if (tan_start.dot(tan_start) < config.tangent_threshold_pow2) {
                tan_start = PointF32{
                    .x = config.tangent_threshold,
                    .y = 0.0,
                };
            }

            if (tan_prev.dot(tan_prev) < config.tangent_threshold_pow2) {
                tan_prev = PointF32{
                    .x = config.tangent_threshold,
                    .y = 0.0,
                };
            }

            if (tan_next.dot(tan_next) < config.tangent_threshold_pow2) {
                tan_next = PointF32{
                    .x = config.tangent_threshold,
                    .y = 0.0,
                };
            }

            const n_start = offset_point.mul((PointF32{
                .x = -tan_start.y,
                .y = tan_start.x,
            }).normalizeUnsafe());
            const offset_tangent = offset_point.mul(tan_prev.normalizeUnsafe());
            const n_prev = PointF32{
                .x = -offset_tangent.y,
                .y = offset_tangent.x,
            };
            const tan_next_norm = tan_next.normalizeUnsafe();
            const n_next = offset_point.mul(PointF32{
                .x = -tan_next_norm.y,
                .y = tan_next_norm.x,
            });

            if (curve.cap == .start) {
                // draw start cap on left side
                drawCap(
                    config,
                    stroke.start_cap,
                    cubic_points.point0,
                    cubic_points.point0.sub(n_start),
                    cubic_points.point0.add(n_start),
                    offset_tangent.negate(),
                    transform,
                    &left_writer,
                );
            }

            flattenEuler(
                config,
                cubic_points,
                transform,
                offset,
                cubic_points.point0.add(n_start),
                cubic_points.point3.add(n_prev),
                &left_writer,
            );

            var right_join_index: usize = 0;
            if (curve.cap == .end) {
                // draw end cap on left side
                drawCap(
                    config,
                    stroke.end_cap,
                    cubic_points.point3,
                    cubic_points.point3.add(n_prev),
                    cubic_points.point3.sub(n_prev),
                    offset_tangent,
                    transform,
                    &left_writer,
                );
            } else {
                drawJoin(
                    config,
                    stroke,
                    cubic_points.point3,
                    tan_prev,
                    tan_next,
                    n_prev,
                    n_next,
                    transform,
                    &left_writer,
                    &right_writer,
                );
                right_join_index = right_writer.index;
            }

            flattenEuler(
                config,
                cubic_points,
                transform,
                -offset,
                cubic_points.point0.sub(n_start),
                cubic_points.point3.sub(n_prev),
                &right_writer,
            );

            std.mem.reverse(T, right_writer.items[right_join_index..right_writer.index]);

            flat_curves[left_flat_curve_index].item_offsets.end = left_flat_curve.item_offsets.start + @as(u32, @intCast(left_writer.index));
            flat_curves[right_flat_curve_index].item_offsets.end = right_flat_curve.item_offsets.start + @as(u32, @intCast(right_writer.index));
        }

        fn flattenEuler(
            config: KernelConfig,
            cubic_points: CubicPoints,
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
                        const line = T.create(transform.apply(l0), transform.apply(l1));
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

        fn drawCap(
            config: KernelConfig,
            cap_style: Style.Cap,
            point: PointF32,
            cap0: PointF32,
            cap1: PointF32,
            offset_tangent: PointF32,
            transform: TransformF32.Matrix,
            writer: *Writer,
        ) void {
            if (cap_style == .round) {
                flattenArc(
                    config,
                    cap0,
                    cap1,
                    point,
                    std.math.pi,
                    transform,
                    writer,
                );
                return;
            }

            var start = cap0;
            var end = cap1;
            if (cap_style == .square) {
                const v = offset_tangent;
                const p0 = start.add(v);
                const p1 = end.add(v);
                writer.write(T.create(transform.apply(start), transform.apply(p0)));
                writer.write(T.create(transform.apply(p1), transform.apply(end)));

                start = p0;
                end = p1;
            }

            writer.write(T.create(transform.apply(start), transform.apply(end)));
        }

        fn drawJoin(
            config: KernelConfig,
            stroke: Style.Stroke,
            p0: PointF32,
            tan_prev: PointF32,
            tan_next: PointF32,
            n_prev: PointF32,
            n_next: PointF32,
            transform: TransformF32.Matrix,
            left_writer: *Writer,
            right_writer: *Writer,
        ) void {
            var front0 = p0.add(n_prev);
            const front1 = p0.add(n_next);
            var back0 = p0.sub(n_next);
            const back1 = p0.sub(n_prev);

            const cr = tan_prev.x * tan_next.y - tan_prev.y * tan_next.x;
            const d = tan_prev.dot(tan_next);

            switch (stroke.join) {
                .bevel => {
                    if (!std.meta.eql(front0, front1) and !std.meta.eql(back0, back1)) {
                        left_writer.write(T.create(transform.apply(front0), transform.apply(front1)));
                        right_writer.write(T.create(transform.apply(back0), transform.apply(back1)));
                    }
                },
                .miter => {
                    const hypot = std.math.hypot(cr, d);
                    const miter_limit = stroke.miter_limit;

                    if (2.0 * hypot < (hypot + d) * miter_limit * miter_limit and cr != 0.0) {
                        const is_backside = cr > 0.0;
                        const fp_last = if (is_backside) back1 else front0;
                        const fp_this = if (is_backside) back0 else front1;
                        const p = if (is_backside) back0 else front0;

                        const v = fp_this.sub(fp_last);
                        const h = (tan_prev.x * v.y - tan_prev.y * v.x) / cr;
                        const miter_pt = fp_this.sub(tan_next.mul(PointF32{
                            .x = h,
                            .y = h,
                        }));

                        if (is_backside) {
                            right_writer.write(T.create(transform.apply(p), transform.apply(miter_pt)));
                            back0 = miter_pt;
                        } else {
                            left_writer.write(T.create(transform.apply(p), transform.apply(miter_pt)));
                            front0 = miter_pt;
                        }
                    }

                    left_writer.write(T.create(transform.apply(front0), transform.apply(front1)));
                    right_writer.write(T.create(transform.apply(back0), transform.apply(back1)));
                },
                .round => {
                    if (cr > 0.0) {
                        flattenArc(
                            config,
                            back0,
                            back1,
                            p0,
                            @abs(std.math.atan2(cr, d)),
                            transform,
                            right_writer,
                        );

                        left_writer.write(T.create(transform.apply(front0), transform.apply(front1)));
                    } else {
                        flattenArc(
                            config,
                            front0,
                            front1,
                            p0,
                            @abs(std.math.atan2(cr, d)),
                            transform,
                            left_writer,
                        );

                        right_writer.write(T.create(transform.apply(back0), transform.apply(back1)));
                    }
                },
            }
        }

        fn flattenArc(
            config: KernelConfig,
            start: PointF32,
            end: PointF32,
            center: PointF32,
            angle: f32,
            transform: TransformF32.Matrix,
            writer: *Writer,
        ) void {
            var p0 = transform.apply(start);
            var r = start.sub(center);
            const radius = @max(config.error_tolerance, (p0.sub(transform.apply(center))).length());
            const theta = @max(config.min_theta, (2.0 * std.math.acos(1.0 - config.error_tolerance / radius)));

            // Always output at least one line so that we always draw the chord.
            const n_lines: u32 = @max(1, @as(u32, @intFromFloat(@ceil(angle / theta))));

            // let (s, c) = theta.sin_cos();
            const s = std.math.sin(theta);
            const c = std.math.cos(theta);
            const rot = TransformF32.Matrix{
                .coefficients = [_]f32{ c, -s, s, c, 0.0, 0.0 },
            };

            for (0..n_lines - 1) |n| {
                _ = n;
                r = rot.apply(r);
                const p1 = transform.apply(center.add(r));
                writer.write(T.create(p0, p1));
                p0 = p1;
            }

            const p1 = transform.apply(end);
            writer.write(T.create(p0, p1));
        }
    };
}

pub const LineKernel = Kernel(Line);

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

pub fn getCubicPoints(curve: Curve, points: []const PointF32) CubicPoints {
    var cubic_points = CubicPoints{};

    cubic_points.point0 = points[0];
    cubic_points.point1 = points[1];

    switch (curve.kind) {
        .line => {
            cubic_points.point3 = cubic_points.point1;
            cubic_points.point2 = cubic_points.point3.lerp(cubic_points.point0, 1.0 / 3.0);
            cubic_points.point1 = cubic_points.point0.lerp(cubic_points.point3, 1.0 / 3.0);
        },
        .quadratic_bezier => {
            cubic_points.point2 = points[2];
            cubic_points.point3 = cubic_points.point2;
            cubic_points.point2 = cubic_points.point1.lerp(cubic_points.point2, 1.0 / 3.0);
            cubic_points.point1 = cubic_points.point1.lerp(cubic_points.point0, 1.0 / 3.0);
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

fn readNeighborSegment(
    config: KernelConfig,
    curves: []const Curve,
    points: []const PointF32,
    curve_range: RangeU32,
    index: u32,
) NeighborSegment {
    const index_shifted = (index - curve_range.start) % curve_range.size() + curve_range.start;
    const curve = curves[index_shifted];
    const cubic_points = getCubicPoints(curve, points[curve.point_offsets.start..curve.point_offsets.end]);
    const tangent = cubicStartTangent(
        config,
        cubic_points.point0,
        cubic_points.point1,
        cubic_points.point2,
        cubic_points.point3,
    );

    return NeighborSegment{
        .tangent = tangent,
    };
}
