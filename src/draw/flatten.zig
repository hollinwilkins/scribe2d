// Source: https://github.com/linebender/vello/blob/eb20ffcd3eff4fe842932e26e6431a7e4fb502d2/vello_shaders/src/cpu/flatten.rs

const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const pen = @import("./pen.zig");
const curve_module = @import("./curve.zig");
const scene_module = @import("./scene.zig");
const euler = @import("./euler.zig");
const soup_module = @import("./soup.zig");
const soup_estimate = @import("./soup_estimate.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;
const PathMetadata = path_module.PathMetadata;
const PathsData = path_module.PathsData;
const Style = pen.Style;
const Line = curve_module.Line;
const CubicPoints = euler.CubicPoints;
const CubicParams = euler.CubicParams;
const EulerParams = euler.EulerParams;
const EulerSegment = euler.EulerSegment;
const LineSoup = soup_module.LineSoup;
const LineSoupEstimator = soup_estimate.LineSoupEstimator;
const Scene = scene_module.Scene;

/// Threshold below which a derivative is considered too small.
pub const DERIV_THRESH: f32 = 1e-6;
pub const DERIV_THRESH_POW2: f32 = std.math.pow(f32, DERIV_THRESH, 2.0);
/// Amount to nudge t when derivative is near-zero.
pub const DERIV_EPS: f32 = 1e-6;
// Limit for subdivision of cubic Béziers.
pub const SUBDIV_LIMIT: f32 = 1.0 / 65536.0;

pub const K1_THRESH: f32 = 1e-3;
pub const DIST_THRESH: f32 = 1e-3;
pub const BREAK1: f32 = 0.8;
pub const BREAK2: f32 = 1.25;
pub const BREAK3: f32 = 2.1;
pub const SIN_SCALE: f32 = 1.0976991822760038;
pub const QUAD_A1: f32 = 0.6406;
pub const QUAD_B1: f32 = -0.81;
pub const QUAD_C1: f32 = 0.9148117935952064;
pub const QUAD_A2: f32 = 0.5;
pub const QUAD_B2: f32 = -0.156;
pub const QUAD_C2: f32 = 0.16145779359520596;
pub const ROBUST_EPSILON: f32 = 2e-7;

pub const EspcRobust = enum(u8) {
    normal = 0,
    low_k1 = 1,
    low_dist = 2,

    pub fn intApproximation(x: f32) f32 {
        const y = @abs(x);
        var a: f32 = undefined;

        if (y < BREAK1) {
            a = std.math.sin(SIN_SCALE * y) * (1.0 / SIN_SCALE);
        } else if (y < BREAK2) {
            a = (std.math.sqrt(8.0) / 3.0) * (y - 1.0) * std.math.sqrt(@abs(y - 1.0)) + (std.math.pi / 4.0);
        } else {
            var qa: f32 = undefined;
            var qb: f32 = undefined;
            var qc: f32 = undefined;

            if (y < BREAK3) {
                qa = QUAD_A1;
                qb = QUAD_B1;
                qc = QUAD_C1;
            } else {
                qa = QUAD_A2;
                qb = QUAD_B2;
                qc = QUAD_C2;
            }

            a = qa * y * y + qb * y + qc;
        }

        return std.math.copysign(a, x);
    }

    pub fn intInvApproximation(x: f32) f32 {
        const y = @abs(x);
        var a: f32 = undefined;

        if (y < 0.7010707591262915) {
            a = std.math.asin(x * SIN_SCALE * (1.0 / SIN_SCALE));
        } else if (y < 0.903249293595206) {
            const b = y - (std.math.pi / 4.0);
            const u = std.math.copysign(std.math.pow(f32, @abs(b), 2.0 / 3.0), b);
            a = u * std.math.cbrt(@as(f32, 9.0 / 8.0)) + 1.0;
        } else {
            var u: f32 = undefined;
            var v: f32 = undefined;
            var w: f32 = undefined;

            if (y < 2.038857793595206) {
                const B: f32 = 0.5 * QUAD_B1 / QUAD_A1;
                u = B * B - QUAD_C1 / QUAD_A1;
                v = 1.0 / QUAD_A1;
                w = B;
            } else {
                const B: f32 = 0.5 * QUAD_B2 / QUAD_A2;
                u = B * B - QUAD_C2 / QUAD_A2;
                v = 1.0 / QUAD_A2;
                w = B;
            }

            a = std.math.sqrt(u + v * y) - w;
        }

        return std.math.copysign(a, x);
    }
};

pub fn cubicStartTangent(p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32) PointF32 {
    const d01 = p1.sub(p0);
    const d02 = p2.sub(p0);
    const d03 = p3.sub(p0);

    if (d01.dot(d01) > ROBUST_EPSILON) {
        return d01;
    } else if (d02.dot(d02) > ROBUST_EPSILON) {
        return d02;
    } else {
        return d03;
    }
}

fn cubicEndTangent(p0: PointF32, p1: PointF32, p2: PointF32, p3: PointF32) PointF32 {
    const d23 = p3.sub(p2);
    const d13 = p3.sub(p1);
    const d03 = p3.sub(p0);
    if (d23.dot(d23) > ROBUST_EPSILON) {
        return d23;
    } else if (d13.dot(d13) > ROBUST_EPSILON) {
        return d13;
    } else {
        return d03;
    }
}

fn readNeighborSegment(paths: PathsData, curve_range: RangeU32, index: u32) NeighborSegment {
    const index_shifted = (index - curve_range.start) % curve_range.end + curve_range.start;
    const curve_record = paths.curve_records[index_shifted];
    const cubic_points = paths.getCubicPoints(curve_record);
    const tangent = cubicStartTangent(
        cubic_points.point0,
        cubic_points.point1,
        cubic_points.point2,
        cubic_points.point3,
    );

    return NeighborSegment{
        .tangent = tangent,
    };
}

pub const NeighborSegment = struct {
    tangent: PointF32,
};

pub const CubicAndDeriv = struct {
    point: PointF32,
    derivative: PointF32,
};

pub const FlatData = struct {
    fill_lines: LineSoup,
    stroke_lines: LineSoup,

    pub fn deinit(self: *@This()) void {
        self.fill_lines.deinit();
        self.stroke_lines.deinit();
    }
};

pub const PathFlattener = struct {
    const PathRecord = struct {
        path_index: u32,
    };

    pub fn flattenSceneAlloc(
        allocator: Allocator,
        scene: Scene,
    ) !LineSoup {
        return try flattenAlloc(
            allocator,
            scene.metadata.items,
            scene.styles.items,
            scene.transforms.items,
            scene.paths.toPathsData(),
        );
    }

    pub fn flattenAlloc(
        allocator: Allocator,
        metadatas: []const PathMetadata,
        styles: []const Style,
        transforms: []const TransformF32.Matrix,
        paths: PathsData,
    ) !LineSoup {
        var soup = try LineSoupEstimator.estimateAlloc(
            allocator,
            metadatas,
            styles,
            transforms,
            paths,
        );
        errdefer soup.deinit();

        for (soup.fill_jobs.items) |fill_job| {
            const source_curve_record = paths.curve_records[fill_job.source_curve_index];
            const cubic_points = paths.getCubicPoints(source_curve_record);
            const metadata = metadatas[fill_job.metadata_index];
            const transform = transforms[metadata.transform_index];
            const curve_record = &soup.curve_records.items[fill_job.curve_index];
            const fill_items = soup.items.items[curve_record.item_offsets.start..curve_record.item_offsets.end];

            const line_count = try flattenEuler(
                cubic_points,
                transform,
                0.0,
                cubic_points.point0,
                cubic_points.point3,
                fill_items,
            );

            curve_record.item_offsets.end = curve_record.item_offsets.start + line_count;
        }

        // var fill_curve_index: usize = 0;
        // var stroke_path_index: usize = 0;
        // var stroke_subpath_index: usize = 0;

        // for (metadatas) |metadata| {
        //     const style = styles[metadata.style_index];
        //     const transform = transforms[metadata.transform_index];

        //     const path_records = paths.path_records[metadata.path_offsets.start..metadata.path_offsets.end];
        //     for (path_records) |path_record| {
        //         if (style.isFilled()) {
        //             const subpath_records = paths.subpath_records[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
        //             for (subpath_records) |subpath_record| {
        //                 const curve_records = paths.curve_records[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
        //                 for (curve_records) |curve_record| {
        //                     const fill_curve_record = encoder.fill.curve_records.items[fill_curve_index];
        //                     fill_curve_index += 1;

        //                     const cubic_points = paths.getCubicPoints(curve_record);
        //                     const fill_items = encoder.fill.items[fill_curve_record.item_offsets.start..fill_curve_record.item_offsets.end];

        //                     try flattenEuler(
        //                         cubic_points,
        //                         transform,
        //                         0.0,
        //                         cubic_points.point0,
        //                         cubic_points.point3,
        //                         fill_items,
        //                     );
        //                 }
        //             }
        //         }
        //     }

        // var fill_path_record: ?*LineSoup.PathRecord = null;
        // if (style.isFilled()) {
        //     fill_path_record = encoding.fill.path_records.items[fill_path_index];
        //     fill_path_index += 1;
        // }

        // var stroke_path_record: ?*LineSoup.PathRecord = null;
        // if (style.isStroked()) {
        //     stroke_path_record = encoding.stroke.path_records.items[stroke_path_index];
        //     stroke_path_index += 1;
        // }

        //             const subpath_records = paths.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
        //             for (subpath_records) |subpath_record| {
        //                 // const items = encoding.fill.items[subpath_record.item_offsets.start..subpath_record.item_offsets.end];
        // //                     const cubic_points = paths.getCubicPoints(curve);
        //                 if (fill_path_record) |fpr| {

        //                     try flattenEuler(
        //                         cubic_points,
        //                         transform,
        //                         0.0,
        //                         cubic_points.point0,
        //                         cubic_points.point3,
        //                         &fill_lines,
        //                     );
        //                 }

        // if (style.isFilled()) {
        //     const fill_subpath_record = encoding.fill.subpath_records.items[fill_subpath_index];
        //     fill_subpath_index += 1;
        // }

        // if (style.stroke) |stroke| {
        //     if (paths.isSubpathCapped(subpath_record)) {
        //         // subpath is capped, so the stroke will be a single subpath
        //         const stroke_subpath_record = encoding.stroke.subpath_records.items[stroke_subpath_index];
        //         stroke_subpath_index += 1;
        //     } else {
        //         // subpath is not capped, so the stroke will be two subpaths
        //         const stroke_subpath_record0 = encoding.stroke.subpath_records.items[stroke_subpath_index];
        //         stroke_subpath_index += 1;
        //         const stroke_subpath_record1 = encoding.stroke.subpath_records.items[stroke_subpath_index];
        //         stroke_subpath_index += 1;
        //     }
        // }
        // }
        // }
        // }

        return soup;
    }

    // pub fn flattenAlloc(
    //     allocator: Allocator,
    //     metadatas: []const PathMetadata,
    //     paths: Paths,
    //     styles: []const Style,
    //     transforms: []const TransformF32.Matrix,
    // ) !FlatData {
    //     var stroke_lines = LineSoup.init(allocator);
    //     var fill_lines = LineSoup.init(allocator);

    //     for (metadatas) |metadata| {
    //         const style = styles[metadata.style_index];
    //         const transform = transforms[metadata.transform_index];

    //         for (paths.path_records.items[metadata.path_offsets.start..metadata.path_offsets.end]) |path| {
    //             if (style.fill) |fill| {
    //                 const path_record = try fill_lines.openPath();
    //                 path_record.fill = fill;
    //             }

    //             if (style.stroke) |stroke| {
    //                 const path_record = try stroke_lines.openPath();
    //                 path_record.fill = stroke.toFill();
    //             }

    //             for (paths.subpath_records.items[path.subpath_offsets.start..path.subpath_offsets.end]) |subpath| {
    //                 if (style.isFilled()) {
    //                     _ = try fill_lines.openSubpath();
    //                 }

    //                 if (style.isStroked()) {
    //                     _ = try stroke_lines.openSubpath();
    //                 }

    //                 for (paths.curve_records.items[subpath.curve_offsets.start..subpath.curve_offsets.end], 0..) |curve, curve_index| {
    //                     const cubic_points = paths.getCubicPoints(curve);

    //                     if (style.isFilled()) {
    //                         try flattenEuler(
    //                             cubic_points,
    //                             transform,
    //                             0.0,
    //                             cubic_points.point0,
    //                             cubic_points.point3,
    //                             &fill_lines,
    //                         );
    //                     }

    //                     if (style.stroke) |stroke| {
    //                         const offset = 0.5 * stroke.width;
    //                         const offset_point = PointF32{
    //                             .x = offset,
    //                             .y = offset,
    //                         };

    //                         if (!curve.is_open) {
    //                             if (curve.cap == .start) {
    //                                 // Draw start cap
    //                                 const tangent = cubicStartTangent(
    //                                     cubic_points.point0,
    //                                     cubic_points.point1,
    //                                     cubic_points.point2,
    //                                     cubic_points.point3,
    //                                 );
    //                                 const offset_tangent = tangent.normalizeUnsafe().mulScalar(offset);
    //                                 const n = PointF32{
    //                                     .x = -offset_tangent.y,
    //                                     .y = offset_tangent.x,
    //                                 };

    //                                 try drawCap(
    //                                     stroke.start_cap,
    //                                     cubic_points.point0,
    //                                     cubic_points.point0.sub(n),
    //                                     cubic_points.point0.add(n),
    //                                     offset_tangent.negate(),
    //                                     transform,
    //                                     &stroke_lines,
    //                                 );
    //                             }

    //                             const neighbor = readNeighborSegment(paths, subpath.curve_offsets, @intCast(curve_index + 1));
    //                             var tan_prev = cubicEndTangent(cubic_points.point0, cubic_points.point1, cubic_points.point2, cubic_points.point3);
    //                             var tan_next = neighbor.tangent;
    //                             var tan_start = cubicStartTangent(cubic_points.point0, cubic_points.point1, cubic_points.point2, cubic_points.point3);

    //                             if (tan_start.dot(tan_start) < euler.TANGENT_THRESH_POW2) {
    //                                 tan_start = PointF32{
    //                                     .x = euler.TANGENT_THRESH,
    //                                     .y = 0.0,
    //                                 };
    //                             }

    //                             if (tan_prev.dot(tan_prev) < euler.TANGENT_THRESH_POW2) {
    //                                 tan_prev = PointF32{
    //                                     .x = euler.TANGENT_THRESH,
    //                                     .y = 0.0,
    //                                 };
    //                             }

    //                             if (tan_next.dot(tan_next) < euler.TANGENT_THRESH_POW2) {
    //                                 tan_next = PointF32{
    //                                     .x = euler.TANGENT_THRESH,
    //                                     .y = 0.0,
    //                                 };
    //                             }

    //                             const n_start = offset_point.mul(PointF32{
    //                                 .x = -tan_start.y,
    //                                 .y = tan_start.x,
    //                             }).normalizeUnsafe();
    //                             const offset_tangent = offset_point.mul(tan_prev.normalizeUnsafe());
    //                             const n_prev = PointF32{
    //                                 .x = -offset_tangent.y,
    //                                 .y = offset_tangent.x,
    //                             };
    //                             const tan_next_norm = tan_next.normalizeUnsafe();
    //                             const n_next = offset_point.mul(PointF32{
    //                                 .x = -tan_next_norm.y,
    //                                 .y = tan_next_norm.x,
    //                             });

    //                             try flattenEuler(
    //                                 cubic_points,
    //                                 transform,
    //                                 offset,
    //                                 cubic_points.point0.add(n_start),
    //                                 cubic_points.point3.add(n_prev),
    //                                 &stroke_lines,
    //                             );
    //                             try flattenEuler(
    //                                 cubic_points,
    //                                 transform,
    //                                 -offset,
    //                                 cubic_points.point0.sub(n_start),
    //                                 cubic_points.point3.sub(n_prev),
    //                                 &stroke_lines,
    //                             );

    //                             if (curve.cap == .end) {
    //                                 // Draw end cap
    //                                 try drawCap(
    //                                     stroke.end_cap,
    //                                     cubic_points.point3,
    //                                     cubic_points.point3.add(n_prev),
    //                                     cubic_points.point3.sub(n_prev),
    //                                     offset_tangent,
    //                                     transform,
    //                                     &stroke_lines,
    //                                 );
    //                             } else {
    //                                 try drawJoin(
    //                                     stroke,
    //                                     cubic_points.point3,
    //                                     tan_prev,
    //                                     tan_next,
    //                                     n_prev,
    //                                     n_next,
    //                                     transform,
    //                                     &stroke_lines,
    //                                 );
    //                             }
    //                         }
    //                     }
    //                 }

    //                 if (style.isFilled()) {
    //                     fill_lines.closeSubpath();
    //                 }

    //                 if (style.isStroked()) {
    //                     stroke_lines.closeSubpath();
    //                 }
    //             }

    //             if (style.isFilled()) {
    //                 fill_lines.closePath();
    //             }

    //             if (style.isStroked()) {
    //                 stroke_lines.closePath();
    //             }
    //         }
    //     }

    //     return FlatData{
    //         .fill_lines = fill_lines,
    //         .stroke_lines = stroke_lines,
    //     };
    // }

    fn drawJoin(
        stroke: Style.Stroke,
        p0: PointF32,
        tan_prev: PointF32,
        tan_next: PointF32,
        n_prev: PointF32,
        n_next: PointF32,
        transform: TransformF32.Matrix,
        line_soup: *LineSoup,
    ) !void {
        var front0 = p0.add(n_prev);
        const front1 = p0.add(n_next);
        var back0 = p0.sub(n_next);
        const back1 = p0.sub(n_prev);

        const cr = tan_prev.x * tan_next.y - tan_prev.y * tan_next.x;
        const d = tan_prev.dot(tan_next);

        switch (stroke.join) {
            .bevel => {
                if (!std.meta.eql(front0, front1) and !std.meta.eql(back0, back1)) {
                    const line1 = try line_soup.addItem();
                    line1.start = transform.apply(front0);
                    line1.end = transform.apply(front1);

                    const line2 = try line_soup.addItem();
                    line2.start = transform.apply(back0);
                    line2.end = transform.apply(back1);
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
                    const miter_pt = fp_this.sub(tan_next).mul(PointF32{
                        .x = h,
                        .y = h,
                    });

                    const line = try line_soup.addItem();
                    line.start = transform.apply(p);
                    line.end = transform.apply(miter_pt);

                    if (is_backside) {
                        back0 = miter_pt;
                    } else {
                        front0 = miter_pt;
                    }
                }

                const line1 = try line_soup.addItem();
                line1.start = transform.apply(front0);
                line1.end = transform.apply(front1);

                const line2 = try line_soup.addItem();
                line2.start = transform.apply(back0);
                line2.end = transform.apply(back1);
            },
            .round => {
                var arc0: PointF32 = undefined;
                var arc1: PointF32 = undefined;
                var other0: PointF32 = undefined;
                var other1: PointF32 = undefined;

                if (cr > 0.0) {
                    arc0 = back0;
                    arc1 = back1;
                    other0 = front0;
                    other1 = front1;
                } else {
                    arc0 = front0;
                    arc1 = front1;
                    other0 = back0;
                    other1 = back1;
                }

                try flattenArc(
                    arc0,
                    arc1,
                    p0,
                    @abs(std.math.atan2(cr, d)),
                    transform,
                    line_soup,
                );

                const line = try line_soup.addItem();
                line.start = transform.apply(other0);
                line.end = transform.apply(other1);
            },
        }
    }

    fn drawCap(
        cap_style: Style.Cap,
        point: PointF32,
        cap0: PointF32,
        cap1: PointF32,
        offset_tangent: PointF32,
        transform: TransformF32.Matrix,
        line_soup: *LineSoup,
    ) !void {
        if (cap_style == .round) {
            try flattenArc(
                cap0,
                cap1,
                point,
                std.math.pi,
                transform,
                line_soup,
            );
            return;
        }

        var start = cap0;
        var end = cap1;
        if (cap_style == .square) {
            const v = offset_tangent;
            const p0 = start.add(v);
            const p1 = end.add(v);
            const line1 = try line_soup.addItem();
            line1.start = transform.apply(start);
            line1.end = transform.apply(p0);

            const line2 = try line_soup.addItem();
            line2.start = transform.apply(p1);
            line2.end = transform.apply(end);

            start = p0;
            end = p1;
        }

        const line = try line_soup.addItem();
        line.start = transform.apply(start);
        line.end = transform.apply(end);
    }

    fn flattenArc(
        start: PointF32,
        end: PointF32,
        center: PointF32,
        angle: f32,
        transform: TransformF32.Matrix,
        line_soup: *LineSoup,
    ) !void {
        const MIN_THETA: f32 = 0.0001;

        var p0 = transform.apply(start);
        var r = start.sub(center);
        const tol: f32 = 0.25;
        const radius = @max(tol, (p0.sub(transform.apply(center))).length());
        const theta = @max(MIN_THETA, (2.0 * std.math.acos(1.0 - tol / radius)));

        // Always output at least one line so that we always draw the chord.
        const n_lines = @max(1, @as(u32, @intFromFloat(@ceil(angle / theta))));

        // let (s, c) = theta.sin_cos();
        const s = std.math.sin(theta);
        const c = std.math.cos(theta);
        const rot = TransformF32.Matrix{
            .coefficients = [_]f32{ c, -s, s, c, 0.0, 0.0 },
        };

        for (0..n_lines - 1) |_| {
            r = rot.apply(r);
            const p1 = transform.apply(center.add(r));
            const line = try line_soup.addItem();
            line.start = p0;
            line.end = p1;
            p0 = p1;
        }

        const p1 = transform.apply(end);
        const line = try line_soup.addItem();
        line.start = p0;
        line.end = p1;
    }

    fn flattenEuler(
        cubic_points: CubicPoints,
        transform: TransformF32.Matrix,
        offset: f32,
        start_point: PointF32,
        end_point: PointF32,
        lines: []Line,
    ) !u32 {
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
            return 0;
        }

        const tol: f32 = 0.25;
        var t0_u: u32 = 0;
        var dt: f32 = 1.0;
        var last_p = p0;
        var last_q = p1.sub(p0);

        // We want to avoid near zero derivatives, so the general technique is to
        // detect, then sample a nearby t value if it fails to meet the threshold.
        if (last_q.lengthSquared() < DERIV_THRESH_POW2) {
            last_q = evaluateCubicAndDeriv(p0, p1, p2, p3, DERIV_EPS).derivative;
        }
        var last_t: f32 = 0.0;
        var lp0 = t_start;

        var line_count: u32 = 0;
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
            if (this_q1.lengthSquared() < DERIV_THRESH_POW2) {
                const cd2 = evaluateCubicAndDeriv(p0, p1, p2, p3, t1 - DERIV_EPS);
                const new_p1 = cd2.point;
                const new_q1 = cd2.derivative;
                this_q1 = new_q1;

                // Change just the derivative at the endpoint, but also move the point so it
                // matches the derivative exactly if in the interior.
                if (t1 < 1.0) {
                    this_p1 = new_p1;
                    t1 -= DERIV_EPS;
                }
            }
            const actual_dt = t1 - last_t;
            const cubic_params = CubicParams.create(this_p0, this_p1, this_q0, this_q1, actual_dt);
            if (cubic_params.err * scale <= tol or dt <= SUBDIV_LIMIT) {
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
                const scale_multiplier = 0.5 * std.math.sqrt1_2 * std.math.sqrt((scale * cubic_params.chord_len / (es.params.ch * tol)));
                var a: f32 = 0.0;
                var b: f32 = 0.0;
                var integral: f32 = 0.0;
                var int0: f32 = 0.0;

                var n_frac: f32 = undefined;
                var robust: EspcRobust = undefined;

                if (@abs(k1) < K1_THRESH) {
                    const k = k0 + 0.5 * k1;
                    n_frac = std.math.sqrt(@abs(k * (k * dist_scaled + 1.0)));
                    robust = .low_k1;
                } else if (@abs(dist_scaled) < DIST_THRESH) {
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
                    int0 = EspcRobust.intApproximation(b);
                    const int1 = EspcRobust.intApproximation(a + b);
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
                                const inv = EspcRobust.intInvApproximation(integral * t + int0);
                                s = (inv - b) / a;
                            },
                        }
                        lp1 = es.applyOffset(s, normalized_offset);
                    }

                    const l0 = if (offset >= 0.0) lp0 else lp1;
                    const l1 = if (offset >= 0.0) lp1 else lp0;
                    lines[line_count] = Line.create(transform.apply(l0), transform.apply(l1));
                    line_count += 1;

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

        return line_count;
    }

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
};
