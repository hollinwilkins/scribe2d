const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const pen = @import("./pen.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const scene_module = @import("./scene.zig");
const soup_module = @import("./soup.zig");
const encoding_module = @import("./encoding.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;
const PathMetadata = path_module.PathMetadata;
const Paths = path_module.Paths;
const Style = pen.Style;
const Line = curve_module.Line;
const Arc = curve_module.Arc;
const CubicPoints = euler.CubicPoints;
const CubicParams = euler.CubicParams;
const EulerParams = euler.EulerParams;
const EulerSegment = euler.EulerSegment;
const Scene = scene_module.Scene;
const Soup = soup_module.Soup;
const Estimate = soup_module.Estimate;
const SubpathEstimate = soup_module.SubpathEstimate;
const SoupEncoding = encoding_module.SoupEncoding;

pub const ArcEstimate = struct {
    items: u32 = 0,
    length: f32 = 0.0,
};

pub fn SoupEstimator(comptime T: type, comptime EstimatorImpl: type) type {
    const S = Soup(T);
    const E = SoupEncoding(T);

    return struct {
        const RSQRT_OF_TOL: f64 = 2.2360679775; // tol = 0.2

        pub fn estimateSceneAlloc(allocator: Allocator, scene: Scene) !E {
            return try estimateAlloc(
                allocator,
                scene.metadata.items,
                scene.styles.items,
                scene.transforms.items,
                scene.paths,
            );
        }

        pub fn estimateAlloc(
            allocator: Allocator,
            metadatas: []const PathMetadata,
            styles: []const Style,
            transforms: []const TransformF32.Matrix,
            paths: Paths,
        ) !E {
            var flat_data = E.init(allocator);
            errdefer flat_data.deinit();

            for (metadatas) |metadata| {
                const style = styles[metadata.style_index];
                const transform = transforms[metadata.transform_index];

                const path_records = paths.path_records.items[metadata.path_offsets.start..metadata.path_offsets.end];
                for (path_records) |path_record| {
                    var fill_path_record: ?*S.PathRecord = null;
                    if (style.fill) |fill| {
                        const fpr = try flat_data.fill.openPath();
                        fpr.fill = fill;
                        fill_path_record = fpr;
                    }

                    const subpath_records = paths.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                    for (subpath_records) |subpath_record| {
                        const subpath_estimate = estimateSubpath(paths, subpath_record, style, transform);

                        if (style.isFilled()) {
                            _ = try flat_data.fill.openSubpath();
                            _ = try flat_data.fill.addItems(subpath_estimate.fill.items);
                            (try flat_data.fill.addSubpathEstimate()).* = subpath_estimate;
                            flat_data.fill.closeSubpath();
                        }

                        if (style.stroke) |stroke| {
                            if (paths.isSubpathCapped(subpath_record)) {
                                // subpath is capped, so the stroke will be a single subpath
                                const stroke_path_record = try flat_data.stroke.openPath();
                                stroke_path_record.fill = stroke.toFill();

                                _ = try flat_data.stroke.openSubpath();
                                _ = try flat_data.stroke.addItems(subpath_estimate.stroke.items * 2);
                                (try flat_data.fill.addSubpathEstimate()).* = subpath_estimate;
                                flat_data.stroke.closeSubpath();

                                flat_data.stroke.closePath();
                            } else {
                                // subpath is not capped, so the stroke will be two subpaths
                                const stroke_path_record = try flat_data.stroke.openPath();
                                stroke_path_record.fill = stroke.toFill();

                                _ = try flat_data.stroke.openSubpath();
                                _ = try flat_data.stroke.addItems(subpath_estimate.stroke.items);
                                (try flat_data.fill.addSubpathEstimate()).* = subpath_estimate;
                                flat_data.stroke.closeSubpath();

                                _ = try flat_data.stroke.openSubpath();
                                _ = try flat_data.stroke.addItems(subpath_estimate.stroke.items);
                                (try flat_data.fill.addSubpathEstimate()).* = subpath_estimate;
                                flat_data.stroke.closeSubpath();

                                flat_data.stroke.closePath();
                            }
                        }
                    }

                    if (style.isFilled()) {
                        flat_data.fill.closePath();
                    }
                }
            }

            return flat_data;
        }

        fn estimateSubpath(
            paths: Paths,
            subpath_record: Paths.SubpathRecord,
            style: Style,
            transform: TransformF32.Matrix,
        ) SubpathEstimate {
            if (!(style.isFilled() or style.isStroked())) {
                return SubpathEstimate{};
            }

            var intersections: u32 = 0;
            var items: u32 = 0;
            var joins: u32 = 0;
            var lines: u32 = 0;
            var quadratics: u32 = 0;
            var last_point: ?PointF32 = null;

            const curve_records = paths.curve_records.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
            for (curve_records) |curve_record| {
                switch (curve_record.kind) {
                    .line => {
                        const points = paths.points.items[curve_record.point_offsets.start..curve_record.point_offsets.end];
                        last_point = points[1];
                        intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateLineIntersections(points[0], points[1], transform)));
                        joins += 1;
                        lines += 1;
                        items += @as(u32, @intFromFloat(EstimatorImpl.estimateLineItems(points[0], points[1], transform)));
                    },
                    .quadratic_bezier => {
                        const points = paths.points.items[curve_record.point_offsets.start..curve_record.point_offsets.end];
                        last_point = points[2];
                        intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateQuadraticIntersections(points[0], points[1], points[2], transform)));
                        joins += 1;
                        quadratics += 1;
                        items += @as(u32, @intFromFloat(Wang.quadratic(
                            @floatCast(RSQRT_OF_TOL),
                            points[0],
                            points[1],
                            points[2],
                            transform,
                        )));
                    },
                }
            }

            var estimate = SubpathEstimate{};
            const base_estimate = Estimate{
                .intersections = intersections,
                .items = items,
            };
            if (style.isFilled()) {
                estimate.fill = base_estimate;
            }

            if (style.stroke) |stroke| {
                const scaled_width = stroke.width * transform.getScale();
                const offset_fudge: f32 = @max(1.0, std.math.sqrt(scaled_width));

                const start_cap_estimate = estimateStrokeCaps(stroke.start_cap, scaled_width, 1);
                const end_cap_estimate = estimateStrokeCaps(stroke.end_cap, scaled_width, 1);
                const join_estimate = estimateStrokeJoins(stroke.join, scaled_width, stroke.miter_limit, joins);

                const stroke_estimate = base_estimate.mulScalar(offset_fudge).add(start_cap_estimate.add(end_cap_estimate).add(join_estimate));
                estimate.stroke = stroke_estimate;
            }

            return estimate;
        }

        fn estimateStrokeCaps(cap: Style.Cap, scaled_width: f32, count: u32) Estimate {
            switch (cap) {
                .butt => {
                    return Estimate{
                        .intersections = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(scaled_width))) * count,
                        .items = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width))) * count,
                    };
                },
                .square => {
                    var intersections = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(scaled_width))) * count;
                    intersections += 2 * @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(0.5 * scaled_width))) * count;
                    var items = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width))) * count;
                    items += 2 * @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(0.5 * scaled_width))) * count;
                    return Estimate{
                        .intersections = intersections,
                        .items = items,
                    };
                },
                .round => {
                    const arc_estimate: ArcEstimate = EstimatorImpl.estimateArc(scaled_width);
                    return Estimate{
                        .intersections = @intFromFloat(EstimatorImpl.estimateLineLengthItems(arc_estimate.length)),
                        .items = arc_estimate.items,
                    };
                },
            }
        }

        fn estimateStrokeJoins(join: Style.Join, scaled_width: f32, miter_limit: f32, count: u32) Estimate {
            var estimate = Estimate{
                .intersections = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(scaled_width))) * count,
                .items = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width))) * count,
            };

            switch (join) {
                .bevel => {
                    estimate.intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(scaled_width))) * count;
                    estimate.items += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width))) * count;
                },
                .miter => {
                    const max_miter_len = scaled_width * miter_limit;
                    estimate.intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(max_miter_len))) * 2 * count;
                    estimate.items += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(max_miter_len))) * 2 * count;
                },
                .round => {
                    const arc_estimate: ArcEstimate = EstimatorImpl.estimateArc(scaled_width);
                    estimate.intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(arc_estimate.length))) * arc_estimate.items * count;
                    estimate.items += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(arc_estimate.length))) * arc_estimate.items * count;
                },
            }

            return estimate;
        }
    };
}

