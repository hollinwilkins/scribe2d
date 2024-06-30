const std = @import("std");
const core = @import("../core/root.zig");
const shape_module = @import("./shape.zig");
const pen = @import("./pen.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const scene_module = @import("./scene.zig");
const soup_module = @import("./soup.zig");
const flatten_module = @import("./flatten.zig");
const kernel_module = @import("./kernel.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const Path = shape_module.Path;
const PathBuilder = shape_module.PathBuilder;
const PathMetadata = shape_module.PathMetadata;
const Shape = shape_module.Shape;
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
const FlatCurveEstimate = soup_module.FlatCurveEstimate;
const FillJob = soup_module.FillJob;
const StrokeJob = soup_module.StrokeJob;
const KernelConfig = kernel_module.KernelConfig;

pub const ArcEstimate = struct {
    items: u32 = 0,
    length: f32 = 0.0,
};

pub const Estimator = struct {
    const RSQRT_OF_TOL: f64 = 2.2360679775; // tol = 0.2
    const VIRTUAL_INTERSECTIONS: u32 = 2;
    const INTERSECTION_FUDGE: u32 = 2;

    pub fn estimateSceneAlloc(allocator: Allocator, scene: Scene) !Soup {
        return try estimateAlloc(
            allocator,
            scene.metadata.items,
            scene.styles.items,
            scene.transforms.items,
            scene.shape.toShapeData(),
        );
    }

    pub fn estimateAlloc(
        allocator: Allocator,
        config: KernelConfig,
        metadatas: []const PathMetadata,
        styles: []const Style,
        transforms: []const TransformF32.Matrix,
        shape: Shape,
    ) !Soup {
        var soup = Soup.init(allocator);
        errdefer soup.deinit();

        const base_estimates = try soup.addBaseEstimates(shape.curves.items.len);

        for (metadatas) |metadata| {
            if (metadata.path_offsets.size() == 0) {
                continue;
            }

            const transform = transforms[metadata.transform_index];
            const start_path = shape.paths.items[metadata.path_offsets.start];
            const end_path = shape.paths.items[metadata.path_offsets.end - 1];
            const start_subpath = shape.subpaths.items[start_path.subpath_offsets.start];
            const end_subpath = shape.subpaths.items[end_path.subpath_offsets.end - 1];
            const curves = shape.curves.items[start_subpath.curve_offsets.start..end_subpath.curve_offsets.end];
            const curve_estimates = base_estimates[start_subpath.curve_offsets.start..end_subpath.curve_offsets.end];

            for (curves, curve_estimates) |curve, *curve_estimate| {
                curve_estimate.* = estimateCurveBase(shape, curve, transform);
            }
        }

        for (metadatas) |metadata| {
            const style = styles[metadata.style_index];

            const paths = shape.paths.items[metadata.path_offsets.start..metadata.path_offsets.end];
            if (style.fill) |fill| {
                for (paths) |path| {
                    const soup_path = try soup.addFlatPath();
                    soup.openFlatPathSubpaths(soup_path);
                    soup_path.fill = fill;

                    const subpaths = shape.subpaths.items[path.subpath_offsets.start..path.subpath_offsets.end];
                    for (subpaths) |subpath| {
                        const soup_subpath = try soup.addFlatSubpath();
                        soup.openFlatSubpathCurves(soup_subpath);

                        const subpath_base_estimates = soup.base_estimates.items[subpath.curve_offsets.start..subpath.curve_offsets.end];
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
                            const flat_curve = try soup.addFlatCurve();
                            soup.openFlatCurveSegments(flat_curve);
                            soup.openFlatCurveBuffer(flat_curve);

                            _ = try soup.addFlatSegments(fill_curve_estimate.segments());
                            _ = try soup.addBufferBytes(fill_curve_estimate.bytes());

                            soup.closeFlatCurveBuffer(flat_curve);
                            soup.closeFlatCurveSegments(flat_curve);

                            const curve_index = subpath.curve_offsets.start + @as(u32, @intCast(curve_offset));
                            const flat_curve_index = soup_subpath.flat_curve_offsets.start + @as(u32, @intCast(curve_offset));

                            fill_job.* = FillJob{
                                .transform_index = metadata.transform_index,
                                .curve_index = curve_index,
                                .flat_curve_index = flat_curve_index,
                            };
                        }

                        soup.closeFlatSubpathCurves(soup_subpath);
                    }
                    soup.closeFlatPathSubpaths(soup_path);
                }
            }

            if (style.stroke) |stroke| {
                const fill = stroke.toFill();
                const transform = transforms[metadata.transform_index];
                const scaled_width = stroke.width * transform.getScale();
                const offset_fudge: f32 = @max(1.0, std.math.sqrt(scaled_width));

                for (paths) |path| {
                    const subpaths = shape.subpaths.items[path.subpath_offsets.start..path.subpath_offsets.end];
                    for (subpaths, 0..) |subpath, subpath_offset| {
                        const curve_len = subpath.curve_offsets.size();
                        const curves = shape.curves.items[subpath.curve_offsets.start..subpath.curve_offsets.end];
                        const subpath_base_estimates = soup.base_estimates.items[subpath.curve_offsets.start..subpath.curve_offsets.end];

                        const soup_path = try soup.addFlatPath();
                        soup.openFlatPathSubpaths(soup_path);
                        soup_path.fill = fill;

                        if (shape.isSubpathCapped(subpath)) {
                            // subpath is capped, so the stroke will be a single subpath
                            const soup_subpath = try soup.addFlatSubpath();
                            soup.openFlatSubpathCurves(soup_subpath);

                            const curve_estimates = try soup.addFlatCurveEstimates(curve_len * 2);
                            const left_curve_estimates = curve_estimates[0..curve_len];
                            const right_curve_estimates = curve_estimates[curve_len..];

                            // need two curve records per each curve record in source
                            // calculate side without caps
                            for (subpath_base_estimates, right_curve_estimates) |base_estimate, *curve_estimate| {
                                curve_estimate.* = base_estimate.mulScalar(offset_fudge).add(estimateStrokeJoin(stroke.join));

                                const flat_curve = try soup.addFlatCurve();
                                soup.openFlatCurveSegments(flat_curve);
                                soup.openFlatCurveBuffer(flat_curve);

                                _ = try soup.addFlatSegments(curve_estimate.segments());
                                _ = try soup.addBufferBytes(curve_estimate.bytes());

                                soup.closeFlatCurveBuffer(flat_curve);
                                soup.closeFlatCurveSegments(flat_curve);
                            }

                            // calculate side with caps
                            for (left_curve_estimates, 0..) |*curve_estimate, offset| {
                                const curve = curves[curves.len - (1 + offset)];
                                const base_estimate = right_curve_estimates[left_curve_estimates.len - (1 + offset)];
                                curve_estimate.* = base_estimate.add(estimateCurveCap(
                                    config,
                                    curve,
                                    stroke,
                                    scaled_width,
                                ));

                                const flat_curve = try soup.addFlatCurve();
                                soup.openFlatCurveSegments(flat_curve);
                                soup.openFlatCurveBuffer(flat_curve);

                                _ = try soup.addFlatSegments(curve_estimate.segments());
                                _ = try soup.addBufferBytes(curve_estimate.bytes());

                                soup.closeFlatCurveBuffer(flat_curve);
                                soup.closeFlatCurveSegments(flat_curve);
                            }

                            soup.closeFlatSubpathCurves(soup_subpath);

                            const stroke_jobs = try soup.addStrokeJobs(curve_len);
                            for (stroke_jobs, 0..) |*stroke_job, offset| {
                                const left_flat_curve_index = soup_subpath.flat_curve_offsets.start + @as(u32, @intCast(offset));
                                const right_flat_curve_index = soup_subpath.flat_curve_offsets.end - (1 + @as(u32, @intCast(offset)));
                                stroke_job.* = StrokeJob{
                                    .transform_index = metadata.transform_index,
                                    .style_index = metadata.style_index,
                                    .subpath_index = path.subpath_offsets.start + @as(u32, @intCast(subpath_offset)),
                                    .curve_index = subpath.curve_offsets.start + @as(u32, @intCast(offset)),
                                    .left_flat_curve_index = left_flat_curve_index,
                                    .right_flat_curve_index = right_flat_curve_index,
                                };
                            }
                        } else {
                            // subpath is not capped, so the stroke will be two subpaths
                            const left_soup_subpath = try soup.addFlatSubpath();
                            soup.openFlatSubpathCurves(left_soup_subpath);
                            const left_soup_subpath_start = left_soup_subpath.flat_curve_offsets.start;

                            const curve_estimates = try soup.addFlatCurveEstimates(curve_len * 2);
                            const left_curve_estimates = curve_estimates[0..curve_len];
                            const right_curve_estimates = curve_estimates[curve_len..];

                            for (subpath_base_estimates, right_curve_estimates) |base_estimate, *curve_estimate| {
                                curve_estimate.* = @as(u32, @intFromFloat((@as(f32, @floatFromInt(base_estimate)) * offset_fudge))) +
                                    estimateStrokeJoin(config, stroke.join, scaled_width, stroke.miter_limit);

                                const flat_curve = try soup.addFlatCurve();
                                soup.openFlatCurveSegments(flat_curve);
                                soup.openFlatCurveBuffer(flat_curve);

                                _ = try soup.addFlatSegments(curve_estimate.segments());
                                _ = try soup.addBufferBytes(curve_estimate.bytes());

                                soup.closeFlatCurveBuffer(flat_curve);
                                soup.closeFlatCurveSegments(flat_curve);
                            }
                            soup.closeFlatSubpathCurves(left_soup_subpath);

                            const right_soup_subpath = try soup.addFlatSubpath();
                            soup.openFlatSubpathCurves(right_soup_subpath);

                            for (left_curve_estimates, 0..) |*curve_estimate, offset| {
                                const base_estimate = right_curve_estimates[left_curve_estimates.len - (1 + offset)];
                                curve_estimate.* = base_estimate;

                                const flat_curve = try soup.addFlatCurve();
                                soup.openFlatCurveSegments(flat_curve);
                                soup.openFlatCurveBuffer(flat_curve);

                                _ = try soup.addFlatSegments(curve_estimate.segments());
                                _ = try soup.addBufferBytes(curve_estimate.bytes());

                                soup.closeFlatCurveBuffer(flat_curve);
                                soup.closeFlatCurveSegments(flat_curve);
                            }
                            soup.closeFlatSubpathCurves(right_soup_subpath);

                            const stroke_jobs = try soup.addStrokeJobs(curve_len);
                            for (stroke_jobs, 0..) |*stroke_job, offset| {
                                const left_flat_curve_index = left_soup_subpath_start + @as(u32, @intCast(offset));
                                const right_flat_curve_index = right_soup_subpath.flat_curve_offsets.end - (1 + @as(u32, @intCast(offset)));
                                stroke_job.* = StrokeJob{
                                    .transform_index = metadata.transform_index,
                                    .style_index = metadata.style_index,
                                    .subpath_index = path.subpath_offsets.start + @as(u32, @intCast(subpath_offset)),
                                    .curve_index = subpath.curve_offsets.start + @as(u32, @intCast(offset)),
                                    .left_flat_curve_index = left_flat_curve_index,
                                    .right_flat_curve_index = right_flat_curve_index,
                                };
                            }
                        }

                        soup.closeFlatPathSubpaths(soup_path);
                    }
                }
            }
        }

        return soup;
    }

    pub fn estimateRaster(soup: *Soup) !void {
        for (soup.flat_paths.items) |*path| {
            var path_intersections: u32 = 0;

            const subpaths = soup.flat_subpaths.items[path.flat_subpath_offsets.start..path.flat_subpath_offsets.end];
            for (subpaths) |*subpath| {
                const curves = soup.flat_curves.items[subpath.flat_curve_offsets.start..subpath.flat_curve_offsets.end];
                for (curves) |*curve| {
                    var curve_intersections: u32 = 0;

                    const segments = soup.flat_segments.items[curve.segment_offsets.start..curve.segment_offsets.end];
                    for (segments) |segment| {
                        switch (segment.kind) {
                            .line => {
                                const line = soup.getFlatSegmentLine(segment);
                                curve_intersections += estimateLineIntersections(line.start, line.end);
                            },
                            .arc => {
                                const arc = soup.getFlatSegmentArc(segment);
                                curve_intersections += estimateArcIntersections(arc.start, arc.end);
                            },
                            else => unreachable,
                        }
                    }

                    soup.openFlatCurveIntersections(curve);
                    _ = try soup.addGridIntersections(curve_intersections);
                    soup.closeFlatCurveIntersections(curve);

                    path_intersections += curve_intersections;
                }
            }

            soup.openFlatPathBoundaries(path);
            _ = try soup.addBoundaryFragments(path_intersections);
            soup.closeFlatPathBoundaries(path);

            soup.openFlatPathMerges(path);
            _ = try soup.addMergeFragments(path_intersections);
            soup.closeFlatPathMerges(path);

            soup.openFlatPathSpans(path);
            _ = try soup.addSpans(path_intersections / 2 + 1);
            soup.closeFlatPathSpans(path);
        }
    }

    fn estimateCurveBase(
        shape: Shape,
        curve: shape_module.Curve,
        transform: TransformF32.Matrix,
    ) FlatCurveEstimate {
        var estimate: FlatCurveEstimate = FlatCurveEstimate{};

        switch (curve.kind) {
            .line => {
                estimate.lines += 1;
            },
            .quadratic_bezier => {
                const points = shape.points.items[curve.point_offsets.start..curve.point_offsets.end];
                estimate.arcs += @as(u32, @intFromFloat(Wang.quadratic(
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
        config: KernelConfig,
        curve: shape_module.Curve,
        stroke: Style.Stroke,
        scaled_width: f32,
    ) FlatCurveEstimate {
        switch (curve.cap) {
            .start => {
                return estimateStrokeCap(config, stroke.start_cap, scaled_width);
            },
            .end => {
                return estimateStrokeCap(config, stroke.end_cap, scaled_width);
            },
            .none => {
                return FlatCurveEstimate{};
            },
        }
    }

    fn estimateStrokeCap(cap: Style.Cap) FlatCurveEstimate {
        switch (cap) {
            .butt => {
                return FlatCurveEstimate{
                    .lines = 1,
                };
            },
            .square => {
                return FlatCurveEstimate{
                    .lines = 3,
                };
            },
            .round => {
                return FlatCurveEstimate{
                    .arcs = 1,
                };
            },
        }
    }

    fn estimateStrokeJoin(join: Style.Join) FlatCurveEstimate {
        var estimate = FlatCurveEstimate{
            .lines = 1, // for inner join
        };

        switch (join) {
            .bevel => {
                estimate.lines += 1;
            },
            .miter => {
                estimate.lines += 2;
            },
            .round => {
                estimate.arcs += 1;
            },
        }

        return estimate;
    }

    pub fn estimateLineIntersections(p0: PointF32, p1: PointF32) u32 {
        const dxdy = p1.sub(p0);
        const intersections: u32 = @intFromFloat(@ceil(@abs(dxdy.x)) + @ceil(@abs(dxdy.y)));
        return @max(1, intersections) + VIRTUAL_INTERSECTIONS + INTERSECTION_FUDGE;
    }

    pub fn estimateArcIntersections(p0: PointF32, p1: PointF32) u32 {
        const square_point = PointF32{
            .x = p0.x,
            .y = p1.y,
        };
        return estimateLineIntersections(p0, square_point) + estimateLineIntersections(square_point, p1);
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
