const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const soup_pen = @import("./soup_pen.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const scene_module = @import("./scene.zig");
const soup_module = @import("./soup.zig");
const flatten_module = @import("./flatten.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;
const PathMetadata = path_module.PathMetadata;
const Paths = path_module.Paths;
const Style = soup_pen.Style;
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
const FillJob = soup_module.FillJob;
const StrokeJob = soup_module.StrokeJob;
const ERROR_TOLERANCE = flatten_module.ERROR_TOLERANCE;

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
            paths: Paths,
        ) !S {
            var soup = S.init(allocator);
            errdefer soup.deinit();

            const base_estimates = try soup.addBaseEstimates(paths.curves.items.len);

            for (metadatas) |metadata| {
                if (metadata.path_offsets.size() == 0) {
                    continue;
                }

                const transform = transforms[metadata.transform_index];
                const start_path_record = paths.paths.items[metadata.path_offsets.start];
                const end_path_record = paths.paths.items[metadata.path_offsets.end - 1];
                const start_subpath_record = paths.subpaths.items[start_path_record.subpath_offsets.start];
                const end_subpath_record = paths.subpaths.items[end_path_record.subpath_offsets.end - 1];
                const curve_records = paths.curves.items[start_subpath_record.curve_offsets.start..end_subpath_record.curve_offsets.end];
                const curve_estimates = base_estimates[start_subpath_record.curve_offsets.start..end_subpath_record.curve_offsets.end];

                for (curve_records, curve_estimates) |curve_record, *curve_estimate| {
                    curve_estimate.* = estimateCurveBase(paths, curve_record, transform);
                }
            }

            for (metadatas) |metadata| {
                const style = styles[metadata.style_index];

                const path_records = paths.paths.items[metadata.path_offsets.start..metadata.path_offsets.end];
                if (style.fill) |fill| {
                    for (path_records) |path_record| {
                        const soup_path_record = try soup.addFlatPath();
                        soup.openFlatPathSubpaths(soup_path_record);
                        soup_path_record.fill = fill;

                        const subpath_records = paths.subpaths.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                        for (subpath_records) |subpath_record| {
                            const soup_subpath_record = try soup.addFlatSubpath();
                            soup.openFlatSubpathCurves(soup_subpath_record);

                            const subpath_base_estimates = soup.base_estimates.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
                            const fill_curve_estimates = try soup.addFlatCurveEstimates(subpath_base_estimates.len);
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
                                const soup_curve_record = try soup.addFlatCurve();
                                soup.openFlatCurveItems(soup_curve_record);

                                _ = try soup.addItems(fill_curve_estimate.*);
                                const source_curve_index = subpath_record.curve_offsets.start + @as(u32, @intCast(curve_offset));
                                const curve_index = soup_subpath_record.flat_curve_offsets.start + @as(u32, @intCast(curve_offset));

                                fill_job.* = FillJob{
                                    .transform_index = metadata.transform_index,
                                    .source_curve_index = source_curve_index,
                                    .curve_index = curve_index,
                                };

                                soup.closeFlatCurveItems(soup_curve_record);
                            }

                            soup.closeFlatSubpathCurves(soup_subpath_record);
                        }
                        soup.closeFlatPathSubpaths(soup_path_record);
                    }
                }

                if (style.stroke) |stroke| {
                    const fill = stroke.toFill();
                    const transform = transforms[metadata.transform_index];
                    const scaled_width = stroke.width * transform.getScale();
                    const offset_fudge: f32 = @max(1.0, std.math.sqrt(scaled_width));

                    for (path_records) |path_record| {
                        const subpath_records = paths.subpaths.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                        for (subpath_records, 0..) |subpath_record, subpath_record_offset| {
                            const curve_record_len = subpath_record.curve_offsets.size();
                            const curve_records = paths.curves.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
                            const subpath_base_estimates = soup.base_estimates.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];

                            const soup_path_record = try soup.addFlatPath();
                            soup.openFlatPathSubpaths(soup_path_record);
                            soup_path_record.fill = fill;

                            if (paths.isSubpathCapped(subpath_record)) {
                                // subpath is capped, so the stroke will be a single subpath
                                const soup_subpath_record = try soup.addFlatSubpath();
                                soup.openFlatSubpathCurves(soup_subpath_record);

                                const curve_estimates = try soup.addFlatCurveEstimates(curve_record_len * 2);
                                const left_curve_estimates = curve_estimates[0..curve_record_len];
                                const right_curve_estimates = curve_estimates[curve_record_len..];

                                // need two curve records per each curve record in source
                                // calculate side without caps
                                for (subpath_base_estimates, right_curve_estimates) |base_estimate, *curve_estimate| {
                                    const soup_curve_record = try soup.addFlatCurve();
                                    soup.openFlatCurveItems(soup_curve_record);

                                    curve_estimate.* = @as(u32, @intFromFloat((@as(f32, @floatFromInt(base_estimate)) * offset_fudge))) +
                                        estimateStrokeJoin(stroke.join, scaled_width, stroke.miter_limit);
                                    _ = try soup.addItems(curve_estimate.*);

                                    soup.closeFlatCurveItems(soup_curve_record);
                                }

                                // calculate side with caps
                                for (left_curve_estimates, 0..) |*curve_estimate, offset| {
                                    const curve_record = curve_records[curve_records.len - (1 + offset)];
                                    const base_estimate = right_curve_estimates[left_curve_estimates.len - (1 + offset)];
                                    curve_estimate.* = base_estimate + estimateCurveCap(
                                        curve_record,
                                        stroke,
                                        scaled_width,
                                    );
                                    const soup_curve_record = try soup.addFlatCurve();
                                    soup.openFlatCurveItems(soup_curve_record);

                                    _ = try soup.addItems(curve_estimate.*);

                                    soup.closeFlatCurveItems(soup_curve_record);
                                }

                                soup.closeFlatSubpathCurves(soup_subpath_record);

                                const stroke_jobs = try soup.addStrokeJobs(curve_record_len);
                                for (stroke_jobs, 0..) |*stroke_job, offset| {
                                    const left_curve_index = soup_subpath_record.flat_curve_offsets.start + @as(u32, @intCast(offset));
                                    const right_curve_index = soup_subpath_record.flat_curve_offsets.end - (1 + @as(u32, @intCast(offset)));
                                    stroke_job.* = StrokeJob{
                                        .transform_index = metadata.transform_index,
                                        .style_index = metadata.style_index,
                                        .source_subpath_index = path_record.subpath_offsets.start + @as(u32, @intCast(subpath_record_offset)),
                                        .source_curve_index = subpath_record.curve_offsets.start + @as(u32, @intCast(offset)),
                                        .left_curve_index = left_curve_index,
                                        .right_curve_index = right_curve_index,
                                    };
                                }
                            } else {
                                // subpath is not capped, so the stroke will be two subpaths
                                const left_soup_subpath_record = try soup.addFlatSubpath();
                                soup.openFlatSubpathCurves(left_soup_subpath_record);
                                const left_soup_subpath_record_start = left_soup_subpath_record.flat_curve_offsets.start;

                                const curve_estimates = try soup.addFlatCurveEstimates(curve_record_len * 2);
                                const left_curve_estimates = curve_estimates[0..curve_record_len];
                                const right_curve_estimates = curve_estimates[curve_record_len..];

                                for (subpath_base_estimates, right_curve_estimates) |base_estimate, *curve_estimate| {
                                    const soup_curve_record = try soup.addFlatCurve();
                                    soup.openFlatCurveItems(soup_curve_record);

                                    curve_estimate.* = @as(u32, @intFromFloat((@as(f32, @floatFromInt(base_estimate)) * offset_fudge))) +
                                        estimateStrokeJoin(stroke.join, scaled_width, stroke.miter_limit);
                                    _ = try soup.addItems(curve_estimate.*);

                                    soup.closeFlatCurveItems(soup_curve_record);
                                }
                                soup.closeFlatSubpathCurves(left_soup_subpath_record);

                                const right_soup_subpath_record = try soup.addFlatSubpath();
                                soup.openFlatSubpathCurves(right_soup_subpath_record);

                                for (left_curve_estimates, 0..) |*curve_estimate, offset| {
                                    const base_estimate = right_curve_estimates[left_curve_estimates.len - (1 + offset)];
                                    curve_estimate.* = base_estimate;
                                    const soup_curve_record = try soup.addFlatCurve();
                                    soup.openFlatCurveItems(soup_curve_record);

                                    _ = try soup.addItems(curve_estimate.*);

                                    soup.closeFlatCurveItems(soup_curve_record);
                                }
                                soup.closeFlatSubpathCurves(right_soup_subpath_record);

                                const stroke_jobs = try soup.addStrokeJobs(curve_record_len);
                                for (stroke_jobs, 0..) |*stroke_job, offset| {
                                    const left_curve_index = left_soup_subpath_record_start + @as(u32, @intCast(offset));
                                    const right_curve_index = right_soup_subpath_record.flat_curve_offsets.end - (1 + @as(u32, @intCast(offset)));
                                    stroke_job.* = StrokeJob{
                                        .transform_index = metadata.transform_index,
                                        .style_index = metadata.style_index,
                                        .source_subpath_index = path_record.subpath_offsets.start + @as(u32, @intCast(subpath_record_offset)),
                                        .source_curve_index = subpath_record.curve_offsets.start + @as(u32, @intCast(offset)),
                                        .left_curve_index = left_curve_index,
                                        .right_curve_index = right_curve_index,
                                    };
                                }
                            }

                            soup.closeFlatPathSubpaths(soup_path_record);
                        }
                    }
                }
            }

            return soup;
        }

        pub fn estimateRaster(soup: *S) !void {
            for (soup.flat_paths.items) |*path_record| {
                var path_intersections: u32 = 0;

                const subpath_records = soup.flat_subpaths.items[path_record.flat_subpath_offsets.start..path_record.flat_subpath_offsets.end];
                for (subpath_records) |*subpath_record| {
                    const curve_records = soup.flat_curves.items[subpath_record.flat_curve_offsets.start..subpath_record.flat_curve_offsets.end];
                    for (curve_records) |*curve_record| {
                        var curve_intersections: u32 = 0;
                        const items = soup.items.items[curve_record.item_offsets.start..curve_record.item_offsets.end];
                        for (items) |item| {
                            curve_intersections += EstimatorImpl.estimateIntersections(item);
                        }

                        soup.openFlatCurveIntersections(curve_record);
                        _ = try soup.addGridIntersections(curve_intersections);
                        soup.closeFlatCurveIntersections(curve_record);

                        path_intersections += curve_intersections;
                    }
                }

                soup.openFlatPathBoundaries(path_record);
                _ = try soup.addBoundaryFragments(path_intersections);
                soup.closeFlatPathBoundaries(path_record);

                soup.openFlatPathMerges(path_record);
                _ = try soup.addMergeFragments(path_intersections);
                soup.closeFlatPathMerges(path_record);

                soup.openFlatPathSpans(path_record);
                _ = try soup.addSpans(path_intersections / 2 + 1);
                soup.closeFlatPathSpans(path_record);
            }
        }

        fn estimateCurveBase(
            paths: Paths,
            curve_record: path_module.Curve,
            transform: TransformF32.Matrix,
        ) u32 {
            var estimate: u32 = 0;

            switch (curve_record.kind) {
                .line => {
                    const points = paths.points.items[curve_record.point_offsets.start..curve_record.point_offsets.end];
                    estimate += @as(u32, @intFromFloat(EstimatorImpl.estimateLineItems(points[0], points[1], transform)));
                },
                .quadratic_bezier => {
                    const points = paths.points.items[curve_record.point_offsets.start..curve_record.point_offsets.end];
                    estimate += @as(u32, @intFromFloat(Wang.quadratic(
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
            curve_record: path_module.Curve,
            stroke: Style.Stroke,
            scaled_width: f32,
        ) u32 {
            switch (curve_record.cap) {
                .start => {
                    return estimateStrokeCap(stroke.start_cap, scaled_width);
                },
                .end => {
                    return estimateStrokeCap(stroke.end_cap, scaled_width);
                },
                .none => {
                    return 0;
                },
            }
        }

        fn estimateStrokeCap(cap: Style.Cap, scaled_width: f32) u32 {
            switch (cap) {
                .butt => {
                    return @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width)));
                },
                .square => {
                    var items = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width)));
                    items += 2 * @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(0.5 * scaled_width)));
                    return items;
                },
                .round => {
                    const arc_estimate: ArcEstimate = EstimatorImpl.estimateArc(scaled_width);
                    return arc_estimate.items;
                },
            }
        }

        fn estimateStrokeJoin(join: Style.Join, scaled_width: f32, miter_limit: f32) u32 {
            const inner_estimate = @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width)));
            var outer_estimate: u32 = 0;

            switch (join) {
                .bevel => {
                    outer_estimate += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(scaled_width)));
                },
                .miter => {
                    const max_miter_len = scaled_width * miter_limit;
                    outer_estimate += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(max_miter_len))) * 2;
                },
                .round => {
                    const arc_estimate: ArcEstimate = EstimatorImpl.estimateArc(scaled_width);
                    outer_estimate += @as(u32, @intFromFloat(EstimatorImpl.estimateLineLengthItems(arc_estimate.length))) * arc_estimate.items;
                },
            }

            return @max(inner_estimate, outer_estimate);
        }
    };
}

