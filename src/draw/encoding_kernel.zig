const std = @import("std");
const core = @import("../core/root.zig");
const encoding_module = @import("./encoding.zig");
const euler_module = @import("./euler.zig");
const msaa_module = @import("./msaa.zig");
const RangeI32 = core.RangeI32;
const RangeU32 = core.RangeU32;
const PathTag = encoding_module.PathTag;
const PathMonoid = encoding_module.PathMonoid;
const Path = encoding_module.Path;
const Subpath = encoding_module.Subpath;
const SegmentData = encoding_module.SegmentData;
const FlatSegment = encoding_module.FlatSegment;
const Style = encoding_module.Style;
const MonoidFunctions = encoding_module.MonoidFunctions;
const Estimates = encoding_module.Estimates;
const Offsets = encoding_module.Offset;
const SegmentOffset = encoding_module.SegmentOffset;
const BumpAllocator = encoding_module.BumpAllocator;
const TransformF32 = core.TransformF32;
const IntersectionF32 = core.IntersectionF32;
const RectF32 = core.RectF32;
const RectI32 = core.RectI32;
const PointF32 = core.PointF32;
const PointI32 = core.PointI32;
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
const HalfPlanesU16 = msaa_module.HalfPlanesU16;

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
        segment_offsets: []SegmentOffset,
    ) void {
        for (range.start..range.end) |index| {
            const path_tag = path_tags[index];
            const path_monoid = path_monoids[index];
            const style = styles[path_monoid.style_index];
            const transform = transforms[path_monoid.transform_index];
            const sd = SegmentData{
                .segment_data = segment_data,
            };

            segment_offsets[index] = estimateSegment(
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
    ) SegmentOffset {
        var base = Offsets{};
        var fill = Offsets{};
        var front_stroke = Offsets{};
        var back_stroke = Offsets{};

        switch (path_tag.segment.kind) {
            .line_f32 => {
                const line = segment_data.getSegment(LineF32, path_monoid).affineTransform(transform);
                base = estimateLine(line);
            },
            .line_i16 => {
                const line = segment_data.getSegment(LineI16, path_monoid).cast(f32).affineTransform(transform);
                base = estimateLine(line);
            },
            .arc_f32 => {
                const arc = segment_data.getSegment(ArcF32, path_monoid).affineTransform(transform);
                base = estimateArc(config, arc);
            },
            .arc_i16 => {
                const arc = segment_data.getSegment(ArcI16, path_monoid).cast(f32).affineTransform(transform);
                base = estimateArc(config, arc);
            },
            .quadratic_bezier_f32 => {
                const qb = segment_data.getSegment(QuadraticBezierF32, path_monoid).affineTransform(transform);
                base = estimateQuadraticBezier(qb);
            },
            .quadratic_bezier_i16 => {
                const qb = segment_data.getSegment(QuadraticBezierI16, path_monoid).cast(f32).affineTransform(transform);
                base = estimateQuadraticBezier(qb);
            },
            .cubic_bezier_f32 => {
                const cb = segment_data.getSegment(CubicBezierF32, path_monoid).affineTransform(transform);
                base = estimateCubicBezier(cb);
            },
            .cubic_bezier_i16 => {
                const cb = segment_data.getSegment(CubicBezierI16, path_monoid).cast(f32).affineTransform(transform);
                base = estimateCubicBezier(cb);
            },
        }

        if (style.isFill()) {
            fill = base;
            fill.flat_segment = 1;
        }

        if (style.isStroke()) {
            // TODO: this still seems wrong
            const scale = transform.getScale() * 0.5;
            const stroke = style.stroke;
            const scaled_width = @max(1.0, stroke.width) * scale;
            const stroke_fudge = @max(1.0, std.math.sqrt(scaled_width));
            const cap = estimateCap(config, path_tag, stroke, scaled_width);
            const join = estimateJoin(config, stroke, scaled_width);
            const base_stroke = base.mulScalar(stroke_fudge);
            front_stroke = base_stroke.combine(cap).combine(join);
            back_stroke = base_stroke.combine(join);
            front_stroke.flat_segment = 1;
            back_stroke.flat_segment = 1;
        }

        return SegmentOffset.create(fill, front_stroke, back_stroke);
    }

    pub fn estimateJoin(config: KernelConfig, stroke: Style.Stroke, scaled_width: f32) Offsets {
        switch (stroke.join) {
            .bevel => {
                return Offsets.create(1, estimateLineWidthIntersections(scaled_width));
            },
            .miter => {
                const MITER_FUDGE: u16 = 2;
                return Offsets.create(2, estimateLineWidthIntersections(scaled_width) * 2 * MITER_FUDGE);
            },
            .round => {
                const arc_estimate = estimateRoundArc(config, scaled_width);
                return Offsets.create(arc_estimate.lines, estimateLineWidthIntersections(arc_estimate.length));
            },
        }
    }

    pub fn estimateCap(config: KernelConfig, path_tag: PathTag, stroke: Style.Stroke, scaled_width: f32) Offsets {
        if (path_tag.segment.cap) {
            const is_start_cap = path_tag.index.subpath == 1;
            const cap = if (is_start_cap) stroke.start_cap else stroke.end_cap;

            switch (cap) {
                .butt => {
                    return Offsets.create(1, estimateLineWidthIntersections(scaled_width));
                },
                .square => {
                    return Offsets.create(3, estimateLineWidthIntersections(scaled_width) * 2);
                },
                .round => {
                    const arc_estimate = estimateRoundArc(config, scaled_width);
                    return Offsets.create(arc_estimate.lines, estimateLineWidthIntersections(arc_estimate.length));
                },
            }
        }

        return Offsets{};
    }

    pub fn estimateLineWidth(scaled_width: f32) Offsets {
        return Offsets.create(1, estimateLineWidthIntersections(scaled_width));
    }

    pub fn estimateLineWidthIntersections(scaled_width: f32) u16 {
        const dxdy = PointF32{
            .x = scaled_width,
            .y = scaled_width,
        };

        const intersections: u16 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        return @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;
    }

    pub fn estimateLine(line: LineF32) Offsets {
        const dxdy = line.p1.sub(line.p0);
        var intersections: u16 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        intersections = @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;

        return Offsets.create(1, intersections);
    }

    pub fn estimateArc(config: KernelConfig, arc: ArcF32) Offsets {
        const width = arc.p0.sub(arc.p1).length() + arc.p2.sub(arc.p1).length();
        const arc_estimate = estimateRoundArc(config, width);

        return Offsets.create(arc_estimate.lines, estimateLineWidthIntersections(arc_estimate.length));
    }

    pub fn estimateQuadraticBezier(quadratic_bezier: QuadraticBezierF32) Offsets {
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

        return Offsets.create(lines, intersections);
    }

    pub fn estimateCubicBezier(cubic_bezier: CubicBezierF32) Offsets {
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

        return Offsets.create(lines, intersections);
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
        paths: []const Path,
        subpaths: []const Subpath,
        segment_data: []const u8,
        range: RangeU32,
        // outputs
        // true if path is used, false to ignore
        segment_offsets: []SegmentOffset,
        flat_segments: []FlatSegment,
        line_data: []u8,
    ) void {
        for (range.start..range.end) |segment_index| {
            const path_monoid = path_monoids[segment_index];
            const path = paths[path_monoid.path_index];
            const style = styles[path_monoid.style_index];
            const current_segment_offset = segment_offsets[segment_index];
            const previous_segment_offset = if (segment_index > 0) segment_offsets[segment_index - 1] else SegmentOffset{};
            const start_segment_offset = if (path.segment_index > 0) segment_offsets[path.segment_index - 1] else SegmentOffset{};
            var end_segment_offset: SegmentOffset = undefined;
            if (path_monoid.path_index + 1 < paths.len) {
                end_segment_offset = segment_offsets[paths[path_monoid.path_index + 1].segment_index - 1];
            } else {
                end_segment_offset = segment_offsets[segment_offsets.len - 1];
            }

            if (style.isFill()) {
                const flat_segment_index = start_segment_offset.sum.flat_segment + (previous_segment_offset.fill.flat_segment - start_segment_offset.fill.flat_segment);
                const start_line_offset = start_segment_offset.sum.line_offset + (previous_segment_offset.fill.line_offset - start_segment_offset.fill.line_offset);
                const end_line_offset = start_segment_offset.sum.line_offset + (current_segment_offset.fill.line_offset - start_segment_offset.fill.line_offset);
                const fill_line_data = line_data[start_line_offset..end_line_offset];

                const flat_segment = &flat_segments[flat_segment_index];
                flat_segment.* = FlatSegment{
                    .kind = .fill,
                    .segment_index = path_monoid.segment_index,
                    .start_line_data_offset = start_line_offset,
                    .end_line_data_offset = start_line_offset,
                };

                flattenFill(
                    config,
                    @intCast(segment_index),
                    path_tags,
                    path_monoids,
                    transforms,
                    segment_data,
                    flat_segment,
                    fill_line_data,
                );
            }

            if (style.isStroke()) {
                const last_fill_line_offset = start_segment_offset.sum.line_offset + (end_segment_offset.fill.line_offset - start_segment_offset.fill.line_offset);
                const last_fill_flat_segment_offset = start_segment_offset.sum.flat_segment + (end_segment_offset.fill.flat_segment - start_segment_offset.fill.flat_segment);
                const start_front_stroke_line_offset = last_fill_line_offset + (previous_segment_offset.front_stroke.line_offset - start_segment_offset.front_stroke.line_offset);
                const end_front_stroke_line_offset = last_fill_line_offset + (current_segment_offset.front_stroke.line_offset - start_segment_offset.front_stroke.line_offset);
                const front_stroke_flat_segment_index = last_fill_flat_segment_offset + (previous_segment_offset.front_stroke.flat_segment - start_segment_offset.front_stroke.flat_segment);
                const last_front_stroke_line_offset = last_fill_line_offset + (end_segment_offset.front_stroke.line_offset - start_segment_offset.front_stroke.line_offset);
                const last_front_stroke_flat_segment_offset = last_fill_flat_segment_offset + (end_segment_offset.front_stroke.flat_segment - start_segment_offset.front_stroke.flat_segment);
                const start_back_stroke_line_offset = last_front_stroke_line_offset + (previous_segment_offset.back_stroke.line_offset - start_segment_offset.back_stroke.line_offset);
                const end_back_stroke_line_offset = last_front_stroke_line_offset + (current_segment_offset.back_stroke.line_offset - start_segment_offset.back_stroke.line_offset);
                const back_stroke_flat_segment_index = last_front_stroke_flat_segment_offset + (previous_segment_offset.back_stroke.flat_segment - start_segment_offset.back_stroke.flat_segment);

                const front_stroke_flat_segment = &flat_segments[front_stroke_flat_segment_index];
                front_stroke_flat_segment.* = FlatSegment{
                    .kind = .stroke_front,
                    .segment_index = path_monoid.segment_index,
                    .start_line_data_offset = start_front_stroke_line_offset,
                    .end_line_data_offset = start_front_stroke_line_offset,
                };
                const front_stroke_line_data = line_data[start_front_stroke_line_offset..end_front_stroke_line_offset];
                const back_stroke_flat_segment = &flat_segments[back_stroke_flat_segment_index];
                back_stroke_flat_segment.* = FlatSegment{
                    .kind = .stroke_back,
                    .segment_index = path_monoid.segment_index,
                    .start_line_data_offset = start_back_stroke_line_offset,
                    .end_line_data_offset = start_back_stroke_line_offset,
                };
                const back_stroke_line_data = line_data[start_back_stroke_line_offset..end_back_stroke_line_offset];

                flattenStroke(
                    config,
                    style.stroke,
                    @intCast(segment_index),
                    path_tags,
                    path_monoids,
                    transforms,
                    subpaths,
                    segment_data,
                    front_stroke_flat_segment,
                    back_stroke_flat_segment,
                    front_stroke_line_data,
                    back_stroke_line_data,
                );
            }
        }
    }

    pub fn flattenFill(
        config: KernelConfig,
        segment_index: u32,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        transforms: []const TransformF32.Affine,
        segment_data: []const u8,
        flat_segment: *FlatSegment,
        line_data: []u8,
    ) void {
        const path_tag = path_tags[segment_index];
        const path_monoid = path_monoids[segment_index];
        const transform = transforms[path_monoid.transform_index];

        if (path_tag.segment.kind == .arc_f32 or path_tag.segment.kind == .arc_i16) {
            std.debug.print("Cannot flatten ArcF32 yet.\n", .{});
            return;
        }

        var writer = Writer{
            .line_data = line_data,
        };

        const cubic_points = getCubicPoints(
            path_tag,
            path_monoid,
            segment_data,
        );

        flattenEuler(
            config,
            cubic_points,
            transform,
            0.0,
            cubic_points.p0,
            cubic_points.p3,
            &writer,
        );

        // adjust lines to represent actual filled lines
        flat_segment.end_line_data_offset = flat_segment.end_line_data_offset + writer.offset;
    }

    pub fn flattenStroke(
        config: KernelConfig,
        stroke: Style.Stroke,
        segment_index: u32,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        transforms: []const TransformF32.Affine,
        subpaths: []const Subpath,
        segment_data: []const u8,
        front_flat_segment: *FlatSegment,
        back_flat_segment: *FlatSegment,
        front_line_data: []u8,
        back_line_data: []u8,
    ) void {
        const path_tag = path_tags[segment_index];
        const path_monoid = path_monoids[segment_index];
        const transform = transforms[path_monoid.transform_index];
        const subpath = subpaths[path_monoid.subpath_index];
        var next_subpath: Subpath = undefined;
        if (path_monoid.subpath_index + 1 < subpaths.len) {
            next_subpath = subpaths[path_monoid.subpath_index + 1];
        } else {
            next_subpath = subpaths[subpaths.len - 1];
        }
        var last_path_tag: PathTag = undefined;
        var last_path_monoid: PathMonoid = undefined;
        if (next_subpath.segment_index > 0) {
            last_path_tag = path_tags[next_subpath.segment_index - 1];
            last_path_monoid = path_monoids[next_subpath.segment_index - 1];
        } else {
            last_path_tag = path_tags[path_tags.len - 1];
            last_path_monoid = path_monoids[path_monoids.len - 1];
        }

        if (path_tag.segment.cap and path_monoid.segment_index == last_path_monoid.segment_index) {
            return;
        }

        if (path_tag.segment.kind == .arc_f32 or path_tag.segment.kind == .arc_i16) {
            std.debug.print("Cannot flatten ArcF32 yet.\n", .{});
            return;
        }

        var front_writer = Writer{
            .line_data = front_line_data,
        };
        var back_writer = Writer{
            .line_data = back_line_data,
        };

        const cubic_points = getCubicPoints(
            path_tag,
            path_monoid,
            segment_data,
        );

        const offset = 0.5 * stroke.width;
        const offset_point = PointF32{
            .x = offset,
            .y = offset,
        };

        const segment_range = RangeU32{
            .start = subpath.segment_index,
            .end = next_subpath.segment_index + 1,
        };
        const neighbor = readNeighborSegment(
            config,
            segment_index + 1,
            segment_range,
            path_tags,
            path_monoids,
            segment_data,
        );
        var tan_prev = cubicEndTangent(config, cubic_points.p0, cubic_points.p1, cubic_points.p2, cubic_points.p3);
        var tan_next = neighbor.tangent;
        var tan_start = cubicStartTangent(config, cubic_points.p0, cubic_points.p1, cubic_points.p2, cubic_points.p3);

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

        if (last_path_tag.segment.cap and path_tag.index.subpath == 1) {
            // draw start cap on left side
            drawCap(
                config,
                stroke.start_cap,
                cubic_points.p0,
                cubic_points.p0.sub(n_start),
                cubic_points.p0.add(n_start),
                offset_tangent.negate(),
                transform,
                &front_writer,
            );
        }

        flattenEuler(
            config,
            cubic_points,
            transform,
            offset,
            cubic_points.p0.add(n_start),
            cubic_points.p3.add(n_prev),
            &front_writer,
        );

        flattenEuler(
            config,
            cubic_points,
            transform,
            -offset,
            cubic_points.p0.sub(n_start),
            cubic_points.p3.sub(n_prev),
            &back_writer,
        );

        if (last_path_tag.segment.cap and path_monoid.segment_index == last_path_monoid.segment_index - 1) {
            // draw end cap on left side
            drawCap(
                config,
                stroke.end_cap,
                cubic_points.p3,
                cubic_points.p3.add(n_prev),
                cubic_points.p3.sub(n_prev),
                offset_tangent,
                transform,
                &front_writer,
            );
        } else {
            drawJoin(
                config,
                stroke,
                cubic_points.p3,
                tan_prev,
                tan_next,
                n_prev,
                n_next,
                transform,
                &front_writer,
                &back_writer,
            );
        }

        front_flat_segment.end_line_data_offset = front_flat_segment.end_line_data_offset + front_writer.offset;
        back_flat_segment.end_line_data_offset = back_flat_segment.end_line_data_offset + back_writer.offset;
    }

    fn flattenEuler(
        config: KernelConfig,
        cubic_points: CubicBezierF32,
        transform: TransformF32.Matrix,
        offset: f32,
        start_point: PointF32,
        end_point: PointF32,
        writer: *Writer,
    ) void {
        const p0 = transform.apply(cubic_points.p0);
        const p1 = transform.apply(cubic_points.p1);
        const p2 = transform.apply(cubic_points.p2);
        const p3 = transform.apply(cubic_points.p3);
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

                    // const l0 = if (offset >= 0.0) lp0 else lp1;
                    // const l1 = if (offset >= 0.0) lp1 else lp0;
                    const line = LineF32.create(transform.apply(lp0), transform.apply(lp1));
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
            writer.write(LineF32.create(start, p0).affineTransform(transform));
            writer.write(LineF32.create(p1, end).affineTransform(transform));

            start = p0;
            end = p1;
        }

        writer.write(LineF32.create(start, end).affineTransform(transform));
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
        const back0 = p0.sub(n_next);
        var back1 = p0.sub(n_prev);

        const cr = tan_prev.x * tan_next.y - tan_prev.y * tan_next.x;
        const d = tan_prev.dot(tan_next);

        switch (stroke.join) {
            .bevel => {
                if (!std.meta.eql(front0, front1) and !std.meta.eql(back0, back1)) {
                    left_writer.write(LineF32.create(front0, front1).affineTransform(transform));
                    right_writer.write(LineF32.create(back1, back0).affineTransform(transform));
                }
            },
            .miter => {
                const hypot = std.math.hypot(cr, d);
                const miter_limit = stroke.miter_limit;

                if (2.0 * hypot < (hypot + d) * miter_limit * miter_limit and cr != 0.0) {
                    const is_backside = cr > 0.0;
                    const fp_last = if (is_backside) back1 else front0;
                    const fp_this = if (is_backside) back0 else front1;
                    const p = if (is_backside) back1 else front0;

                    const v = fp_this.sub(fp_last);
                    const h = (tan_prev.x * v.y - tan_prev.y * v.x) / cr;
                    const miter_pt = fp_this.sub(tan_next.mul(PointF32{
                        .x = h,
                        .y = h,
                    }));

                    if (is_backside) {
                        right_writer.write(LineF32.create(p, miter_pt).affineTransform(transform));
                        back1 = miter_pt;
                    } else {
                        left_writer.write(LineF32.create(p, miter_pt).affineTransform(transform));
                        front0 = miter_pt;
                    }
                }

                right_writer.write(LineF32.create(back1, back0).affineTransform(transform));
                left_writer.write(LineF32.create(front0, front1).affineTransform(transform));
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

                    left_writer.write(LineF32.create(front0, front1).affineTransform(transform));
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

                    right_writer.write(LineF32.create(back0, back1).affineTransform(transform));
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
            .coefficients = [_]f32{ c, -s, 0.0, s, c, 0.0 },
        };

        for (0..n_lines - 1) |n| {
            _ = n;
            r = rot.apply(r);
            const p1 = transform.apply(center.add(r));
            writer.write(LineF32.create(p0, p1));
            p0 = p1;
        }

        const p1 = transform.apply(end);
        writer.write(LineF32.create(p0, p1));
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

    pub fn getCubicPoints(path_tag: PathTag, path_monoid: PathMonoid, segment_data: []const u8) CubicBezierF32 {
        var cubic_points: CubicBezierF32 = undefined;
        const sd = SegmentData{
            .segment_data = segment_data,
        };

        switch (path_tag.segment.kind) {
            .line_f32 => {
                const line = sd.getSegment(LineF32, path_monoid);
                cubic_points.p0 = line.p0;
                cubic_points.p1 = line.p1;
                cubic_points.p3 = cubic_points.p1;
                cubic_points.p2 = cubic_points.p3.lerp(cubic_points.p0, 1.0 / 3.0);
                cubic_points.p1 = cubic_points.p0.lerp(cubic_points.p3, 1.0 / 3.0);
            },
            .line_i16 => {
                const line = sd.getSegment(LineI16, path_monoid).cast(f32);
                cubic_points.p0 = line.p0;
                cubic_points.p1 = line.p1;
                cubic_points.p3 = cubic_points.p1;
                cubic_points.p2 = cubic_points.p3.lerp(cubic_points.p0, 1.0 / 3.0);
                cubic_points.p1 = cubic_points.p0.lerp(cubic_points.p3, 1.0 / 3.0);
            },
            .quadratic_bezier_f32 => {
                const qb = sd.getSegment(QuadraticBezierF32, path_monoid);
                cubic_points.p0 = qb.p0;
                cubic_points.p1 = qb.p1;
                cubic_points.p2 = qb.p2;
                cubic_points.p3 = cubic_points.p2;
                cubic_points.p2 = cubic_points.p1.lerp(cubic_points.p2, 1.0 / 3.0);
                cubic_points.p1 = cubic_points.p1.lerp(cubic_points.p0, 1.0 / 3.0);
            },
            .quadratic_bezier_i16 => {
                const qb = sd.getSegment(QuadraticBezierI16, path_monoid).cast(f32);
                cubic_points.p0 = qb.p0;
                cubic_points.p1 = qb.p1;
                cubic_points.p2 = qb.p2;
                cubic_points.p3 = cubic_points.p2;
                cubic_points.p2 = cubic_points.p1.lerp(cubic_points.p2, 1.0 / 3.0);
                cubic_points.p1 = cubic_points.p1.lerp(cubic_points.p0, 1.0 / 3.0);
            },
            .cubic_bezier_f32 => {
                cubic_points = sd.getSegment(CubicBezierF32, path_monoid);
            },
            .cubic_bezier_i16 => {
                cubic_points = sd.getSegment(CubicBezierI16, path_monoid).cast(f32);
            },
            else => @panic("Cannot get cubic points for Arc"),
        }

        return cubic_points;
    }

    pub const NeighborSegment = struct {
        tangent: PointF32,
    };

    fn readNeighborSegment(
        config: KernelConfig,
        next_segment_index: u32,
        segment_range: RangeU32,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        segment_data: []const u8,
    ) NeighborSegment {
        const index_shifted = (next_segment_index - segment_range.start) % segment_range.size() + segment_range.start;
        const next_path_tag = path_tags[index_shifted];
        const next_path_monoid = path_monoids[index_shifted];
        const cubic_points = getCubicPoints(next_path_tag, next_path_monoid, segment_data);
        const tangent = cubicStartTangent(
            config,
            cubic_points.p0,
            cubic_points.p1,
            cubic_points.p2,
            cubic_points.p3,
        );

        return NeighborSegment{
            .tangent = tangent,
        };
    }

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

    const Writer = struct {
        line_data: []u8,
        offset: u32 = 0,

        pub fn write(self: *@This(), line: LineF32) void {
            if (self.offset == 0) {
                self.addPoint(line.p0);
                self.addPoint(line.p1);
                return;
            }

            const last_point = self.lastPoint();
            if (!std.meta.eql(last_point, line.p0)) {
                var line_iter = encoding_module.LineIterator{
                    .line_data = self.line_data[0..self.offset],
                };

                std.debug.print("=========== Bad Line Data =============:\n", .{});
                while (line_iter.next()) |l| {
                    std.debug.print("{}\n", .{l});
                }
                std.debug.print("--------\n", .{});
                std.debug.print("Bad Line: {}\n", .{line});
                std.debug.print("=================================\n", .{});
                std.debug.assert(false);
            }
            self.addPoint(line.p1);
        }

        fn lastPoint(self: @This()) PointF32 {
            return std.mem.bytesToValue(PointF32, self.line_data[self.offset - @sizeOf(PointF32) .. self.offset]);
        }

        fn addPoint(self: *@This(), point: PointF32) void {
            std.mem.bytesAsValue(PointF32, self.line_data[self.offset .. self.offset + @sizeOf(PointF32)]).* = point;
            self.offset += @sizeOf(PointF32);
        }
    };
};

// pub const Rasterize = struct {
//     const GRID_POINT_TOLERANCE: f32 = 1e-6;

//     pub fn intersect(
//         flat_segment_data: []const u8,
//         range: RangeU32,
//         flat_segment_offsets: []SegmentOffsets,
//         grid_intersections: []GridIntersection,
//     ) void {
//         for (range.start..range.end) |segment_index| {
//             intersectSegment(
//                 @intCast(segment_index),
//                 flat_segment_data,
//                 flat_segment_offsets,
//                 grid_intersections,
//             );
//         }
//     }

//     pub fn intersectSegment(
//         segment_index: u32,
//         flat_segment_data: []const u8,
//         flat_segment_offsets: []SegmentOffsets,
//         grid_intersections: []GridIntersection,
//     ) void {
//         const segment_offsets = &flat_segment_offsets[segment_index];
//         const previous_segment_offsets = if (segment_index > 0) flat_segment_offsets[segment_index - 1] else null;
//         var start_intersection_offset: u32 = 0;
//         var start_line_offset: u32 = 0;
//         if (previous_segment_offsets) |so| {
//             start_intersection_offset = so.fill.intersection.capacity;
//             start_line_offset = so.fill.line.capacity;
//         }
//         const end_intersection_offset = segment_offsets.fill.intersection.capacity;
//         const end_line_offset = segment_offsets.fill.line.end;

//         const intersections = grid_intersections[start_intersection_offset..end_intersection_offset];
//         var intersection_writer = IntersectionWriter{
//             .slice = intersections,
//         };
//         const line_segments = flat_segment_data[start_line_offset..end_line_offset];
//         var line_iter = LineIterator{
//             .segment_data = line_segments,
//         };

//         while (line_iter.next()) |line| {
//             const start_intersection_index = intersection_writer.index;
//             const start_point: PointF32 = line.apply(0.0);
//             const end_point: PointF32 = line.apply(1.0);
//             const bounds_f32: RectF32 = RectF32.create(start_point, end_point);
//             const bounds: RectI32 = RectI32.create(PointI32{
//                 .x = @intFromFloat(@ceil(bounds_f32.min.x)),
//                 .y = @intFromFloat(@ceil(bounds_f32.min.y)),
//             }, PointI32{
//                 .x = @intFromFloat(@floor(bounds_f32.max.x)),
//                 .y = @intFromFloat(@floor(bounds_f32.max.y)),
//             });
//             const scan_bounds = RectF32.create(PointF32{
//                 .x = @floatFromInt(bounds.min.x - 1),
//                 .y = @floatFromInt(bounds.min.y - 1),
//             }, PointF32{
//                 .x = @floatFromInt(bounds.max.x + 1),
//                 .y = @floatFromInt(bounds.max.y + 1),
//             });

//             intersection_writer.addOne().* = GridIntersection.create((IntersectionF32{
//                 .t = 0.0,
//                 .point = start_point,
//             }).fitToGrid());

//             for (0..@as(usize, @intCast(bounds.getWidth())) + 1) |x_offset| {
//                 const grid_x: f32 = @floatFromInt(bounds.min.x + @as(i32, @intCast(x_offset)));
//                 try scanX(grid_x, line, scan_bounds, &intersection_writer);
//             }

//             for (0..@as(usize, @intCast(bounds.getHeight())) + 1) |y_offset| {
//                 const grid_y: f32 = @floatFromInt(bounds.min.y + @as(i32, @intCast(y_offset)));
//                 try scanY(grid_y, line, scan_bounds, &intersection_writer);
//             }

//             intersection_writer.addOne().* = GridIntersection.create((IntersectionF32{
//                 .t = 1.0,
//                 .point = end_point,
//             }).fitToGrid());

//             const end_intersection_index = intersection_writer.index;
//             const line_intersections = intersection_writer.slice[start_intersection_index..end_intersection_index];

//             // need to sort by T for each curve, in order
//             std.mem.sort(
//                 GridIntersection,
//                 line_intersections,
//                 @as(u32, 0),
//                 gridIntersectionLessThan,
//             );
//         }

//         segment_offsets.fill.intersection.end = start_intersection_offset + intersection_writer.index;
//     }

//     fn gridIntersectionLessThan(_: u32, left: GridIntersection, right: GridIntersection) bool {
//         if (left.intersection.t < right.intersection.t) {
//             return true;
//         }

//         return false;
//     }

//     pub fn boundary(
//         half_planes: HalfPlanesU16,
//         path_monoids: []const PathMonoid,
//         paths: []const Path,
//         subpaths: []const Subpath,
//         grid_intersections: []const GridIntersection,
//         flat_segment_offsets: []const SegmentOffsets,
//         range: RangeU32,
//         path_bumps: []std.atomic.Value(u32),
//         boundary_fragments: []BoundaryFragment,
//     ) void {
//         for (range.start..range.end) |segment_index| {
//             boundarySegment(
//                 @intCast(segment_index),
//                 half_planes,
//                 path_monoids,
//                 paths,
//                 subpaths,
//                 grid_intersections,
//                 flat_segment_offsets,
//                 path_bumps,
//                 boundary_fragments,
//             );
//         }
//     }

//     pub fn boundarySegment(
//         segment_index: u32,
//         half_planes: HalfPlanesU16,
//         path_monoids: []const PathMonoid,
//         paths: []const Path,
//         subpaths: []const Subpath,
//         grid_intersections: []const GridIntersection,
//         flat_segment_offsets: []const SegmentOffsets,
//         path_bumps: []std.atomic.Value(u32),
//         boundary_fragments: []BoundaryFragment,
//     ) void {
//         const path_monoid = path_monoids[segment_index];
//         const path = paths[path_monoid.path_index];
//         const subpath = subpaths[path_monoid.subpath_index];

//         var start_boundary_offset: u32 = 0;
//         const previous_path = if (path_monoid.path_index > 0) paths[path_monoid.path_index - 1] else null;
//         if (previous_path) |p| {
//             start_boundary_offset = p.fill.boundary_fragment.capacity;
//         }
//         const end_boundary_offset = path.fill.boundary_fragment.capacity;

//         const previous_subpath = if (path_monoid.subpath_index > 0) subpaths[path_monoid.subpath_index - 1] else null;
//         var start_segment_offset: u32 = 0;
//         if (previous_subpath) |s| {
//             start_segment_offset = s.last_segment_offset;
//         }
//         const end_segment_offset = subpath.last_segment_offset;
//         const previous_segment_offsets = if (segment_index > 0) flat_segment_offsets[segment_index - 1] else null;
//         var start_intersection_offset: u32 = 0;
//         if (previous_segment_offsets) |so| {
//             start_intersection_offset = so.fill.intersection.capacity;
//         }
//         const end_intersection_offset = flat_segment_offsets[segment_index].fill.intersection.end;

//         var path_bump = BumpAllocator{
//             .start = start_boundary_offset,
//             .end = end_boundary_offset,
//             .offset = &path_bumps[path_monoid.path_index],
//         };
//         const segment_grid_intersections = grid_intersections[start_intersection_offset..end_intersection_offset];

//         if (segment_grid_intersections.len == 0) {
//             return;
//         }

//         for (segment_grid_intersections, 0..) |*grid_intersection, index| {
//             var next_grid_intersection: GridIntersection = undefined;
//             const next_index = index + 1;

//             if (next_index >= segment_grid_intersections.len) {
//                 const next_segment_index = (segment_index + 1 - start_segment_offset) % (end_segment_offset - start_segment_offset) + start_segment_offset;
//                 const previous_next_segment_offsets = if (next_segment_index > 0) flat_segment_offsets[next_segment_index - 1] else null;
//                 var start_next_intersection_offset: u32 = 0;
//                 if (previous_next_segment_offsets) |so| {
//                     start_next_intersection_offset = so.fill.intersection.capacity;
//                 }

//                 next_grid_intersection = grid_intersections[start_next_intersection_offset];
//             } else {
//                 next_grid_intersection = segment_grid_intersections[next_index];
//             }

//             if (grid_intersection.intersection.point.approxEqAbs(next_grid_intersection.intersection.point, GRID_POINT_TOLERANCE)) {
//                 // skip if exactly the same point
//                 continue;
//             }

//             {
//                 const boundary_fragment_index = path_bump.bump(1);
//                 boundary_fragments[boundary_fragment_index] = BoundaryFragment.create(
//                     half_planes,
//                     [_]*const GridIntersection{
//                         grid_intersection,
//                         &next_grid_intersection,
//                     },
//                 );
//             }
//         }
//     }

//     pub fn merge(
//         paths: []const Path,
//         boundary_fragments: []const BoundaryFragment,
//         range: RangeU32,
//         path_bumps: []std.atomic.Value(u32),
//         merge_fragments: []MergeFragment,
//     ) void {
//         for (range.start..range.end) |path_index| {
//             mergePath(
//                 @intCast(path_index),
//                 paths,
//                 boundary_fragments,
//                 path_bumps,
//                 merge_fragments,
//             );
//         }
//     }

//     pub fn mergePath(
//         path_index: u32,
//         paths: []const Path,
//         boundary_fragments: []const BoundaryFragment,
//         path_bumps: []std.atomic.Value(u32),
//         merge_fragments: []MergeFragment,
//     ) void {
//         const path = paths[path_index];
//         var start_boundary_offset: u32 = 0;
//         var start_merge_offset: u32 = 0;
//         const previous_path = if (path_index > 0) paths[path_index - 1] else null;
//         if (previous_path) |p| {
//             start_boundary_offset = p.fill.boundary_fragment.capacity;
//             start_merge_offset = p.fill.merge_fragment.capacity;
//         }
//         const end_boundary_offset = path.fill.boundary_fragment.end;
//         const end_merge_offset = path.fill.merge_fragment.capacity;
//         var bump = BumpAllocator{
//             .start = start_merge_offset,
//             .end = end_merge_offset,
//             .offset = &path_bumps[path_index],
//         };
//         const path_boundary_fragments = boundary_fragments[start_boundary_offset..end_boundary_offset];

//         var merge_fragment = &merge_fragments[bump.bump(1)];
//         merge_fragment.* = MergeFragment{
//             .pixel = boundary_fragments[start_boundary_offset].pixel,
//         };
//         for (path_boundary_fragments, 0..) |*boundary_fragment, boundary_fragment_index| {
//             if (boundary_fragment.pixel.x != merge_fragment.pixel.x or boundary_fragment.pixel.y != merge_fragment.pixel.y) {
//                 merge_fragment.boundary_offset = start_boundary_offset + @as(u32, @intCast(boundary_fragment_index));

//                 merge_fragment = &merge_fragments[bump.bump(1)];
//                 merge_fragment.* = MergeFragment{
//                     .pixel = boundary_fragment.pixel,
//                 };
//             }
//         }

//         merge_fragment.boundary_offset = end_boundary_offset;
//     }

//     pub fn mask(
//         config: KernelConfig,
//         paths: []const Path,
//         boundary_fragments: []const BoundaryFragment,
//         range: RangeU32,
//         merge_fragments: []MergeFragment,
//     ) void {
//         for (range.start..range.end) |path_index| {
//             const path = paths[path_index];
//             var start_merge_offset: u32 = 0;
//             const previous_path = if (path_index > 0) paths[path_index - 1] else null;
//             if (previous_path) |p| {
//                 start_merge_offset = p.fill.merge_fragment.capacity;
//             }
//             const end_merge_offset = path.fill.merge_fragment.end;
//             const path_merge_fragments = merge_fragments[start_merge_offset..end_merge_offset];
//             const merge_range = RangeU32{
//                 .start = 0,
//                 .end = end_merge_offset - start_merge_offset,
//             };

//             var chunk_iter = merge_range.chunkIterator(config.chunk_size);

//             while (chunk_iter.next()) |chunk| {
//                 maskPath(
//                     chunk,
//                     boundary_fragments,
//                     path_merge_fragments,
//                 );
//             }
//         }
//     }

//     pub fn maskPath(
//         range: RangeU32,
//         boundary_fragments: []const BoundaryFragment,
//         merge_fragments: []MergeFragment,
//     ) void {
//         for (range.start..range.end) |merge_fragment_index| {
//             maskFragment(
//                 @intCast(merge_fragment_index),
//                 boundary_fragments,
//                 merge_fragments,
//             );
//         }
//     }

//     pub fn maskFragment(
//         merge_fragment_index: u32,
//         boundary_fragments: []const BoundaryFragment,
//         merge_fragments: []MergeFragment,
//     ) void {
//         const merge_fragment = &merge_fragments[merge_fragment_index];
//         var start_boundary_fragment_offset: u32 = 0;
//         const previous_merge_fragment = if (merge_fragment_index > 0) merge_fragments[merge_fragment_index - 1] else null;
//         if (previous_merge_fragment) |f| {
//             start_boundary_fragment_offset = f.boundary_offset;
//         }
//         const end_boundary_fragment_offset = merge_fragment.boundary_offset;
//         const merge_boundary_fragments = boundary_fragments[start_boundary_fragment_offset..end_boundary_fragment_offset];

//         // calculate main ray winding
//         var main_ray_winding: f32 = 0.0;
//         for (merge_boundary_fragments) |boundary_fragment| {
//             main_ray_winding += boundary_fragment.calculateMainRayWinding();
//         }

//         // calculate stencil mask
//         for (0..16) |index| {
//             const bit_index: u16 = @as(u16, 1) << @as(u4, @intCast(index));
//             var bit_winding: f32 = main_ray_winding;

//             for (merge_boundary_fragments) |boundary_fragment| {
//                 const masks = boundary_fragment.masks;
//                 const vertical_winding0 = masks.vertical_sign0 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask0 & bit_index != 0)));
//                 const vertical_winding1 = masks.vertical_sign1 * @as(f32, @floatFromInt(@intFromBool(masks.vertical_mask1 & bit_index != 0)));
//                 const horizontal_winding = masks.horizontal_sign * @as(f32, @floatFromInt(@intFromBool(masks.horizontal_mask & bit_index != 0)));
//                 bit_winding += vertical_winding0 + vertical_winding1 + horizontal_winding;
//             }

//             merge_fragment.stencil_mask = merge_fragment.stencil_mask | (@as(u16, @intFromBool(bit_winding != 0.0)) * bit_index);
//         }
//     }

//     pub fn Writer(comptime T: type) type {
//         return struct {
//             slice: []T,
//             index: u16 = 0,

//             pub fn create(slice: []T) @This() {
//                 return @This(){
//                     .slice = slice,
//                 };
//             }

//             pub fn addOne(self: *@This()) *T {
//                 const item = &self.slice[self.index];
//                 self.index += 1;
//                 return item;
//             }

//             pub fn toSlice(self: @This()) []T {
//                 return self.slice[0..self.index];
//             }
//         };
//     }

//     const IntersectionWriter = Writer(GridIntersection);
//     const BoundaryFragmentWriter = Writer(BoundaryFragment);
//     const MergeFragmentWriter = Writer(MergeFragment);

//     fn scanX(
//         grid_x: f32,
//         line: LineF32,
//         scan_bounds: RectF32,
//         intersection_writer: *IntersectionWriter,
//     ) !void {
//         const scan_line = LineF32.create(
//             PointF32{
//                 .x = grid_x,
//                 .y = scan_bounds.min.y,
//             },
//             PointF32{
//                 .x = grid_x,
//                 .y = scan_bounds.max.y,
//             },
//         );

//         if (line.intersectVerticalLine(scan_line)) |intersection| {
//             intersection_writer.addOne().* = GridIntersection.create(intersection.fitToGrid());
//         }
//     }

//     fn scanY(
//         grid_y: f32,
//         line: LineF32,
//         scan_bounds: RectF32,
//         intersection_writer: *IntersectionWriter,
//     ) !void {
//         const scan_line = LineF32.create(
//             PointF32{
//                 .x = scan_bounds.min.x,
//                 .y = grid_y,
//             },
//             PointF32{
//                 .x = scan_bounds.max.x,
//                 .y = grid_y,
//             },
//         );

//         if (line.intersectHorizontalLine(scan_line)) |intersection| {
//             intersection_writer.addOne().* = GridIntersection.create(intersection.fitToGrid());
//         }
//     }
// };
