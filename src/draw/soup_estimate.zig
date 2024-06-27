const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const pen = @import("./pen.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const scene_module = @import("./scene.zig");
const soup_module = @import("./soup.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;
const PathMetadata = path_module.PathMetadata;
const Paths = path_module.Paths;
const PathsData = path_module.PathsData;
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
const CurveEstimate = soup_module.CurveEstimate;

pub const ArcEstimate = struct {
    items: u32 = 0,
    length: f32 = 0.0,
};

pub fn SoupEstimator(comptime T: type, comptime EstimatorImpl: type) type {
    const S = Soup(T);

    return struct {
        const RSQRT_OF_TOL: f64 = 2.2360679775; // tol = 0.2

        pub fn estimateSceneAlloc(allocator: Allocator, scene: Scene) !S {
            return try estimateAlloc(
                allocator,
                scene.metadata.items,
                scene.styles.items,
                scene.transforms.items,
                scene.paths.toPathsData(),
            );
        }

        pub fn estimateAlloc(
            allocator: Allocator,
            metadatas: []const PathMetadata,
            styles: []const Style,
            transforms: []const TransformF32.Matrix,
            paths: PathsData,
        ) !S {
            var soup = S.init(allocator);
            errdefer soup.deinit();

            const base_estimates = try soup.addBaseEstimates(paths.curve_records.len);

            for (metadatas) |metadata| {
                if (metadata.path_offsets.size() == 0) {
                    continue;
                }

                const transform = transforms[metadata.transform_index];
                const start_path_record = paths.path_records[metadata.path_offsets.start];
                const end_path_record = paths.path_records[metadata.path_offsets.end - 1];
                const start_subpath_record = paths.subpath_records[start_path_record.subpath_offsets.start];
                const end_subpath_record = paths.subpath_records[end_path_record.subpath_offsets.end - 1];
                const curve_records = paths.curve_records[start_subpath_record.curve_offsets.start..end_subpath_record.curve_offsets.end];
                const curve_estimates = base_estimates[start_subpath_record.curve_offsets.start..end_subpath_record.curve_offsets.end];

                for (curve_records, curve_estimates) |curve_record, *curve_estimate| {
                    curve_estimate.* = estimateCurveBase(paths, curve_record, transform);
                }
            }

            for (metadatas, 0..) |metadata, metadata_index| {
                const style = styles[metadata.style_index];

                const path_records = paths.path_records[metadata.path_offsets.start..metadata.path_offsets.end];
                if (style.isFilled()) {
                    for (path_records) |path_record| {
                        _ = try soup.openPath();
                        const subpath_records = paths.subpath_records[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                        for (subpath_records) |subpath_record| {
                            const soup_subpath_record = try soup.openSubpath();

                            const subpath_base_estimates = soup.base_estimates.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
                            const fill_curve_estimates = try soup.addCurveEstimates(subpath_base_estimates.len);
                            const fill_jobs = try soup.addFillJobs(subpath_base_estimates.len);
                            for (
                                subpath_base_estimates,
                                fill_curve_estimates,
                                fill_jobs,
                                0..,
                            ) |
                                base_estimate,
                                *fill_curve_estimate,
                                *fill_job,
                                curve_offset,
                            | {
                                fill_curve_estimate.* = base_estimate;
                                _ = try soup.openCurve();

                                _ = try soup.addItems(fill_curve_estimate.items);
                                const source_curve_index = subpath_record.curve_offsets.start + @as(u32, @intCast(curve_offset));
                                const curve_index = soup_subpath_record.curve_offsets.start + @as(u32, @intCast(curve_offset));

                                fill_job.* = S.FillJob{
                                    .metadata_index = @intCast(metadata_index),
                                    .source_curve_index = source_curve_index,
                                    .curve_index = curve_index,
                                };

                                soup.closeCurve();
                            }

                            soup.closeSubpath();
                        }
                        soup.closePath();
                    }
                }

                if (style.stroke) |stroke| {
                    const transform = transforms[metadata.transform_index];
                    const scaled_width = stroke.width * transform.getScale();
                    const offset_fudge: f32 = @max(1.0, std.math.sqrt(scaled_width));

                    for (path_records) |path_record| {
                        const subpath_records = paths.subpath_records[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                        for (subpath_records, 0..) |subpath_record, subpath_record_offset| {
                            const curve_record_len = subpath_record.curve_offsets.size();
                            const curve_records = paths.curve_records[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
                            const subpath_base_estimates = soup.base_estimates.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];

                            _ = try soup.openPath();

                            if (paths.isSubpathCapped(subpath_record)) {
                                // subpath is capped, so the stroke will be a single subpath
                                const soup_subpath_record = try soup.openSubpath();

                                const left_curve_estimates = try soup.addCurveEstimates(curve_record_len);

                                // need two curve records per each curve record in source
                                // calculate side without caps
                                for (subpath_base_estimates, left_curve_estimates) |base_estimate, *curve_estimate| {
                                    _ = try soup.openCurve();
                                    curve_estimate.* = base_estimate.mulScalar(offset_fudge).add(
                                        estimateStrokeJoin(stroke.join, scaled_width, stroke.miter_limit),
                                    );
                                    _ = try soup.addItems(curve_estimate.items);
                                    soup.closeCurve();
                                }

                                // calculate side with caps
                                const right_curve_estimates = try soup.addCurveEstimates(curve_record_len);
                                for (right_curve_estimates, 0..) |*curve_estimate, offset| {
                                    const curve_record = curve_records[curve_records.len - (1 + offset)];
                                    const base_estimate = left_curve_estimates[left_curve_estimates.len - (1 + offset)];
                                    curve_estimate.* = base_estimate;
                                    curve_estimate.* = base_estimate.add(estimateCurveCap(curve_record, stroke, scaled_width));
                                    _ = try soup.openCurve();
                                    _ = try soup.addItems(curve_estimate.items);
                                    soup.closeCurve();
                                }

                                soup.closeSubpath();

                                const stroke_jobs = try soup.addStrokeJobs(curve_record_len);
                                for (stroke_jobs, 0..) |*stroke_job, offset| {
                                    const left_curve_index = soup_subpath_record.curve_offsets.start + @as(u32, @intCast(offset));
                                    const right_curve_index = soup_subpath_record.curve_offsets.end - (1 + @as(u32, @intCast(offset)));
                                    stroke_job.* = S.StrokeJob{
                                        .metadata_index = @intCast(metadata_index),
                                        .source_subpath_index = path_record.subpath_offsets.start + @as(u32, @intCast(subpath_record_offset)),
                                        .source_curve_index = subpath_record.curve_offsets.start + @as(u32, @intCast(offset)),
                                        .left_curve_index = left_curve_index,
                                        .right_curve_index = right_curve_index,
                                    };
                                }
                            } else {
                                // subpath is not capped, so the stroke will be two subpaths
                                const left_soup_subpath_record = try soup.openSubpath();
                                const left_curve_estimates = try soup.addCurveEstimates(curve_record_len);
                                for (subpath_base_estimates, left_curve_estimates) |base_estimate, *curve_estimate| {
                                    _ = try soup.openCurve();
                                    curve_estimate.* = base_estimate.mulScalar(offset_fudge).add(
                                        estimateStrokeJoin(stroke.join, scaled_width, stroke.miter_limit),
                                    );
                                    _ = try soup.addItems(curve_estimate.items);
                                    soup.closeCurve();
                                }
                                soup.closeSubpath();

                                const right_soup_subpath_record = try soup.openSubpath();
                                const right_curve_estimates = try soup.addCurveEstimates(curve_record_len);
                                for (right_curve_estimates, 0..) |*curve_estimate, offset| {
                                    const base_estimate = left_curve_estimates[left_curve_estimates.len - (1 + offset)];
                                    curve_estimate.* = base_estimate;
                                    _ = try soup.openCurve();
                                    _ = try soup.addItems(curve_estimate.items);
                                    soup.closeCurve();
                                }
                                soup.closeSubpath();

                                const stroke_jobs = try soup.addStrokeJobs(curve_record_len);
                                for (stroke_jobs, 0..) |*stroke_job, offset| {
                                    const left_curve_index = left_soup_subpath_record.curve_offsets.start + @as(u32, @intCast(offset));
                                    const right_curve_index = right_soup_subpath_record.curve_offsets.end - (1 + @as(u32, @intCast(offset)));
                                    stroke_job.* = S.StrokeJob{
                                        .metadata_index = @intCast(metadata_index),
                                        .source_subpath_index = path_record.subpath_offsets.start + @as(u32, @intCast(subpath_record_offset)),
                                        .source_curve_index = subpath_record.curve_offsets.start + @as(u32, @intCast(offset)),
                                        .left_curve_index = left_curve_index,
                                        .right_curve_index = right_curve_index,
                                    };
                                }
                            }

                            soup.closePath();
                        }
                    }
                }
            }

            return soup;
        }

        fn estimateCurveBase(
            paths: PathsData,
            curve_record: Paths.CurveRecord,
            transform: TransformF32.Matrix,
        ) Estimate {
            var estimate = Estimate{};

            switch (curve_record.kind) {
                .line => {
                    const points = paths.points[curve_record.point_offsets.start..curve_record.point_offsets.end];
                    estimate.intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateLineIntersections(points[0], points[1], transform)));
                    estimate.items += @as(u32, @intFromFloat(EstimatorImpl.estimateLineItems(points[0], points[1], transform)));
                },
                .quadratic_bezier => {
                    const points = paths.points[curve_record.point_offsets.start..curve_record.point_offsets.end];
                    estimate.intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateQuadraticIntersections(points[0], points[1], points[2], transform)));
                    estimate.items += @as(u32, @intFromFloat(Wang.quadratic(
                        @floatCast(RSQRT_OF_TOL),
                        points[0],
                        points[1],
                        points[2],
                        transform,
                    )));
                },
            }

            return estimate;
        }

        fn estimateCurveCap(
            curve_record: Paths.CurveRecord,
            stroke: Style.Stroke,
            scaled_width: f32,
        ) Estimate {
            switch (curve_record.cap) {
                .start => {
                    return estimateStrokeCap(stroke.start_cap, scaled_width);
                },
                .end => {
                    return estimateStrokeCap(stroke.end_cap, scaled_width);
                },
                .none => {
                    return Estimate{};
                },
            }
        }

        fn estimateStrokeCap(cap: Style.Cap, scaled_width: f32) Estimate {
            switch (cap) {
                .butt => {
                    return Estimate{
                        .intersections = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(scaled_width))),
                        .items = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width))),
                    };
                },
                .square => {
                    var intersections = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(scaled_width)));
                    intersections += 2 * @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(0.5 * scaled_width)));
                    var items = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width)));
                    items += 2 * @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(0.5 * scaled_width)));
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

        fn estimateStrokeJoin(join: Style.Join, scaled_width: f32, miter_limit: f32) Estimate {
            var inner_estimate = Estimate{
                .intersections = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(scaled_width))),
                .items = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width))),
            };
            var outer_estimate = Estimate{};

            switch (join) {
                .bevel => {
                    outer_estimate.intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(scaled_width)));
                    outer_estimate.items += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width)));
                },
                .miter => {
                    const max_miter_len = scaled_width * miter_limit;
                    outer_estimate.intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(max_miter_len))) * 2;
                    outer_estimate.items += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(max_miter_len))) * 2;
                },
                .round => {
                    const arc_estimate: ArcEstimate = EstimatorImpl.estimateArc(scaled_width);
                    outer_estimate.intersections += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthIntersections(arc_estimate.length))) * arc_estimate.items;
                    outer_estimate.items += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(arc_estimate.length))) * arc_estimate.items;
                },
            }

            return inner_estimate.max(outer_estimate);
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