pub const LineSoupEstimator = SoupEstimator(Line, LineEstimatorImpl);

pub const LineEstimatorImpl = struct {
    const VIRTUAL_INTERSECTIONS: u32 = 2;
    const INTERSECTION_FUDGE: u32 = 2;

    pub fn estimateLineItems(_: PointF32, _: PointF32, _: TransformF32.Matrix) f32 {
        return 1.0;
    }

    pub fn estimateLineLengthItems(_: f32) f32 {
        return 1.0;
    }

    fn approxArcLengthCubic(p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32) f32 {
        const chord_len = (p3.sub(p0)).length();
        // Length of the control polygon
        const poly_len = (p1.sub(p0)).length() + (p2.sub(p1)).length() + (p3.sub(p2)).length();
        return 0.5 * (chord_len + poly_len);
    }

    fn estimateArc(scaled_width: f32) ArcEstimate {
        const MIN_THETA: f32 = 1e-6;
        const radius = @max(ERROR_TOLERANCE, scaled_width * 0.5);
        const theta = @max(MIN_THETA, (2.0 * std.math.acos(1.0 - ERROR_TOLERANCE / radius)));
        const arc_lines = @max(2, @as(u32, @intFromFloat(@ceil((std.math.pi / 2.0) / theta))));

        return ArcEstimate{
            .items = arc_lines,
            .length = 2.0 * std.math.sin(theta) * radius,
        };
    }

    pub fn estimateIntersections(line: Line) u32 {
        const dxdy = line.end.sub(line.start);
        const intersections: u32 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        return @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;
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