pub const LineSoupEstimator = SoupEstimator(Line, LineEstimatorImpl);

pub const LineEstimatorImpl = struct {
    pub fn estimateLineItems(_: PointF32, _: PointF32, _: TransformF32.Matrix) f32 {
        return 1.0;
    }

    pub fn estimateLineLengthItems(_: f32) f32 {
        return 1.0;
    }

    pub fn estimateLineIntersections(p0: PointF32, p1: PointF32, transform: TransformF32.Matrix) f32 {
        const dxdy = transform.applyScale(p0.sub(p1));
        const segments = @floor(@abs(dxdy.x)) + @floor(@abs(dxdy.y));
        return @max(1.0, segments);
    }

    pub fn estimateLineLengthIntersections(scaled_width: f32) f32 {
        return @max(1.0, @floor(scaled_width) * 2.0);
    }

    pub fn estimateQuadraticIntersections(p0: PointF32, p1: PointF32, p2: PointF32, transform: TransformF32.Matrix) f32 {
        return estimateCubicIntersections(
            p0,
            p1.lerp(p0, 0.333333),
            p1.lerp(p2, 0.333333),
            p2,
            transform,
        );
    }

    pub fn estimateCubicIntersections(p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32, transform: TransformF32.Matrix) f32 {
        const pt0 = transform.applyScale(p0);
        const pt1 = transform.applyScale(p1);
        const pt2 = transform.applyScale(p2);
        const pt3 = transform.applyScale(p3);
        return @ceil(approxArcLengthCubic(pt0, pt1, pt2, pt3)) * 2.0;
    }

    fn approxArcLengthCubic(p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32) f32 {
        const chord_len = (p3.sub(p0)).length();
        // Length of the control polygon
        const poly_len = (p1.sub(p0)).length() + (p2.sub(p1)).length() + (p3.sub(p2)).length();
        return 0.5 * (chord_len + poly_len);
    }

    fn estimateArc(scaled_width: f32) ArcEstimate {
        const MIN_THETA: f32 = 1e-6;
        const TOL: f32 = 0.25;
        const radius = @max(TOL, scaled_width * 0.5);
        const theta = @max(MIN_THETA, (2.0 * std.math.acos(1.0 - TOL / radius)));
        const arc_lines = @max(2, @as(u32, @intFromFloat(@ceil((std.math.pi / 2.0) / theta))));

        return ArcEstimate{
            .items = arc_lines,
            .length = 2.0 * std.math.sin(theta) * radius,
        };
    }
};

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

    pub fn quadratic(rsqrt_of_tol: f32, p0: PointF32, p1: PointF32, p2: PointF32, transform: TransformF32.Matrix) f32 {
        const v = transform.applyScale(p1.add(p0).add(p2).mulScalar(-2.0));
        const m = v.length();
        return @ceil(SQRT_OF_DEGREE_TERM_QUAD * std.math.sqrt(m) * rsqrt_of_tol);
    }

    pub fn cubic(rsqrt_of_tol: f32, p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32, transform: TransformF32.Matrix) f32 {
        const v1 = transform.applyScale(p1.add(p0).add(p2).mulScalar(-2.0));
        const v2 = transform.applyScale(p2.add(p1).add(p3).mulScalar(-2.0));
        const m = @max(v1.length(), v2.length());
        return @ceil(SQRT_OF_DEGREE_TERM_CUBIC * std.math.sqrt(m) * rsqrt_of_tol);
    }
};
