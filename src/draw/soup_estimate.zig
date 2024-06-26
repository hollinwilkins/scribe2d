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
const SoupEncoding = encoding_module.SoupEncoding;
const SoupEncoder = encoding_module.SoupEncoder;

pub const ArcEstimate = struct {
    items: u32 = 0,
    length: f32 = 0.0,
};

pub fn SoupEstimator(comptime T: type, comptime EstimatorImpl: type) type {
    const S = Soup(T);
    const E = SoupEncoder(T);

    return struct {
        const RSQRT_OF_TOL: f64 = 2.2360679775; // tol = 0.2

        pub fn estimateSceneAlloc(allocator: Allocator, scene: Scene) !E {
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
        ) !E {
            var encoding = E.init(allocator);
            errdefer encoding.deinit();

            const base_estimates = try encoding.addBaseEstimates(paths.curve_records.len);
            var curve_index: usize = 0;
            for (metadatas) |metadata| {
                const transform = transforms[metadata.transform_index];

                const curve_record = paths.curve_records[curve_index];
                base_estimates[curve_index] = estimateCurveBase(paths, curve_record, transform);

                curve_index += 1;
            }

            for (metadatas) |metadata| {
                const style = styles[metadata.style_index];

                if (style.isFilled()) {
                    const path_records = paths.path_records[metadata.path_offsets.start..metadata.path_offsets.end];

                    for (path_records) |path_record| {
                        _ = try encoding.fill.openPath();
                        const subpath_records = paths.subpath_records[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                        for (subpath_records) |subpath_record| {
                            _ = try encoding.fill.openSubpath();

                            const subpath_base_estimates = encoding.base_estimates[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
                            const fill_curve_estimates = try encoding.fill.addCurveEstimates(subpath_base_estimates.len);
                            for (subpath_base_estimates, fill_curve_estimates) |base_estimate, *fill_curve_estimate| {
                                fill_curve_estimate.* = base_estimate;
                                _ = try encoding.fill.openCurve();
                                _ = try encoding.fill.addItems(fill_curve_estimate.items);
                                encoding.fill.closeCurve();
                            }

                            encoding.fill.closeSubpath();
                        }
                        encoding.fill.closePath();
                    }
                }
            }

            for (metadatas) |metadata| {
                const style = styles[metadata.style_index];
                const transform = transforms[metadata.transform_index];

                if (style.stroke) |stroke| {
                    const fill = stroke.toFill();
                    const scaled_width = stroke.width * transform.getScale();
                    const offset_fudge: f32 = @max(1.0, std.math.sqrt(scaled_width));

                    const path_records = paths.path_records[metadata.path_offsets.start..metadata.path_offsets.end];
                    for (path_records) |path_record| {
                        const subpath_records = paths.subpath_records[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                        for (subpath_records) |subpath_record| {
                            const stroke_path_record = try encoding.stroke.openPath();
                            stroke_path_record.fill = fill;

                            if (paths.isSubpathCapped(subpath_record)) {
                                // subpath is capped, so the stroke will be a single subpath
                                _ = try encoding.stroke.openSubpath();

                                const subpath_base_estimates = encoding.base_estimates[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
                                const stroke_curve_estimates = try encoding.stroke.addCurveEstimates(subpath_base_estimates.len);

                                // need two curve records per each curve record in source
                                for (subpath_base_estimates, stroke_curve_estimates) |base_estimate, *stroke_curve_estimate| {
                                    _ = try encoding.stroke.openCurve();
                                    
                                    encoding.stroke.closeCurve();
                                }

                                encoding.stroke.closeSubpath();
                            } else {
                                // subpath is not capped, so the stroke will be two subpaths
                                _ = try encoding.stroke.openSubpath();
                                encoding.stroke.closeSubpath();

                                _ = try encoding.stroke.openSubpath();
                                encoding.stroke.closeSubpath();
                            }

                            encoding.stroke.closePath();
                        }
                    }
                }
            }

            // for (metadatas) |metadata| {
            //     const style = styles[metadata.style_index];
            //     const transform = transforms[metadata.transform_index];

            //     const path_records = paths.path_records[metadata.path_offsets.start..metadata.path_offsets.end];
            //     if (style.isFilled() or style.isStroked()) {

            //         for (path_records) |path_record| {
            //             const subpath_records = paths.subpath_records[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
            //             for (subpath_records) |subpath_record| {
            //                 const curve_records = paths.curve_records[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
            //                 const curve_estimates = try encoding.addBaseEstimates(curve_records.len);
            //                 for (curve_records, curve_estimates) |curve_record, *curve_estimate| {
            //                     curve_estimate.* = estimateCurveBase(paths, curve_record, style, transform);
            //                 }
            //             }
            //         }
            //     }

            //     if (style.isFilled()) {
            //         for (path_records) |path_record| {
            //             const subpath_records = paths.subpath_records[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
            //             for (subpath_records) |subpath_record| {
            //                 const curve_records = paths.curve_records[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
            //                 for (curve_records, curve_estimates) |curve_record, *curve_estimate| {
            //                     curve_estimate.* = estimateCurveBase(paths, curve_record, style, transform);
            //                 }
            //             }
            //         }
            //     }

            // const path_records = paths.path_records[metadata.path_offsets.start..metadata.path_offsets.end];
            // for (path_records) |path_record| {
            //     var fill_path_record: ?*S.PathRecord = null;
            //     if (style.fill) |fill| {
            //         const fpr = try encoding.fill.openPath();
            //         fpr.fill = fill;
            //         fill_path_record = fpr;
            //     }

            //     const subpath_records = paths.subpath_records[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
            //     for (subpath_records) |subpath_record| {
            //         // const scaled_width = stroke.width * transform.getScale();
            //         // const offset_fudge: f32 = @max(1.0, std.math.sqrt(scaled_width));
            //         const curve_records = paths.curve_records[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
            //         const curve_estimates = try encoding.addBaseEstimates(curve_records.len);
            //         for (curve_records, curve_estimates) |curve_record, *curve_estimate| {
            //             curve_estimate.* = estimateCurveBase(paths, curve_record, style, transform);
            //         }

            //         if (style.isFilled()) {
            //             _ = try encoding.fill.openSubpath();

            //             const fill_curve_estimates = try encoding.fill.addCurveEstimates(curve_estimates.len);
            //             for (curve_estimates, fill_curve_estimates) |curve_estimate, *fill_curve_estimate| {
            //                 fill_curve_estimate.* = curve_estimate;
            //                 _ = try encoding.fill.openCurve();
            //                 _ = try encoding.fill.addItems(curve_estimate.items);
            //                 encoding.fill.closeCurve();
            //             }

            //             encoding.fill.closeSubpath();
            //         }

            //         if (style.stroke) |stroke| {
            //             if (paths.isSubpathCapped(subpath_record)) {
            //                 // subpath is capped, so the stroke will be a single subpath
            //             } else {
            //                 // subpath is not capped, so the stroke will be two subpaths
            //             }
            //         }

            //         // if (style.stroke) |stroke| {
            //         //     if (paths.isSubpathCapped(subpath_record)) {
            //         //         // subpath is capped, so the stroke will be a single subpath
            //         //         const stroke_path_record = try encoding.stroke.openPath();
            //         //         stroke_path_record.fill = stroke.toFill();

            //         //         _ = try encoding.stroke.openSubpath();
            //         //         _ = try encoding.stroke.addItems(subpath_estimate.stroke.items * 2);
            //         //         (try encoding.fill.addSubpathEstimate()).* = subpath_estimate;
            //         //         encoding.stroke.closeSubpath();

            //         //         encoding.stroke.closePath();
            //         //     } else {
            //         //         // subpath is not capped, so the stroke will be two subpaths
            //         //         const stroke_path_record = try encoding.stroke.openPath();
            //         //         stroke_path_record.fill = stroke.toFill();

            //         //         _ = try encoding.stroke.openSubpath();
            //         //         _ = try encoding.stroke.addItems(subpath_estimate.stroke.items);
            //         //         (try encoding.fill.addSubpathEstimate()).* = subpath_estimate;
            //         //         encoding.stroke.closeSubpath();

            //         //         _ = try encoding.stroke.openSubpath();
            //         //         _ = try encoding.stroke.addItems(subpath_estimate.stroke.items);
            //         //         (try encoding.fill.addSubpathEstimate()).* = subpath_estimate;
            //         //         encoding.stroke.closeSubpath();

            //         //         encoding.stroke.closePath();
            //         //     }
            //         // }
            //     }

            //     if (style.isFilled()) {
            //         encoding.fill.closePath();
            //     }
            // }
            // }

            return encoding;
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

        fn estimateCurveStroke(
            base_estimate: Estimate,
            stroke: Style.Stroke,
            curve_record: Paths.CurveRecord,
            scaled_width: f32,
            offset_fudge: f32,
        ) Estimate {
            var estimate = Estimate{};
            estimate = base_estimate.mulScalar(offset_fudge);

            switch (curve_record.cap) {
                .start => {
                    estimate = estimate.add(estimateStrokeCaps(stroke.start_cap, scaled_width, 1));
                },
                .end => {
                    estimate = estimate.add(estimateStrokeCaps(stroke.end_cap, scaled_width, 1));
                },
                .none => {
                    // do nothing
                },
            }

            estimate = estimate.add(estimateStrokeJoins(stroke.join, scaled_width, stroke.miter_limit, 1));

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
