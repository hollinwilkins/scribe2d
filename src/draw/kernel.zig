const std = @import("std");
const core = @import("../core/root.zig");
const soup_module = @import("./soup.zig");
const shape_module = @import("./shape.zig");
const euler_module = @import("./euler.zig");
const curve_module = @import("./curve.zig");
const pen_module = @import("./pen.zig");
const TransformF32 = core.TransformF32;
const PointF32 = core.PointF32;
const RangeU32 = core.RangeU32;
const RangeF32 = core.RangeF32;
const FlatPath = soup_module.FlatPath;
const FlatSubpath = soup_module.FlatSubpath;
const FlatCurve = soup_module.FlatCurve;
const FlatSegment = soup_module.FlatSegment;
const FillJob = soup_module.FillJob;
const StrokeJob = soup_module.StrokeJob;
const Path = shape_module.Path;
const Subpath = shape_module.Subpath;
const Curve = shape_module.Curve;
const CubicPoints = euler_module.CubicPoints;
const CubicParams = euler_module.CubicParams;
const EulerParams = euler_module.EulerParams;
const EulerSegment = euler_module.EulerSegment;
const Arc = curve_module.Arc;
const Line = curve_module.Line;
const Style = pen_module.Style;

pub const KernelConfig = struct {
    pub const DEFAULT: @This() = init(@This(){});

    parallelism: u8 = 8,
    fill_job_chunk_size: u8 = 8,
    stroke_job_chunk_size: u8 = 2,
    evolutes_enabled: bool = false,

    newton_iter: u32 = 1,
    halley_iter: u32 = 1,

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
            .fill_job_chunk_size = config.fill_job_chunk_size,
            .stroke_job_chunk_size = config.stroke_job_chunk_size,
            .evolutes_enabled = config.evolutes_enabled,

            .newton_iter = config.newton_iter,
            .halley_iter = config.halley_iter,

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

const SegmentWriter = struct {
    flat_segments: []FlatSegment,
    buffer: []u8,
    buffer_start: u32,
    index: usize = 0,

    pub fn writeLine(self: *@This(), line: Line) void {
        if (line.isEmpty()) {
            return;
        }

        const segment_buffer_start: u32 = @intCast(self.buffer_start + self.index);
        self.flat_segments[self.index] = FlatSegment{
            .kind = .line,
            .buffer_offsets = RangeU32{
                .start = segment_buffer_start,
                .end = segment_buffer_start + @sizeOf(Line),
            },
        };
        std.mem.copyForwards(u8, self.buffer[self.index..], @alignCast(std.mem.asBytes(&line)));
        self.index += @sizeOf(Line);
    }

    pub fn writeArc(self: *@This(), arc: Arc) void {
        if (arc.isEmpty()) {
            return;
        }

        const segment_buffer_start: u32 = @intCast(self.buffer_start + self.index);
        self.flat_segments[self.index] = FlatSegment{
            .kind = .arc,
            .buffer_offsets = RangeU32{
                .start = segment_buffer_start,
                .end = segment_buffer_start + @sizeOf(Arc),
            },
        };
        std.mem.copyForwards(u8, self.buffer[self.index..], @alignCast(std.mem.asBytes(&arc)));
        self.index += @sizeOf(Arc);
    }
};

pub const Kernel = struct {
    pub fn flattenFill(
        config: KernelConfig,
        // input buffers
        transforms: []const TransformF32.Matrix,
        curves: []const Curve,
        points: []const PointF32,
        fill_jobs: []const FillJob,
        fill_range: RangeU32,
        // write destination
        flat_curves: []FlatCurve,
        flat_segments: []FlatSegment,
        buffer: []u8,
    ) void {
        for (fill_jobs[fill_range.start..fill_range.end]) |fill_job| {
            flattenFillJob(
                config,
                // inputs
                transforms,
                curves,
                points,
                fill_job.transform_index,
                fill_job.curve_index,
                fill_job.flat_curve_index,
                // output
                flat_curves,
                flat_segments,
                buffer,
            );
        }
    }

    pub fn flattenStroke(
        config: KernelConfig,
        // input buffers
        transforms: []const TransformF32.Matrix,
        styles: []const Style,
        subpaths: []const Subpath,
        curves: []const Curve,
        points: []const PointF32,
        stroke_jobs: []const StrokeJob,
        stroke_range: RangeU32,
        // write destination
        flat_curves: []FlatCurve,
        flat_segments: []FlatSegment,
        buffer: []u8,
    ) void {
        for (stroke_jobs[stroke_range.start..stroke_range.end]) |stroke_job| {
            flattenStrokeJob(
                config,
                // input
                transforms,
                styles,
                subpaths,
                curves,
                points,
                stroke_job.transform_index,
                stroke_job.style_index,
                stroke_job.curve_index,
                stroke_job.subpath_index,
                stroke_job.left_flat_curve_index,
                stroke_job.right_flat_curve_index,
                // output
                flat_curves,
                flat_segments,
                buffer,
            );
        }
    }

    pub fn flattenFillJob(
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
        flat_segments: []FlatSegment,
        buffer: []u8,
    ) void {
        const transform = transforms[transform_index];
        const curve = curves[curve_index];
        const flat_curve = flat_curves[flat_curve_index];
        const flat_curve_segments = flat_segments[flat_curve.segment_offsets.start..flat_curve.segment_offsets.end];
        const flat_curve_buffer = buffer[flat_curve.buffer_offsets.start..flat_curve.buffer_offsets.end];
        var writer = SegmentWriter{
            .flat_segments = flat_curve_segments,
            .buffer = flat_curve_buffer,
            .buffer_start = flat_curve.buffer_offsets.start,
        };

        const cubic_points = getCubicPoints(
            curve,
            points[curve.point_offsets.start..curve.point_offsets.end],
        );

        flattenEuler(
            config,
            cubic_points,
            transform,
            0.0,
            cubic_points.point0,
            cubic_points.point3,
            &writer,
        );

        flat_curves[flat_curve_index].buffer_offsets.end = flat_curve.buffer_offsets.start + @as(u32, @intCast(writer.index));
    }

    pub fn flattenStrokeJob(
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
        flat_segments: []FlatSegment,
        buffer: []u8,
    ) void {
        const transform = transforms[transform_index];
        const curve = curves[curve_index];
        const left_flat_curve = flat_curves[left_flat_curve_index];
        const right_flat_curve = flat_curves[right_flat_curve_index];
        const left_flat_segments = flat_segments[left_flat_curve.segment_offsets.start..left_flat_curve.segment_offsets.end];
        const right_flat_segments = flat_segments[right_flat_curve.segment_offsets.start..right_flat_curve.segment_offsets.end];
        const left_flat_curve_buffer = buffer[left_flat_curve.buffer_offsets.start..left_flat_curve.buffer_offsets.end];
        const right_flat_curve_buffer = buffer[right_flat_curve.buffer_offsets.start..right_flat_curve.buffer_offsets.end];
        var left_writer = SegmentWriter{
            .flat_segments = left_flat_segments,
            .buffer = left_flat_curve_buffer,
            .buffer_start = left_flat_curve.segment_offsets.start,
        };
        var right_writer = SegmentWriter{
            .flat_segments = right_flat_segments,
            .buffer = right_flat_curve_buffer,
            .buffer_start = right_flat_curve.segment_offsets.start,
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
        const cubic_points = getCubicPoints(
            curve,
            points[curve.point_offsets.start..curve.point_offsets.end],
        );
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

        // std.mem.reverse(Line, right_writer.lines[right_join_index..right_writer.index]);

        flat_curves[left_flat_curve_index].buffer_offsets.end = left_flat_curve.buffer_offsets.start + @as(u32, @intCast(left_writer.index));
        flat_curves[right_flat_curve_index].buffer_offsets.end = right_flat_curve.buffer_offsets.start + @as(u32, @intCast(right_writer.index));
    }

    fn flattenEuler(
        config: KernelConfig,
        cubic_points: CubicPoints,
        transform: TransformF32.Matrix,
        offset: f32,
        start_point: PointF32,
        end_point: PointF32,
        writer: *SegmentWriter,
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
        var contour = t_start;

        while (true) {
            const t0 = @as(f32, @floatFromInt(t0_u)) * dt;
            if (t0 == 1.0) {
                writer.writeLine(Line.create(contour, t_end).transformMatrix(transform));
                break;
            }

            var t1 = t0 + dt;
            const this_p0 = last_p;
            const this_q0 = last_q;
            var this_pq1 = evaluateCubicAndDeriv(p0, p1, p2, p3, t1);
            if (this_pq1.derivative.lengthSquared() < config.derivative_threshold_pow2) {
                const new_pq1 = evaluateCubicAndDeriv(p0, p1, p2, p3, t1 - config.derivative_eps);
                this_pq1.derivative = new_pq1.derivative;
                if (t1 < 1.0) {
                    this_pq1.point = new_pq1.point;
                    t1 = t1 - config.derivative_eps;
                }
            }

            const actual_dt = t1 - last_t;
            const cubic_params = CubicParams.create(this_p0, this_pq1.point, this_q0, this_pq1.derivative, actual_dt);
            if (cubic_params.err * scale < config.error_tolerance or dt <= config.subdivision_limit) {
                const euler_params = EulerParams.create(cubic_params.th0, cubic_params.th1);
                const euler_segment = EulerSegment{
                    .p0 = this_p0,
                    .p1 = this_pq1.point,
                    .params = euler_params,
                };
                const lowering = EulerLoweringParams{
                    .euler_segment = euler_segment,
                    .transform = transform,
                    .t1 = t1,
                    .scale = scale,
                    .offset = offset,
                    .chord_len = cubic_params.chord_len,
                };

                if (config.evolutes_enabled) {
                    // TODO: implement this
                } else {
                    contour = flattenSegmentOffset(
                        config,
                        lowering,
                        contour,
                        RangeF32{
                            .start = 0.0,
                            .end = 1.0,
                        },
                        writer,
                    );
                }

                last_p = this_pq1.point;
                last_q = this_pq1.derivative;
                last_t = t1;
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

    fn flattenSegmentOffset(
        config: KernelConfig,
        lowering: EulerLoweringParams,
        p0: PointF32,
        t_range: RangeF32,
        writer: *SegmentWriter,
    ) PointF32 {
        const euler_segment = lowering.euler_segment;
        const range_size = t_range.end - t_range.start;
        const k1 = euler_segment.params.k1 + range_size;
        const normalized_offset = lowering.offset / lowering.chord_len;
        const offset = lowering.offset;
        const arclen = euler_segment.p1.sub(euler_segment.p0).length() / euler_segment.params.ch;
        const est_err1: f32 = (1.0 / 120.0) / config.error_tolerance;
        const est_err2: f32 = (arclen * 0.4 * @abs(k1 * offset));
        const est_err: f32 = est_err1 * @abs(k1) * est_err2;
        const n_subdiv = cbrt(config, est_err);
        const n = @max(@as(u32, @intFromFloat(n_subdiv * range_size)), 1);
        const arc_dt = 1.0 / @as(f32, @floatFromInt(n));
        var lp0 = p0;

        for (0..n) |i| {
            var ap1: PointF32 = undefined;
            const arc_t0 = @as(f32, @floatFromInt(i)) * arc_dt;
            const arc_t1 = arc_t0 + arc_dt;
            if (i + 1 == n) {
                // ap1 = euler_segment.p1; // should be this probably
                ap1 = euler_segment.applyOffset(t_range.end, normalized_offset);
            } else {
                ap1 = euler_segment.applyOffset(t_range.start + range_size * arc_t1, normalized_offset);
            }

            const t = arc_t0 + 0.5 * arc_dt - 0.5;
            const k = euler_segment.params.k0 + t * k1;
            var r: f32 = undefined;
            const arc_k = k * arc_dt;
            if (@abs(arc_k) < 1e-12) {
                r = 0.0;
            } else {
                const s = if (offset == 0.0) 1.0 else std.math.sign(offset);
                r = 0.5 * s * lp0.sub(ap1).length() / std.math.sin(0.5 * arc_k);
            }
            const forward = lowering.offset >= 0;
            const l0 = if (forward) lp0 else ap1;
            const l1 = if (forward) ap1 else lp0;

            if (@abs(r) < 1e-12) {
                writer.writeLine(Line.create(l0, l1).transformMatrix(lowering.transform));
            } else {
                const angle = std.math.asin(0.5 * l0.sub(l1).length() / r);
                const mid_ch = l0.add(l1).mulScalar(0.5);
                const v = l1.sub(mid_ch).normalizeUnsafe().mulScalar(std.math.cos(angle) * r);
                const center = mid_ch.sub(PointF32{
                    .x = -v.y,
                    .y = v.x,
                });
                writer.writeArc(Arc.create(
                    l0,
                    l1,
                    center,
                    2.0 * angle,
                ).transformMatrix(lowering.transform));
            }
            lp0 = ap1;
        }

        return lp0;
    }

    fn drawCap(
        cap_style: Style.Cap,
        point: PointF32,
        cap0: PointF32,
        cap1: PointF32,
        offset_tangent: PointF32,
        transform: TransformF32.Matrix,
        writer: *SegmentWriter,
    ) void {
        if (cap_style == .round) {
            writer.writeArc(Arc.create(
                cap0,
                point,
                cap1,
                std.math.pi,
            ).transformMatrix(transform));
            return;
        }

        var start = cap0;
        var end = cap1;
        if (cap_style == .square) {
            const v = offset_tangent;
            const p0 = start.add(v);
            const p1 = end.add(v);
            writer.writeLine(Line.create(start, p0).transformMatrix(transform));
            writer.writeLine(Line.create(p1, end).transformMatrix(transform));

            start = p0;
            end = p1;
        }

        writer.writeLine(Line.create(start, end).transformMatrix(transform));
    }

    fn drawJoin(
        stroke: Style.Stroke,
        p0: PointF32,
        tan_prev: PointF32,
        tan_next: PointF32,
        n_prev: PointF32,
        n_next: PointF32,
        transform: TransformF32.Matrix,
        left_writer: *SegmentWriter,
        right_writer: *SegmentWriter,
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
                    left_writer.writeLine(Line.create(front0, front1).transformMatrix(transform));
                    right_writer.writeLine(Line.create(back0, back1).transformMatrix(transform));
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
                        right_writer.writeLine(Line.create(p, miter_pt).transformMatrix(transform));
                        back0 = miter_pt;
                    } else {
                        left_writer.writeLine(Line.create(p, miter_pt).transformMatrix(transform));
                        front0 = miter_pt;
                    }
                }

                left_writer.writeLine(Line.create(front0, front1).transformMatrix(transform));
                right_writer.writeLine(Line.create(back0, back1).transformMatrix(transform));
            },
            .round => {
                if (cr > 0.0) {
                    right_writer.writeArc(Arc.create(
                        back0,
                        p0,
                        back1,
                        @abs(std.math.atan2(cr, d)),
                    ).transformMatrix(transform));

                    left_writer.writeLine(Line.create(front0, front1).transformMatrix(transform));
                } else {
                    left_writer.writeArc(Arc.create(
                        front0,
                        p0,
                        front1,
                        @abs(std.math.atan2(cr, d)),
                    ).transformMatrix(transform));

                    right_writer.writeLine(Line.create(back0, back1).transformMatrix(transform));
                }
            },
        }
    }
};

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

fn cbrt(config: KernelConfig, x: f32) f32 {
    if (x == 0.0) {
        return 0.0;
    }

    // var y = sign(x) * bitcast<f32>(bitcast<u32>(abs(x)) / 3u + 0x2a514067u);
    var y = std.math.sign(x) * @as(f32, @bitCast((@as(u32, @bitCast(@abs(x))) / 3 + 0x2a514067)));

    for (0..config.newton_iter) |_| {
        y = (2.0 * y + x / (y * y)) * 0.333333333;
    }
    for (0..config.halley_iter) |_| {
        const y3 = y * y * y;
        y *= (y3 + 2.0 * x) / (2.0 * y3 + x);
    }

    return y;
}

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

pub const EulerLoweringParams = struct {
    euler_segment: EulerSegment,
    transform: TransformF32.Matrix,
    t1: f32,
    scale: f32,
    offset: f32,
    chord_len: f32,
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
