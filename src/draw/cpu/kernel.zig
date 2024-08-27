const std = @import("std");
const core = @import("../../core/root.zig");
const encoding_module = @import("../encoding.zig");
const texture_module = @import("../texture.zig");
const euler_module = @import("../euler.zig");
const msaa_module = @import("../msaa.zig");
const Allocator = std.mem.Allocator;
const RangeF32 = core.RangeF32;
const RangeI32 = core.RangeI32;
const RangeU32 = core.RangeU32;
const PointU32 = core.PointU32;
const PathTag = encoding_module.PathTag;
const PathMonoid = encoding_module.PathMonoid;
const SegmentMeta = encoding_module.SegmentMeta;
const Path = encoding_module.Path;
const SegmentData = encoding_module.SegmentData;
const FlatSegment = encoding_module.FlatSegment;
const Style = encoding_module.Style;
const StyleOffset = encoding_module.StyleOffset;
const LineIterator = encoding_module.LineIterator;
const MonoidFunctions = encoding_module.MonoidFunctions;
const AtomicBounds = encoding_module.AtomicBounds;
const Offsets = encoding_module.Offset;
const PathOffset = encoding_module.PathOffset;
const SegmentOffset = encoding_module.SegmentOffset;
const IntersectionOffset = encoding_module.IntersectionOffset;
const GridIntersection = encoding_module.GridIntersection;
const BoundaryFragment = encoding_module.BoundaryFragment;
const MergeFragment = encoding_module.MergeFragment;
const BumpAllocator = encoding_module.BumpAllocator;
const Scanner = encoding_module.Scanner;
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
const TextureUnmanaged = texture_module.TextureUnmanaged;
const ColorF32 = texture_module.ColorF32;
const ColorU8 = texture_module.ColorU8;
const ColorBlend = texture_module.ColorBlend;
const CubicPoints = euler_module.CubicPoints;
const CubicParams = euler_module.CubicParams;
const EulerParams = euler_module.EulerParams;
const EulerSegment = euler_module.EulerSegment;
const HalfPlanesU16 = msaa_module.HalfPlanesU16;

pub const KernelConfig = struct {
    pub const DEFAULT: @This() = init(@This(){});
    pub const SERIAL: @This() = init(@This(){
        .parallelism = 1,
    });

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
    min_stroke_width: f32 = 1.0,

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
            .min_stroke_width = config.min_stroke_width,
        };
    }
};

pub const Config = struct {
    kernel_config: KernelConfig = KernelConfig.DEFAULT,
    debug_flags: DebugFlags = DebugFlags{},
    buffer_sizes: BufferSizes = BufferSizes{},
};

pub const DebugFlags = struct {
    expand_monoids: bool = false,
    calculate_lines: bool = false,
    flatten: bool = false,
    tile: bool = false,
};

pub const BufferSizes = struct {
    pub const DEFAULT_PATHS_SIZE: u32 = 1;
    pub const DEFAULT_LINES_SIZE: u32 = 4096 * 4096;
    pub const DEFAULT_BOUNDARIES_SIZE: u32 = 4096 * 4096;
    pub const DEFAULT_SEGMENTS_SIZE: u32 = 10;
    pub const DEFAULT_SEGMENT_DATA_SIZE: u32 = DEFAULT_SEGMENTS_SIZE * @sizeOf(CubicBezierF32);

    paths_size: u32 = DEFAULT_PATHS_SIZE,
    path_tags_size: u32 = DEFAULT_SEGMENTS_SIZE,
    segment_data_size: u32 = DEFAULT_SEGMENT_DATA_SIZE,
    lines_size: u32 = DEFAULT_LINES_SIZE,
    boundaries_size: u32 = DEFAULT_BOUNDARIES_SIZE,

    pub fn pathsSize(self: @This()) u32 {
        return self.paths_size;
    }

    pub fn stylesSize(self: @This()) u32 {
        return self.paths_size;
    }

    pub fn transformsSize(self: @This()) u32 {
        return self.paths_size;
    }

    pub fn bumpsSize(self: @This()) u32 {
        return self.pathsSize() * 2;
    }

    pub fn pathTagsSize(self: @This()) u32 {
        return self.path_tags_size;
    }

    pub fn segmentDataSize(self: @This()) u32 {
        return self.segment_data_size;
    }

    pub fn offsetsSize(self: @This()) u32 {
        return self.pathTagsSize() * 2;
    }

    pub fn linesSize(self: @This()) u32 {
        return self.lines_size;
    }

    pub fn boundariesSize(self: @This()) u32 {
        return self.boundaries_size;
    }
};

pub const Buffers = struct {
    path_offsets: []u32,
    path_line_offsets: []u32,
    path_boundary_offsets: []u32,
    path_bumps: []u32,
    styles: []Style,
    transforms: []TransformF32.Affine,
    path_tags: []PathTag,
    path_monoids: []PathMonoid,
    segment_data: []u8,
    lines: []LineF32,
    boundary_fragments: []BoundaryFragment,

    pub fn create(allocator: Allocator, sizes: BufferSizes) !@This() {
        return @This(){
            .path_offsets = try allocator.alloc(
                u32,
                sizes.pathsSize(),
            ),
            .path_line_offsets = try allocator.alloc(
                u32,
                sizes.pathsSize() * 2,
            ),
            .path_boundary_offsets = try allocator.alloc(
                u32,
                sizes.pathsSize() * 2,
            ),
            .path_bumps = try allocator.alloc(
                u32,
                sizes.bumpsSize() * 2,
            ),
            .styles = try allocator.alloc(
                Style,
                sizes.stylesSize(),
            ),
            .transforms = try allocator.alloc(
                TransformF32.Affine,
                sizes.transformsSize(),
            ),
            .path_tags = try allocator.alloc(
                PathTag,
                sizes.pathTagsSize(),
            ),
            .path_monoids = try allocator.alloc(
                PathMonoid,
                sizes.pathTagsSize() + 2,
            ),
            .segment_data = try allocator.alloc(
                u8,
                sizes.segmentDataSize(),
            ),
            .lines = try allocator.alloc(
                LineF32,
                sizes.linesSize(),
            ),
            .boundary_fragments = try allocator.alloc(
                BoundaryFragment,
                sizes.boundariesSize(),
            ),
        };
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.path_offsets);
        allocator.free(self.path_line_offsets);
        allocator.free(self.path_boundary_offsets);
        allocator.free(self.path_bumps);
        allocator.free(self.styles);
        allocator.free(self.transforms);
        allocator.free(self.path_tags);
        allocator.free(self.path_monoids);
        allocator.free(self.segment_data);
        allocator.free(self.lines);
        allocator.free(self.boundary_fragments);
    }
};

pub const PipelineState = struct {
    path_indices: RangeU32 = RangeU32{},
    segment_indices: RangeU32 = RangeU32{},
    style_indices: RangeI32 = RangeI32{},
    transform_indices: RangeI32 = RangeI32{},
    segment_data_indices: RangeU32 = RangeU32{},
    run_line_path_indices: RangeU32 = RangeU32{},
    run_boundary_path_indices: RangeU32 = RangeU32{},

    pub fn segmentIndex(self: @This(), segment_index: u32) u32 {
        return segment_index - self.segment_indices.start;
    }

    pub fn styleIndex(self: @This(), style_index: i32) i32 {
        if (self.style_indices.start >= 0) {
            return style_index - self.style_indices.start;
        } else {
            return -1;
        }
    }

    pub fn transformIndex(self: @This(), transform_index: i32) i32 {
        if (self.transform_indices.start >= 0) {
            return transform_index - self.transform_indices.start;
        } else {
            return -1;
        }
    }

    pub fn nextRunLinePathIndices(self: @This()) ?RangeU32 {
        if (self.run_line_path_indices.size() == 0) {
            if (self.run_line_path_indices.start == 0) {
                return null;
            } else {
                @panic("line buffer not large enough");
            }
        }

        return self.run_line_path_indices;
    }
};

pub const PathMonoidExpander = struct {
    pub fn expand(
        config: Config,
        path_tags: []const PathTag,
        // outputs
        pipeline_state: *PipelineState,
        path_monoids: []PathMonoid,
    ) void {
        const segment_size = pipeline_state.segment_indices.size();
        var next_path_monoid = path_monoids[config.buffer_sizes.pathTagsSize()];
        for (path_tags[0..segment_size], path_monoids[0..segment_size]) |path_tag, *path_monoid| {
            next_path_monoid = next_path_monoid.combine(PathMonoid.createTag(path_tag));
            path_monoid.* = next_path_monoid.calculate(path_tag);
        }

        const start_path_monoid = path_monoids[0];
        const end_path_monoid = path_monoids[segment_size - 1];
        const end_path_tag = path_tags[segment_size - 1];
        path_monoids[config.buffer_sizes.pathTagsSize()] = next_path_monoid;
        path_monoids[config.buffer_sizes.pathTagsSize() + 1] = path_monoids[0];

        pipeline_state.style_indices = RangeI32.create(start_path_monoid.style_index, end_path_monoid.style_index + 1);
        pipeline_state.transform_indices = RangeI32.create(start_path_monoid.transform_index, end_path_monoid.transform_index + 1);
        pipeline_state.segment_data_indices = RangeU32.create(
            start_path_monoid.segment_offset,
            end_path_monoid.segment_offset + end_path_tag.segment.size(),
        );
    }
};

pub const LineAllocator = struct {
    pub fn flatten(
        config: Config,
        path_offsets: []const u32,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        styles: []const Style,
        transforms: []const TransformF32.Affine,
        segment_data: []const u8,
        // outputs
        pipeline_state: *PipelineState,
        path_line_offsets: []u32,
    ) void {
        const path_size = pipeline_state.path_indices.size();
        for (0..path_size) |path_index| {
            const start_segment_offset = path_offsets[path_index] - pipeline_state.segment_indices.start;
            const end_segment_offset = if (path_index + 1 < path_size) path_offsets[path_index + 1] - pipeline_state.segment_indices.start else pipeline_state.segment_indices.end - pipeline_state.segment_indices.start;
            const fill_offset = &path_line_offsets[path_index];
            fill_offset.* = 0;
            const stroke_offset = &path_line_offsets[path_size + path_index];
            stroke_offset.* = 0;

            for (start_segment_offset..end_segment_offset) |segment_index| {
                const segment_metadata = getSegmentMeta(
                    @intCast(segment_index),
                    path_tags,
                    path_monoids,
                );
                const style = getStyle(
                    styles,
                    pipeline_state.styleIndex(segment_metadata.path_monoid.style_index),
                );
                const transform = getTransform(
                    transforms,
                    pipeline_state.transformIndex(segment_metadata.path_monoid.transform_index),
                );

                if (style.isFill()) {
                    flattenFill(
                        config,
                        segment_metadata,
                        transform,
                        path_tags,
                        segment_data,
                        fill_offset,
                    );
                }

                if (style.isStroke()) {
                    flattenStroke(
                        config,
                        style.stroke,
                        segment_metadata,
                        transform,
                        path_tags,
                        path_monoids,
                        segment_data,
                        stroke_offset,
                    );
                }
            }
        }

        var sum_offset: u32 = 0;
        for (path_line_offsets[0..path_size]) |*offset| {
            sum_offset += offset.*;
            offset.* = sum_offset;
        }

        sum_offset = 0;
        for (path_line_offsets[path_size .. path_size * 2]) |*offset| {
            sum_offset += offset.*;
            offset.* = sum_offset;
        }

        calculateRunLinePaths(
            config,
            pipeline_state,
            path_line_offsets,
        );
    }

    pub fn flattenFill(
        config: Config,
        segment_metadata: SegmentMeta,
        transform: TransformF32.Affine,
        path_tags: []const PathTag,
        segment_data: []const u8,
        line_offset: *u32,
    ) void {
        if (segment_metadata.path_tag.isArc()) {
            @panic("Arc is not yet supported.");
            // const arc_points = getArcPoints(
            //     config,
            //     path_tag,
            //     path_monoid,
            //     segment_data,
            // ).affineTransform(transform);
            // flattenArcSegment(
            //     config,
            //     arc_points,
            //     0.5 * transform.getScale(),
            //     0.0,
            //     arc_points.p0,
            //     arc_points.p2,
            //     line_writer,
            // );
        } else {
            flatten: {
                var cubic_points: CubicBezierF32 = undefined;
                if (segment_metadata.path_tag.segment.subpath_end) {
                    const previous_path_tag = path_tags[segment_metadata.segment_index - 1];
                    if (previous_path_tag.segment.cap) {
                        // we need to draw the final fill line
                        // TODO: should be LineF32 or LineI16
                        cubic_points = getCubicPointsRaw(
                            .line_f32,
                            segment_metadata.path_monoid.segment_offset - @sizeOf(PointF32),
                            segment_data,
                        );
                    } else {
                        break :flatten;
                    }
                } else {
                    cubic_points = getCubicPoints(
                        segment_metadata,
                        segment_data,
                    );
                }
                cubic_points = cubic_points.affineTransform(transform);

                flattenEuler(
                    config.kernel_config,
                    cubic_points,
                    0.5 * transform.getScale(),
                    0.0,
                    cubic_points.p0,
                    cubic_points.p3,
                    line_offset,
                );
            }
        }
    }

    pub fn flattenStroke(
        config: Config,
        stroke: Style.Stroke,
        segment_metadata: SegmentMeta,
        transform: TransformF32.Affine,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        segment_data: []const u8,
        line_offset: *u32,
    ) void {
        if (segment_metadata.path_tag.isArc()) {
            @panic("Arc is not supported yet.");
            // flattenStrokeArc(
            //     config,
            //     stroke,
            //     segment_index,
            //     path_tags,
            //     path_monoids,
            //     transforms,
            //     subpaths,
            //     segment_data,
            //     front_line_writer,
            //     back_line_writer,
            // );
        } else {
            flatten: {
                if (segment_metadata.path_tag.segment.subpath_end) {
                    break :flatten;
                }

                flattenStrokeEuler(
                    config.kernel_config,
                    stroke,
                    segment_metadata,
                    transform,
                    path_tags,
                    path_monoids,
                    segment_data,
                    line_offset,
                );
            }
        }
    }

    fn flattenEuler(
        config: KernelConfig,
        cubic_points: CubicBezierF32,
        scale: f32,
        offset: f32,
        start_point: PointF32,
        end_point: PointF32,
        line_count: *u32,
    ) void {
        const p0 = cubic_points.p0;
        const p1 = cubic_points.p1;
        const p2 = cubic_points.p2;
        const p3 = cubic_points.p3;

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

                if (@abs(k1) < config.k1_threshold) {
                    const k = k0 + 0.5 * k1;
                    n_frac = std.math.sqrt(@abs(k * (k * dist_scaled + 1.0)));
                } else if (@abs(dist_scaled) < config.distance_threshold) {
                    a = k1;
                    b = k0;
                    int0 = b * std.math.sqrt(@abs(b));
                    const int1 = (a + b) * std.math.sqrt(@abs(a + b));
                    integral = int1 - int0;
                    n_frac = (2.0 / 3.0) * integral / a;
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
                }

                const n = std.math.clamp(@ceil(n_frac * scale_multiplier), 1.0, 100.0);
                line_count.* += @as(u32, @intFromFloat(n));

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

    fn flattenStrokeEuler(
        config: KernelConfig,
        stroke: Style.Stroke,
        segment_metadata: SegmentMeta,
        transform: TransformF32.Affine,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        segment_data: []const u8,
        line_offset: *u32,
    ) void {
        const next_segment_metadata = getSegmentMeta(
            segment_metadata.segment_index + 1,
            path_tags,
            path_monoids,
        );

        if (segment_metadata.path_tag.segment.subpath_end) {
            // marker segment, do nothing
            return;
        }

        const cubic_points = getCubicPoints(
            segment_metadata,
            segment_data,
        ).affineTransform(transform);

        const scale = transform.getScale() / 2.0;
        var stroke_width = stroke.width * scale;
        stroke_width = if (stroke_width < config.min_stroke_width) config.min_stroke_width else stroke_width;

        const offset = 0.5 * stroke_width;
        const offset_point = PointF32{
            .x = offset,
            .y = offset,
        };

        var tan_prev = cubicEndTangent(config, cubic_points.p0, cubic_points.p1, cubic_points.p2, cubic_points.p3);
        var tan_next = readNeighborSegment(
            config,
            next_segment_metadata,
            transform,
            segment_data,
        );
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

        if (segment_metadata.path_tag.segment.cap and !next_segment_metadata.path_tag.segment.subpath_end) {
            // draw start cap on left side
            drawCap(
                config,
                stroke.start_cap,
                cubic_points.p0,
                cubic_points.p0.add(n_start),
                line_offset,
            );
        }

        flattenEuler(
            config,
            cubic_points,
            0.5 * transform.getScale(),
            offset,
            cubic_points.p0.add(n_start),
            cubic_points.p3.add(n_prev),
            line_offset,
        );

        flattenEuler(
            config,
            cubic_points,
            0.5 * transform.getScale(),
            -offset,
            cubic_points.p0.sub(n_start),
            cubic_points.p3.sub(n_prev),
            line_offset,
        );

        if (segment_metadata.path_tag.segment.cap and next_segment_metadata.path_tag.segment.subpath_end) {
            // draw end cap on left side
            drawCap(
                config,
                stroke.end_cap,
                cubic_points.p3,
                cubic_points.p3.sub(n_prev),
                line_offset,
            );
        } else {
            drawJoin(
                config,
                stroke,
                cubic_points.p3,
                tan_prev,
                tan_next,
                n_prev,
                line_offset,
            );
        }
    }

    fn drawCap(
        config: KernelConfig,
        cap_style: Style.Cap,
        point: PointF32,
        cap0: PointF32,
        line_count: *u32,
    ) void {
        switch (cap_style) {
            .round => flattenArc(
                config,
                cap0,
                point,
                std.math.pi,
                line_count,
            ),
            .square => line_count.* += 3,
            .butt => line_count.* += 1,
        }
    }

    fn drawJoin(
        config: KernelConfig,
        stroke: Style.Stroke,
        p0: PointF32,
        tan_prev: PointF32,
        tan_next: PointF32,
        n_prev: PointF32,
        line_count: *u32,
    ) void {
        const front0 = p0.add(n_prev);
        const back1 = p0.sub(n_prev);

        const cr = tan_prev.x * tan_next.y - tan_prev.y * tan_next.x;
        const d = tan_prev.dot(tan_next);

        switch (stroke.join) {
            .bevel => line_count.* += 2,
            .miter => {
                const hypot = std.math.hypot(cr, d);
                const miter_limit = stroke.miter_limit;

                if (2.0 * hypot < (hypot + d) * miter_limit * miter_limit and cr != 0.0) {
                    line_count.* += 1;
                }

                line_count.* += 2;
            },
            .round => {
                if (cr > 0.0) {
                    flattenArc(
                        config,
                        back1,
                        p0,
                        @abs(std.math.atan2(cr, d)),
                        line_count,
                    );
                } else {
                    flattenArc(
                        config,
                        front0,
                        p0,
                        @abs(std.math.atan2(cr, d)),
                        line_count,
                    );
                }

                line_count.* += 1;
            },
        }
    }

    fn flattenArc(
        config: KernelConfig,
        start: PointF32,
        center: PointF32,
        angle: f32,
        line_count: *u32,
    ) void {
        const radius = @max(config.error_tolerance, (start.sub(center)).length());
        const theta = @max(config.min_theta, (2.0 * std.math.acos(1.0 - config.error_tolerance / radius)));

        // Always output at least one line so that we always draw the chord.
        const n_lines: u32 = @max(1, @as(u32, @intFromFloat(@ceil(angle / theta))));

        line_count.* += n_lines;
    }
};

pub const Flatten = struct {
    pub fn flatten(
        config: Config,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        styles: []const Style,
        transforms: []const TransformF32.Affine,
        path_offsets: []const u32,
        path_line_offsets: []const u32,
        segment_data: []const u8,
        // outputs
        pipeline_state: *PipelineState,
        path_bumps: []u32,
        path_boundary_offsets: []u32,
        lines: []LineF32,
    ) void {
        const path_bumps_atomic: []std.atomic.Value(u32) = @as([*]std.atomic.Value(u32), @ptrCast(path_bumps.ptr))[0..path_bumps.len];
        const path_boundary_offsets_atomic: []std.atomic.Value(u32) = @as([*]std.atomic.Value(u32), @ptrCast(path_boundary_offsets.ptr))[0..path_boundary_offsets.len];
        const path_size: u32 = @intCast(pipeline_state.run_line_path_indices.size());
        const projected_path_size: u32 = @intCast(pipeline_state.path_indices.size());
        for (0..path_size) |path_index| {
            const projected_path_index = path_index + pipeline_state.run_line_path_indices.start;
            const start_segment_index = path_offsets[projected_path_index];
            const end_segment_index = if (projected_path_index + 1 < pipeline_state.path_indices.size()) path_offsets[projected_path_index + 1] else pipeline_state.segment_indices.end;
            const segment_size = end_segment_index - start_segment_index;

            const start_fill_offset = if (path_index > 0) path_line_offsets[path_index - 1] else 0;
            const start_stroke_offset = if (path_index > 0) path_line_offsets[path_size + path_index - 1] else path_line_offsets[path_size - 1];

            const end_fill_offset = path_line_offsets[path_index];
            const end_stroke_offset = path_line_offsets[path_size + path_index];

            path_bumps[projected_path_index] = 0;
            path_bumps[projected_path_size + projected_path_index] = 0;
            path_boundary_offsets[projected_path_index] = 0;
            path_boundary_offsets[projected_path_size + projected_path_index] = 0;

            var fill_bump = BumpAllocator{
                .start = start_fill_offset,
                .end = end_fill_offset,
                .offset = &path_bumps_atomic[projected_path_index],
            };
            var stroke_bump = BumpAllocator{
                .start = start_stroke_offset,
                .end = end_stroke_offset,
                .offset = &path_bumps_atomic[projected_path_size + projected_path_index],
            };

            var fill_line_writer = LineWriter{
                .lines = lines,
                .reverse = false,
                .bump = &fill_bump,
                .boundary_offset = &path_boundary_offsets_atomic[projected_path_index],
            };
            var front_stroke_line_writer = LineWriter{
                .lines = lines,
                .reverse = false,
                .bump = &stroke_bump,
                .boundary_offset = &path_boundary_offsets_atomic[projected_path_size + projected_path_index],
            };
            var back_stroke_line_writer = LineWriter{
                .lines = lines,
                .reverse = true,
                .bump = &stroke_bump,
                .boundary_offset = &path_boundary_offsets_atomic[projected_path_size + projected_path_index],
            };

            for (0..segment_size) |segment_index| {
                const segment_metadata = getSegmentMeta(
                    @intCast(segment_index),
                    path_tags,
                    path_monoids,
                );
                const style = getStyle(
                    styles,
                    pipeline_state.styleIndex(segment_metadata.path_monoid.style_index),
                );
                const transform = getTransform(
                    transforms,
                    pipeline_state.transformIndex(segment_metadata.path_monoid.transform_index),
                );

                if (style.isFill()) {
                    flattenFill(
                        config.kernel_config,
                        segment_metadata,
                        path_tags,
                        transform,
                        segment_data,
                        &fill_line_writer,
                    );

                    // var atomic_fill_bounds = AtomicBounds.createRect(&path.bounds);
                    // atomic_fill_bounds.extendBy(line_writer.bounds);
                }

                if (style.isStroke()) {
                    flattenStroke(
                        config.kernel_config,
                        style.stroke,
                        segment_metadata,
                        path_tags,
                        path_monoids,
                        transform,
                        segment_data,
                        &front_stroke_line_writer,
                        &back_stroke_line_writer,
                    );

                    // var atomic_stroke_bounds = AtomicBounds.createRect(&path.bounds);
                    // atomic_stroke_bounds.extendBy(front_line_writer.bounds);
                    // atomic_stroke_bounds.extendBy(back_line_writer.bounds);
                }

                // std.debug.print("Flatten: Path({}), Segment({}), Fill({},{}), Stroke({},{})\n", .{
                //     path_index,
                //     segment_index,
                //     start_fill_offset,
                //     end_fill_offset,
                //     start_stroke_offset,
                //     end_stroke_offset,
                // });
            }
        }

        calculateRunLinePaths(
            config,
            pipeline_state,
            path_line_offsets,
        );

        calculateRunBoundaryPaths(
            config,
            pipeline_state,
            path_boundary_offsets,
        );
    }

    pub fn flattenFill(
        config: KernelConfig,
        segment_metadata: SegmentMeta,
        path_tags: []const PathTag,
        transform: TransformF32.Affine,
        segment_data: []const u8,
        line_writer: *LineWriter,
    ) void {
        flatten: {
            var cubic_points: CubicBezierF32 = undefined;
            if (segment_metadata.path_tag.segment.subpath_end) {
                const previous_path_tag = path_tags[segment_metadata.segment_index - 1];
                if (previous_path_tag.segment.cap) {
                    // we need to draw the final fill line
                    // TODO: should be LineF32 or LineI16
                    cubic_points = getCubicPointsRaw(
                        .line_f32,
                        segment_metadata.path_monoid.segment_offset - @sizeOf(PointF32),
                        segment_data,
                    );
                } else {
                    break :flatten;
                }
            } else {
                cubic_points = getCubicPoints(
                    segment_metadata,
                    segment_data,
                );
            }

            cubic_points = cubic_points.affineTransform(transform);
            flattenEuler(
                config,
                cubic_points,
                0.5 * transform.getScale(),
                0.0,
                cubic_points.p0,
                cubic_points.p3,
                line_writer,
            );
        }
    }

    pub fn flattenStroke(
        config: KernelConfig,
        stroke: Style.Stroke,
        segment_metadata: SegmentMeta,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        transform: TransformF32.Affine,
        segment_data: []const u8,
        front_line_writer: *LineWriter,
        back_line_writer: *LineWriter,
    ) void {
        const path_tag = path_tags[segment_metadata.segment_index];

        if (path_tag.isArc()) {
            @panic("arcs not supported yet");
            // flattenStrokeArc(
            //     config,
            //     stroke,
            //     segment_index,
            //     path_tags,
            //     path_monoids,
            //     transforms,
            //     segment_data,
            //     front_line_writer,
            //     back_line_writer,
            // );
        } else {
            flatten: {
                if (segment_metadata.path_tag.segment.subpath_end) {
                    break :flatten;
                }

                flattenStrokeEuler(
                    config,
                    stroke,
                    segment_metadata,
                    path_tags,
                    path_monoids,
                    transform,
                    segment_data,
                    front_line_writer,
                    back_line_writer,
                );
            }
        }
    }

    // fn flattenStrokeArc(
    //     config: KernelConfig,
    //     stroke: Style.Stroke,
    //     segment_index: u32,
    //     path_tags: []const PathTag,
    //     path_monoids: []const PathMonoid,
    //     transforms: []const TransformF32.Affine,
    //     segment_data: []const u8,
    //     front_line_writer: *LineWriter,
    //     back_line_writer: *LineWriter,
    // ) void {
    //     const path_tag = path_tags[segment_index];
    //     const path_monoid = path_monoids[segment_index];
    //     const transform = getTransform(transforms, path_monoid.transform_index);

    //     const arc_points = getArcPoints(
    //         config,
    //         path_tag,
    //         path_monoid,
    //         segment_data,
    //     ).affineTransform(transform);

    //     const offset = 0.5 * stroke.width;
    //     const offset_point = PointF32{
    //         .x = offset,
    //         .y = offset,
    //     };

    //     const neighbor = readNeighborSegment(
    //         config,
    //         path_monoid.segment_index + 1,
    //         path_tags,
    //         path_monoids,
    //         transforms,
    //         segment_data,
    //     );
    //     var tan_prev = arcTangent(arc_points.p1, arc_points.p2);
    //     var tan_next = neighbor.tangent;
    //     var tan_start = arcTangent(arc_points.p1, arc_points.p0);

    //     if (tan_start.dot(tan_start) < config.tangent_threshold_pow2) {
    //         tan_start = PointF32{
    //             .x = config.tangent_threshold,
    //             .y = 0.0,
    //         };
    //     }

    //     if (tan_prev.dot(tan_prev) < config.tangent_threshold_pow2) {
    //         tan_prev = PointF32{
    //             .x = config.tangent_threshold,
    //             .y = 0.0,
    //         };
    //     }

    //     if (tan_next.dot(tan_next) < config.tangent_threshold_pow2) {
    //         tan_next = PointF32{
    //             .x = config.tangent_threshold,
    //             .y = 0.0,
    //         };
    //     }

    //     const n_start = offset_point.mul((PointF32{
    //         .x = -tan_start.y,
    //         .y = tan_start.x,
    //     }).normalizeUnsafe());
    //     const offset_tangent = offset_point.mul(tan_prev.normalizeUnsafe());
    //     const n_prev = PointF32{
    //         .x = -offset_tangent.y,
    //         .y = offset_tangent.x,
    //     };
    //     const tan_next_norm = tan_next.normalizeUnsafe();
    //     const n_next = offset_point.mul(PointF32{
    //         .x = -tan_next_norm.y,
    //         .y = tan_next_norm.x,
    //     });

    //     if (path_tag.segment.cap and !path_tag.segment.subpath_end) {
    //         // draw start cap on left side
    //         drawCap(
    //             config,
    //             stroke.start_cap,
    //             arc_points.p0,
    //             arc_points.p0.sub(n_start),
    //             arc_points.p0.add(n_start),
    //             offset_tangent.negate(),
    //             front_line_writer,
    //         );
    //     }

    //     flattenArcSegment(
    //         config,
    //         arc_points,
    //         0.5 * transform.getScale(),
    //         offset,
    //         arc_points.p0.add(n_start),
    //         arc_points.p2.add(n_prev),
    //         front_line_writer,
    //     );

    //     flattenArcSegment(
    //         config,
    //         arc_points,
    //         0.5 * transform.getScale(),
    //         -offset,
    //         arc_points.p0.sub(n_start),
    //         arc_points.p2.sub(n_prev),
    //         back_line_writer,
    //     );

    //     if (path_tag.segment.cap and path_tag.segment.subpath_end) {
    //         // draw end cap on left side
    //         drawCap(
    //             config,
    //             stroke.end_cap,
    //             arc_points.p2,
    //             arc_points.p2.add(n_prev),
    //             arc_points.p2.sub(n_prev),
    //             offset_tangent,
    //             front_line_writer,
    //         );
    //     } else {
    //         drawJoin(
    //             config,
    //             stroke,
    //             arc_points.p2,
    //             tan_prev,
    //             tan_next,
    //             n_prev,
    //             n_next,
    //             front_line_writer,
    //             back_line_writer,
    //         );
    //     }
    // }

    fn flattenStrokeEuler(
        config: KernelConfig,
        stroke: Style.Stroke,
        segment_metadata: SegmentMeta,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
        transform: TransformF32.Affine,
        segment_data: []const u8,
        front_line_writer: *LineWriter,
        back_line_writer: *LineWriter,
    ) void {
        const next_segment_metadata = getSegmentMeta(
            segment_metadata.segment_index + 1,
            path_tags,
            path_monoids,
        );

        const cubic_points = getCubicPoints(
            segment_metadata,
            segment_data,
        ).affineTransform(transform);

        const scale = transform.getScale() / 2.0;
        var stroke_width = stroke.width * scale;
        stroke_width = if (stroke_width < config.min_stroke_width) config.min_stroke_width else stroke_width;

        const offset = 0.5 * stroke_width;
        const offset_point = PointF32{
            .x = offset,
            .y = offset,
        };

        var tan_prev = cubicEndTangent(config, cubic_points.p0, cubic_points.p1, cubic_points.p2, cubic_points.p3);
        var tan_next = readNeighborSegment(
            config,
            next_segment_metadata,
            transform,
            segment_data,
        );
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

        if (segment_metadata.path_tag.segment.cap and !next_segment_metadata.path_tag.segment.subpath_end) {
            // draw start cap on left side
            drawCap(
                config,
                stroke.start_cap,
                cubic_points.p0,
                cubic_points.p0.sub(n_start),
                cubic_points.p0.add(n_start),
                offset_tangent.negate(),
                front_line_writer,
            );
        }

        flattenEuler(
            config,
            cubic_points,
            0.5 * transform.getScale(),
            offset,
            cubic_points.p0.add(n_start),
            cubic_points.p3.add(n_prev),
            front_line_writer,
        );

        flattenEuler(
            config,
            cubic_points,
            0.5 * transform.getScale(),
            -offset,
            cubic_points.p0.sub(n_start),
            cubic_points.p3.sub(n_prev),
            back_line_writer,
        );

        if (segment_metadata.path_tag.segment.cap and next_segment_metadata.path_tag.segment.subpath_end) {
            // draw end cap on left side
            drawCap(
                config,
                stroke.end_cap,
                cubic_points.p3,
                cubic_points.p3.add(n_prev),
                cubic_points.p3.sub(n_prev),
                offset_tangent,
                front_line_writer,
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
                front_line_writer,
                back_line_writer,
            );
        }
    }

    fn flattenArcSegment(
        config: KernelConfig,
        arc_points: ArcF32,
        scale: f32,
        offset: f32,
        start_point: PointF32,
        end_point: PointF32,
        line_writer: *LineWriter,
    ) void {
        _ = scale;
        _ = offset;
        const angle1 = arc_points.p0.sub(arc_points.p1).atan2();
        const angle2 = arc_points.p2.sub(arc_points.p1).atan2();
        const angle = @abs(angle1 - angle2);

        flattenArc(
            config,
            start_point,
            end_point,
            arc_points.p1,
            1,
            angle,
            line_writer,
        );
    }

    fn flattenEuler(
        config: KernelConfig,
        cubic_points: CubicBezierF32,
        scale: f32,
        offset: f32,
        start_point: PointF32,
        end_point: PointF32,
        writer: *LineWriter,
    ) void {
        const p0 = cubic_points.p0;
        const p1 = cubic_points.p1;
        const p2 = cubic_points.p2;
        const p3 = cubic_points.p3;

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
                            },
                        }
                        lp1 = es.applyOffset(s, normalized_offset);
                    }

                    // const l0 = if (offset >= 0.0) lp0 else lp1;
                    // const l1 = if (offset >= 0.0) lp1 else lp0;
                    const line = LineF32.create(lp0, lp1);
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
        line_writer: *LineWriter,
    ) void {
        if (cap_style == .round) {
            flattenArc(
                config,
                cap0,
                cap1,
                point,
                -1,
                std.math.pi,
                line_writer,
            );
            return;
        }

        var start = cap0;
        var end = cap1;
        if (cap_style == .square) {
            const v = offset_tangent;
            const p0 = start.add(v);
            const p1 = end.add(v);
            line_writer.write(LineF32.create(start, p0));
            line_writer.write(LineF32.create(p0, p1));

            start = p1;
            end = end;
        }

        line_writer.write(LineF32.create(start, end));
    }

    fn drawJoin(
        config: KernelConfig,
        stroke: Style.Stroke,
        p0: PointF32,
        tan_prev: PointF32,
        tan_next: PointF32,
        n_prev: PointF32,
        n_next: PointF32,
        front_line_writer: *LineWriter,
        back_line_writer: *LineWriter,
    ) void {
        var front0 = p0.add(n_prev);
        const front1 = p0.add(n_next);
        const back0 = p0.sub(n_next);
        var back1 = p0.sub(n_prev);

        const cr = tan_prev.x * tan_next.y - tan_prev.y * tan_next.x;
        const d = tan_prev.dot(tan_next);

        switch (stroke.join) {
            .bevel => {
                front_line_writer.write(LineF32.create(front0, front1));
                back_line_writer.write(LineF32.create(back1, back0));
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
                        back_line_writer.write(LineF32.create(p, miter_pt));
                        back1 = miter_pt;
                    } else {
                        front_line_writer.write(LineF32.create(p, miter_pt));
                        front0 = miter_pt;
                    }
                }

                back_line_writer.write(LineF32.create(back1, back0));
                front_line_writer.write(LineF32.create(front0, front1));
            },
            .round => {
                if (cr > 0.0) {
                    flattenArc(
                        config,
                        back1,
                        back0,
                        p0,
                        1,
                        @abs(std.math.atan2(cr, d)),
                        back_line_writer,
                    );

                    front_line_writer.write(LineF32.create(front0, front1));
                } else {
                    flattenArc(
                        config,
                        front0,
                        front1,
                        p0,
                        -1,
                        @abs(std.math.atan2(cr, d)),
                        front_line_writer,
                    );

                    back_line_writer.write(LineF32.create(back1, back0));
                }
            },
        }
    }

    fn flattenArc(
        config: KernelConfig,
        start: PointF32,
        end: PointF32,
        center: PointF32,
        theta_sign: i2,
        angle: f32,
        line_writer: *LineWriter,
    ) void {
        var p0 = start;
        var r = start.sub(center);
        const radius = @max(config.error_tolerance, (p0.sub(center)).length());
        const theta = @max(config.min_theta, (2.0 * std.math.acos(1.0 - config.error_tolerance / radius)));

        // Always output at least one line so that we always draw the chord.
        const n_lines: u32 = @max(1, @as(u32, @intFromFloat(@ceil(angle / theta))));

        // let (s, c) = theta.sin_cos();
        const i_theta = theta * @as(f32, @floatFromInt(theta_sign));
        const s = std.math.sin(i_theta);
        const c = std.math.cos(i_theta);
        const rot = TransformF32.Matrix{
            .coefficients = [_]f32{
                c, -s, 0.0,
                s, c,  0.0,
            },
        };

        for (0..n_lines - 1) |_| {
            r = rot.apply(r);
            const p1 = center.add(r);
            line_writer.write(LineF32.create(p0, p1));
            p0 = p1;
        }

        const p1 = end;
        line_writer.write(LineF32.create(p0, p1));
    }
};

pub fn calculateRunLinePaths(
    config: Config,
    pipeline_state: *PipelineState,
    path_line_offsets: []const u32,
) void {
    const path_size = pipeline_state.path_indices.size();
    const start_path_offset = 0;
    const start_fill_line_offset = if (start_path_offset > 0) path_line_offsets[start_path_offset - 1] else 0;
    const start_stroke_line_offset = if (start_path_offset > 0) path_line_offsets[path_size + start_path_offset - 1] else path_line_offsets[path_size + start_path_offset];
    var end_path_offset: u32 = start_path_offset;

    var next_path_offset = end_path_offset + 1;
    while (next_path_offset <= path_size) {
        const next_fill_line_offset = path_line_offsets[next_path_offset - 1];
        const next_stroke_line_offset = path_line_offsets[path_size + next_path_offset - 1];
        const lines = (next_fill_line_offset - start_fill_line_offset) + (next_stroke_line_offset - start_stroke_line_offset);

        if (lines > config.buffer_sizes.linesSize()) {
            break;
        }

        end_path_offset = next_path_offset;
        next_path_offset += 1;
    }

    pipeline_state.run_line_path_indices = RangeU32.create(start_path_offset, end_path_offset);
}

pub fn calculateRunBoundaryPaths(
    config: Config,
    pipeline_state: *PipelineState,
    path_boundary_offsets: []const u32,
) void {
    const path_size = pipeline_state.path_indices.size();
    const start_path_offset = 0;
    const start_fill_line_offset = if (start_path_offset > 0) path_boundary_offsets[start_path_offset - 1] else 0;
    const start_stroke_line_offset = if (start_path_offset > 0) path_boundary_offsets[path_size + start_path_offset - 1] else path_boundary_offsets[path_size + start_path_offset];
    var end_path_offset: u32 = start_path_offset;

    var next_path_offset = end_path_offset + 1;
    while (next_path_offset <= path_size) {
        const next_fill_line_offset = path_boundary_offsets[next_path_offset - 1];
        const next_stroke_line_offset = path_boundary_offsets[path_size + next_path_offset - 1];
        const lines = (next_fill_line_offset - start_fill_line_offset) + (next_stroke_line_offset - start_stroke_line_offset);

        if (lines > config.buffer_sizes.boundariesSize()) {
            break;
        }

        end_path_offset = next_path_offset;
        next_path_offset += 1;
    }

    pipeline_state.run_boundary_path_indices = RangeU32.create(start_path_offset, end_path_offset);
}

pub fn getArcPoints(config: KernelConfig, path_tag: PathTag, path_monoid: PathMonoid, segment_data: []const u8) ArcF32 {
    const sd = SegmentData{
        .segment_data = segment_data,
    };

    var arc_points: ArcF32 = undefined;
    switch (path_tag.segment.kind) {
        .arc_f32 => {
            arc_points = sd.getSegment(ArcF32, path_monoid);
        },
        .arc_i16 => {
            arc_points = sd.getSegment(ArcI16, path_monoid).cast(f32);
        },
        else => {
            @panic("Can only get arc points for Arc32 or ArcI16");
        },
    }

    var line1 = LineF32.create(arc_points.p0, arc_points.p1);
    var line2 = LineF32.create(arc_points.p1, arc_points.p2);
    const delta_y1 = line1.p1.y - line1.p0.y;
    const delta_x1 = line1.p1.x - line1.p0.x;
    const delta_y2 = line2.p1.y - line2.p0.y;
    const delta_x2 = line2.p1.x - line2.p0.x;

    if (delta_y1 < config.robust_eps) {
        line1.p0.y = line1.p0.y;
    }

    if (delta_x1 < config.robust_eps) {
        line1.p0.x = line1.p0.x;
    }

    if (delta_y2 < config.robust_eps) {
        line2.p0.y = line2.p0.y;
    }

    if (delta_x2 < config.robust_eps) {
        line2.p0.x = line2.p0.x;
    }

    // calculate normals
    var normal1 = line1.normal();
    var normal2 = line2.normal();

    // calculate midpoints
    const mid1 = line1.midpoint();
    const mid2 = line2.midpoint();

    // position normals at midpoint of line
    normal1 = normal1.add(mid1);
    normal2 = normal2.add(mid2);

    // intersect normal lines
    const normal_line1 = LineF32.create(mid1, normal1);
    const normal_line2 = LineF32.create(mid2, normal2);

    if (normal_line1.pointIntersectLine(normal_line2)) |center| {
        arc_points.p1 = center;
    } else {
        @panic("Invalid arc, straight line");
    }

    return arc_points;
}

pub fn getCubicPoints(segment_metadata: SegmentMeta, segment_data: []const u8) CubicBezierF32 {
    return getCubicPointsRaw(
        segment_metadata.path_tag.segment.kind,
        segment_metadata.path_monoid.segment_offset,
        segment_data,
    );
}

pub fn getCubicPointsRaw(kind: PathTag.Kind, offset: u32, segment_data: []const u8) CubicBezierF32 {
    var cubic_points: CubicBezierF32 = undefined;
    const sd = SegmentData{
        .segment_data = segment_data,
    };

    switch (kind) {
        .line_f32 => {
            const line = sd.getSegmentOffset(LineF32, offset);
            cubic_points.p0 = line.p0;
            cubic_points.p1 = line.p1;
            cubic_points.p3 = cubic_points.p1;
            cubic_points.p2 = cubic_points.p3.lerp(cubic_points.p0, 1.0 / 3.0);
            cubic_points.p1 = cubic_points.p0.lerp(cubic_points.p3, 1.0 / 3.0);
        },
        .line_i16 => {
            const line = sd.getSegmentOffset(LineI16, offset).cast(f32);
            cubic_points.p0 = line.p0;
            cubic_points.p1 = line.p1;
            cubic_points.p3 = cubic_points.p1;
            cubic_points.p2 = cubic_points.p3.lerp(cubic_points.p0, 1.0 / 3.0);
            cubic_points.p1 = cubic_points.p0.lerp(cubic_points.p3, 1.0 / 3.0);
        },
        .quadratic_bezier_f32 => {
            const qb = sd.getSegmentOffset(QuadraticBezierF32, offset);
            cubic_points.p0 = qb.p0;
            cubic_points.p1 = qb.p1;
            cubic_points.p2 = qb.p2;
            cubic_points.p3 = cubic_points.p2;
            cubic_points.p2 = cubic_points.p1.lerp(cubic_points.p2, 1.0 / 3.0);
            cubic_points.p1 = cubic_points.p1.lerp(cubic_points.p0, 1.0 / 3.0);
        },
        .quadratic_bezier_i16 => {
            const qb = sd.getSegmentOffset(QuadraticBezierI16, offset).cast(f32);
            cubic_points.p0 = qb.p0;
            cubic_points.p1 = qb.p1;
            cubic_points.p2 = qb.p2;
            cubic_points.p3 = cubic_points.p2;
            cubic_points.p2 = cubic_points.p1.lerp(cubic_points.p2, 1.0 / 3.0);
            cubic_points.p1 = cubic_points.p1.lerp(cubic_points.p0, 1.0 / 3.0);
        },
        .cubic_bezier_f32 => {
            cubic_points = sd.getSegmentOffset(CubicBezierF32, offset);
        },
        .cubic_bezier_i16 => {
            cubic_points = sd.getSegmentOffset(CubicBezierI16, offset).cast(f32);
        },
        else => @panic("Cannot get cubic points for Arc"),
    }

    return cubic_points;
}

pub const NeighborSegment = struct {
    tangent: PointF32,
};

pub const CubicAndDeriv = struct {
    point: PointF32,
    derivative: PointF32,
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
            a = std.math.asin(x * config.sin_scale) * (1.0 / config.sin_scale);
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

fn readNeighborSegment(
    config: KernelConfig,
    segment_metadata: SegmentMeta,
    transform: TransformF32.Affine,
    segment_data: []const u8,
) PointF32 {
    if (segment_metadata.path_tag.isArc()) {
        @panic("Arc not yet supported.");
    } else {
        const cubic_points = getCubicPoints(
            segment_metadata,
            segment_data,
        ).affineTransform(transform);

        return cubicStartTangent(
            config,
            cubic_points.p0,
            cubic_points.p1,
            cubic_points.p2,
            cubic_points.p3,
        );
    }
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

fn arcTangent(center: PointF32, point: PointF32) PointF32 {
    return LineF32.create(center, point).normal();
}

pub const LineSum = struct {
    count: u32,

    pub fn add(self: *@This()) void {
        self.count += 1;
    }
};

pub const LineWriter = struct {
    lines: []LineF32,
    bump: *BumpAllocator,
    boundary_offset: *std.atomic.Value(u32),
    reverse: bool,
    bounds: RectF32 = RectF32.NONE,

    pub fn write(self: *@This(), line: LineF32) void {
        if (self.reverse) {
            self.lines[self.bump.bump(1)] = LineF32.create(line.p1, line.p0);
        } else {
            self.lines[self.bump.bump(1)] = line;
        }

        self.allocatorBoundaryFragments(line);
        self.bounds.extendByInPlace(line.p0);
        self.bounds.extendByInPlace(line.p1);
    }

    pub fn allocatorBoundaryFragments(
        self: *@This(),
        line: LineF32,
    ) void {
        var intersections: u32 = 0;
        const start_point: PointF32 = line.p0;
        const end_point: PointF32 = line.p1;

        const min_x = start_point.x < end_point.x;
        const min_y = start_point.y < end_point.y;
        const start_x: f32 = if (min_x) @floor(start_point.x) else @ceil(start_point.x);
        const end_x: f32 = if (min_x) @ceil(end_point.x) else @floor(end_point.x);
        const start_y: f32 = if (min_y) @floor(start_point.y) else @ceil(start_point.y);
        const end_y: f32 = if (min_y) @ceil(end_point.y) else @floor(end_point.y);

        intersections += @intFromFloat(@abs(start_x - end_x));
        intersections += @intFromFloat(@abs(start_y - end_y));
        intersections += 2;

        _ = self.boundary_offset.fetchAdd(intersections, .acq_rel);
    }
};

pub const TileGenerator = struct {
    pub fn tile(
        half_planes: *const HalfPlanesU16,
        path_line_offsets: []const u32,
        path_boundary_offsets: []const u32,
        lines: []const LineF32,
        // output
        pipeline_state: *PipelineState,
        path_bumps: []u32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        const path_bumps_atomic: []std.atomic.Value(u32) = @as([*]std.atomic.Value(u32), @ptrCast(path_bumps.ptr))[0..path_bumps.len];
        const path_size: u32 = @intCast(pipeline_state.run_line_path_indices.size());
        const projected_path_size: u32 = @intCast(pipeline_state.path_indices.size());
        for (0..path_size) |path_index| {
            const projected_path_index = path_index + pipeline_state.run_line_path_indices.start;

            const start_fill_line_offset = if (path_index > 0) path_line_offsets[path_index - 1] else 0;
            const start_stroke_line_offset = if (path_index > 0) path_line_offsets[path_size + path_index - 1] else path_line_offsets[path_size - 1];
            const end_fill_line_offset = path_line_offsets[path_index];
            const end_stroke_line_offset = path_line_offsets[path_size + path_index];

            const start_fill_boundary_offset = if (path_index > 0) path_boundary_offsets[path_index - 1] else 0;
            const start_stroke_boundary_offset = if (path_index > 0) path_boundary_offsets[path_size + path_index - 1] else path_boundary_offsets[path_size - 1];
            const end_fill_boundary_offset = path_boundary_offsets[path_index];
            const end_stroke_boundary_offset = path_boundary_offsets[path_size + path_index];

            path_bumps[projected_path_index] = 0;
            path_bumps[projected_path_size + projected_path_index] = 0;
            const fill_bump = BumpAllocator{
                .start = start_fill_boundary_offset,
                .end = end_fill_boundary_offset,
                .offset = &path_bumps_atomic[projected_path_index],
            };
            const stroke_bump = BumpAllocator{
                .start = start_stroke_boundary_offset,
                .end = end_stroke_boundary_offset,
                .offset = &path_bumps_atomic[projected_path_size + projected_path_index],
            };

            for (start_fill_line_offset..end_fill_line_offset) |line_index| {
                tileLine(
                    half_planes,
                    @intCast(line_index),
                    lines,
                    fill_bump,
                    boundary_fragments,
                );
            }

            for (start_stroke_line_offset..end_stroke_line_offset) |line_index| {
                tileLine(
                    half_planes,
                    @intCast(line_index),
                    lines,
                    stroke_bump,
                    boundary_fragments,
                );
            }
        }
    }

    pub fn tileLine(
        half_planes: *const HalfPlanesU16,
        line_index: u32,
        lines: []const LineF32,
        // output
        bump: BumpAllocator,
        boundary_fragments: []BoundaryFragment,
    ) void {
        var line = lines[line_index];
        const min = line.p0.min(line.p1).floor();
        const offset_x = if (min.x < 0) @abs(min.x) else 0.0;
        const offset_y = if (min.y < 0) @abs(min.y) else 0.0;
        const pixel_offset = PointF32.create(offset_x, offset_y);

        var intersection_writer = IntersectionWriter{
            .half_planes = half_planes,
            .bump = bump,
            .pixel_offset = pixel_offset.cast(i32).negate(),
            .boundary_fragments = boundary_fragments,
        };
        line = line.translate(pixel_offset);

        if (std.meta.eql(line.p0, line.p1)) {
            return;
        }
        const start_point: PointF32 = line.p0;
        const end_point: PointF32 = line.p1;
        const bounds_f32: RectF32 = RectF32.create(start_point, end_point);
        const bounds: RectI32 = RectI32.create(PointI32{
            .x = @intFromFloat(@ceil(bounds_f32.min.x)),
            .y = @intFromFloat(@ceil(bounds_f32.min.y)),
        }, PointI32{
            .x = @intFromFloat(@floor(bounds_f32.max.x)),
            .y = @intFromFloat(@floor(bounds_f32.max.y)),
        });
        const scan_bounds = RectF32.create(PointF32{
            .x = @floatFromInt(bounds.min.x - 1),
            .y = @floatFromInt(bounds.min.y - 1),
        }, PointF32{
            .x = @floatFromInt(bounds.max.x + 1),
            .y = @floatFromInt(bounds.max.y + 1),
        });

        const start_intersection = GridIntersection.create(IntersectionF32{
            .t = 0.0,
            .point = start_point,
        });
        const end_intersection = GridIntersection.create(IntersectionF32{
            .t = 1.0,
            .point = end_point,
        });

        const min_x = start_intersection.intersection.point.x < end_intersection.intersection.point.x;
        const min_y = start_intersection.intersection.point.y < end_intersection.intersection.point.y;
        const start_x: f32 = if (min_x) @floor(start_intersection.intersection.point.x) else @ceil(start_intersection.intersection.point.x);
        const end_x: f32 = if (min_x) @ceil(end_intersection.intersection.point.x) else @floor(end_intersection.intersection.point.x);
        const start_y: f32 = if (min_y) @floor(start_intersection.intersection.point.y) else @ceil(start_intersection.intersection.point.y);
        const end_y: f32 = if (min_y) @ceil(end_intersection.intersection.point.y) else @floor(end_intersection.intersection.point.y);
        const inc_x: f32 = if (min_x) 1.0 else -1.0;
        const inc_y: f32 = if (min_y) 1.0 else -1.0;

        var start_x2 = start_x;
        if (start_x == start_intersection.intersection.point.x) {
            start_x2 += inc_x;
        }

        var end_x2 = end_x;
        if (end_x == end_intersection.intersection.point.x) {
            end_x2 -= inc_x;
        }

        var start_y2 = start_y;
        if (start_y == start_intersection.intersection.point.y) {
            start_y2 += inc_y;
        }

        var end_y2 = end_y;
        if (end_y == end_intersection.intersection.point.y) {
            end_y2 -= inc_y;
        }

        var scanner = Scanner{
            .x_range = RangeF32{
                .start = start_x2,
                .end = end_x2,
            },
            .y_range = RangeF32{
                .start = start_y2,
                .end = end_y2,
            },
            .inc_x = inc_x,
            .inc_y = inc_y,
        };

        // std.debug.print("S: ", .{});
        intersection_writer.write(start_intersection);

        var previous_x_intersection = start_intersection;
        var previous_y_intersection = start_intersection;
        while (scanner.nextX()) |x| {
            if (scanX(x, line, scan_bounds)) |x_intersection| {
                var diff_y: bool = undefined;

                if (scanner.inc_y < 0.0 and x_intersection.intersection.point.y > scanner.y_range.start) {
                    diff_y = false;
                } else if (scanner.inc_y > 0.0 and x_intersection.intersection.point.y < scanner.y_range.start) {
                    diff_y = false;
                } else {
                    diff_y = @abs(previous_x_intersection.pixel.y - x_intersection.pixel.y) >= 1;
                }

                var x_flushed: bool = false;
                scan_y: {
                    if (diff_y) {
                        while (scanner.nextY()) |y| {
                            if (scanY(y, line, scan_bounds)) |y_intersection| {
                                if (!x_flushed and y_intersection.intersection.t >= x_intersection.intersection.t) {
                                    // TODO: there is probably a better way to handle this...
                                    // this mallarky is possible because of floating point errors
                                    // std.debug.print("X: ", .{});
                                    intersection_writer.write(x_intersection);
                                    previous_x_intersection = x_intersection;
                                    x_flushed = true;
                                }

                                // std.debug.print("Y: ", .{});
                                intersection_writer.write(y_intersection);
                                previous_y_intersection = y_intersection;
                            }

                            const next_y = scanner.peekNextY();
                            if (min_y and next_y > x_intersection.intersection.point.y) {
                                break :scan_y;
                            } else if (!min_y and next_y < x_intersection.intersection.point.y) {
                                break :scan_y;
                            }
                        }
                    }
                }

                if (!x_flushed) {
                    // std.debug.print("X: ", .{});
                    intersection_writer.write(x_intersection);
                    previous_x_intersection = x_intersection;
                }
            }
        }

        while (scanner.nextY()) |y| {
            if (scanY(y, line, scan_bounds)) |y_intersection| {
                // std.debug.print("Y: ", .{});
                intersection_writer.write(y_intersection);
                previous_y_intersection = y_intersection;
            }
        }

        // std.debug.print("E: ", .{});
        intersection_writer.write(end_intersection);
    }

    fn scanX(
        grid_x: f32,
        line: LineF32,
        scan_bounds: RectF32,
    ) ?GridIntersection {
        const scan_line = LineF32.create(
            PointF32{
                .x = grid_x,
                .y = scan_bounds.min.y,
            },
            PointF32{
                .x = grid_x,
                .y = scan_bounds.max.y,
            },
        );

        if (line.intersectVerticalLine(scan_line)) |intersection| {
            return GridIntersection.create(intersection);
        }

        return null;
    }

    fn scanY(
        grid_y: f32,
        line: LineF32,
        scan_bounds: RectF32,
    ) ?GridIntersection {
        const scan_line = LineF32.create(
            PointF32{
                .x = scan_bounds.min.x,
                .y = grid_y,
            },
            PointF32{
                .x = scan_bounds.max.x,
                .y = grid_y,
            },
        );

        if (line.intersectHorizontalLine(scan_line)) |intersection| {
            return GridIntersection.create(intersection);
        }

        return null;
    }
};

pub const IntersectionWriter = struct {
    const GRID_POINT_TOLERANCE: f32 = 1e-6;

    half_planes: *const HalfPlanesU16,
    bump: BumpAllocator,
    boundary_fragments: []BoundaryFragment,
    pixel_offset: PointI32,
    previous_grid_intersection: ?GridIntersection = null,

    pub fn write(self: *@This(), grid_intersection2: GridIntersection) void {
        // std.debug.print("{}\n", .{grid_intersection.intersection});
        const grid_intersection = grid_intersection2.fitToGrid();

        if (self.previous_grid_intersection) |*previous| {
            if (grid_intersection.intersection.point.approxEqAbs(previous.intersection.point, GRID_POINT_TOLERANCE)) {
                // skip if exactly the same point
                self.previous_grid_intersection = grid_intersection;
                return;
            }

            {
                self.writeBoundaryFragment(BoundaryFragment.create(
                    self.half_planes,
                    self.pixel_offset,
                    [_]*const GridIntersection{
                        previous,
                        &grid_intersection,
                    },
                ));
            }

            self.previous_grid_intersection = grid_intersection;
        } else {
            self.previous_grid_intersection = grid_intersection;
            return;
        }
    }

    pub fn writeBoundaryFragment(self: *@This(), boundary_fragment: BoundaryFragment) void {
        self.boundary_fragments[self.bump.bump(1)] = boundary_fragment;
    }
};

pub const Rasterize = struct {
    const GRID_POINT_TOLERANCE: f32 = 1e-6;

    pub fn boundaryFinish(
        range: RangeU32,
        paths: []Path,
        boundary_fragments: []BoundaryFragment,
    ) void {
        for (range.start..range.end) |path_index| {
            const path = paths[path_index];

            std.mem.sort(
                BoundaryFragment,
                boundary_fragments[path.boundary_offset.start_fill_offset..path.boundary_offset.end_fill_offset],
                @as(u32, 0),
                boundaryFragmentLessThan,
            );

            std.mem.sort(
                BoundaryFragment,
                boundary_fragments[path.boundary_offset.start_stroke_offset..path.boundary_offset.end_stroke_offset],
                @as(u32, 0),
                boundaryFragmentLessThan,
            );
        }
    }

    fn boundaryFragmentLessThan(_: u32, left: BoundaryFragment, right: BoundaryFragment) bool {
        if (left.pixel.y < right.pixel.y) {
            return true;
        } else if (left.pixel.y > right.pixel.y) {
            return false;
        } else if (left.pixel.x < right.pixel.x) {
            return true;
        } else if (left.pixel.x > right.pixel.x) {
            return false;
        }

        return false;
    }

    pub fn merge(
        config: KernelConfig,
        paths: []const Path,
        range: RangeU32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        for (range.start..range.end) |path_index| {
            const path = paths[path_index];

            const fill_merge_range = RangeU32{
                .start = 0,
                .end = path.boundary_offset.end_fill_offset - path.boundary_offset.start_fill_offset,
            };
            const stroke_merge_range = RangeU32{
                .start = 0,
                .end = path.boundary_offset.end_stroke_offset - path.boundary_offset.start_stroke_offset,
            };
            const fill_boundary_fragments = boundary_fragments[path.boundary_offset.start_fill_offset..path.boundary_offset.end_fill_offset];
            const stroke_boundary_fragments = boundary_fragments[path.boundary_offset.start_stroke_offset..path.boundary_offset.end_stroke_offset];

            var chunk_iter = fill_merge_range.chunkIterator(config.chunk_size);
            while (chunk_iter.next()) |chunk| {
                mergePath(
                    chunk,
                    fill_boundary_fragments,
                );
            }

            chunk_iter = stroke_merge_range.chunkIterator(config.chunk_size);
            while (chunk_iter.next()) |chunk| {
                mergePath(
                    chunk,
                    stroke_boundary_fragments,
                );
            }
        }
    }

    pub fn mergePath(
        range: RangeU32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        for (range.start..range.end) |boundary_fragment_index| {
            mergeFragment(
                @intCast(boundary_fragment_index),
                boundary_fragments,
            );
        }
    }

    pub fn mergeFragment(
        boundary_fragment_index: u32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        const merge_fragment = &boundary_fragments[boundary_fragment_index];
        const previous_boundary_fragment = if (boundary_fragment_index > 0) boundary_fragments[boundary_fragment_index - 1] else null;

        if (previous_boundary_fragment) |previous| {
            if (!std.meta.eql(previous.pixel, merge_fragment.pixel)) {
                merge_fragment.is_merge = true;
            }

            if (previous.pixel.y != merge_fragment.pixel.y) {
                merge_fragment.is_scanline = true;
            }
        } else {
            merge_fragment.is_merge = true;
            merge_fragment.is_scanline = true;
        }
    }

    pub fn windMainRay(
        config: KernelConfig,
        paths: []const Path,
        range: RangeU32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        for (range.start..range.end) |path_index| {
            const path = paths[path_index];

            const fill_merge_range = RangeU32{
                .start = 0,
                .end = path.boundary_offset.end_fill_offset - path.boundary_offset.start_fill_offset,
            };
            const stroke_merge_range = RangeU32{
                .start = 0,
                .end = path.boundary_offset.end_stroke_offset - path.boundary_offset.start_stroke_offset,
            };
            const fill_boundary_fragments = boundary_fragments[path.boundary_offset.start_fill_offset..path.boundary_offset.end_fill_offset];
            const stroke_boundary_fragments = boundary_fragments[path.boundary_offset.start_stroke_offset..path.boundary_offset.end_stroke_offset];

            var chunk_iter = fill_merge_range.chunkIterator(config.chunk_size);
            while (chunk_iter.next()) |chunk| {
                windMainRayPath(
                    chunk,
                    fill_boundary_fragments,
                );
            }

            chunk_iter = stroke_merge_range.chunkIterator(config.chunk_size);
            while (chunk_iter.next()) |chunk| {
                windMainRayPath(
                    chunk,
                    stroke_boundary_fragments,
                );
            }
        }
    }

    pub fn windMainRayPath(
        range: RangeU32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        for (range.start..range.end) |boundary_fragment_index| {
            windMainRayFragment(
                @intCast(boundary_fragment_index),
                boundary_fragments,
            );
        }
    }

    pub fn windMainRayFragment(
        boundary_fragment_index: u32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        const merge_fragment = &boundary_fragments[boundary_fragment_index];

        if (!merge_fragment.is_scanline) {
            return;
        }

        // calculate main ray winding
        var main_ray_winding: f32 = merge_fragment.calculateMainRayWinding();
        for (boundary_fragments[boundary_fragment_index + 1 ..]) |*boundary_fragment| {
            if (boundary_fragment.is_scanline) {
                break;
            }

            if (boundary_fragment.is_merge) {
                boundary_fragment.main_ray_winding = main_ray_winding;
            }

            const boundary_framgent_winding = boundary_fragment.calculateMainRayWinding();
            main_ray_winding += boundary_framgent_winding;

            if (!boundary_fragment.is_merge) {
                boundary_fragment.main_ray_winding = boundary_framgent_winding;
            }
        }
    }

    pub fn mask(
        config: KernelConfig,
        path_monoids: []const PathMonoid,
        paths: []const Path,
        styles: []const Style,
        range: RangeU32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        for (range.start..range.end) |path_index| {
            const path = paths[path_index];
            const path_monoid = path_monoids[path.segment_index];
            const style = getStyle(styles, path_monoid.style_index);

            const fill_merge_range = RangeU32{
                .start = 0,
                .end = path.boundary_offset.end_fill_offset - path.boundary_offset.start_fill_offset,
            };
            const stroke_merge_range = RangeU32{
                .start = 0,
                .end = path.boundary_offset.end_stroke_offset - path.boundary_offset.start_stroke_offset,
            };
            const fill_boundary_fragments = boundary_fragments[path.boundary_offset.start_fill_offset..path.boundary_offset.end_fill_offset];
            const stroke_boundary_fragments = boundary_fragments[path.boundary_offset.start_stroke_offset..path.boundary_offset.end_stroke_offset];

            var chunk_iter = fill_merge_range.chunkIterator(config.chunk_size);
            while (chunk_iter.next()) |chunk| {
                maskPath(
                    style.fill.rule,
                    chunk,
                    fill_boundary_fragments,
                );
            }

            chunk_iter = stroke_merge_range.chunkIterator(config.chunk_size);
            while (chunk_iter.next()) |chunk| {
                maskPath(
                    .non_zero,
                    chunk,
                    stroke_boundary_fragments,
                );
            }
        }
    }

    pub fn maskPath(
        fill_rule: Style.FillRule,
        range: RangeU32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        for (range.start..range.end) |boundary_fragment_index| {
            maskFragment(
                fill_rule,
                @intCast(boundary_fragment_index),
                boundary_fragments,
            );
        }
    }

    pub fn maskFragment(
        fill_rule: Style.FillRule,
        boundary_fragment_index: u32,
        boundary_fragments: []BoundaryFragment,
    ) void {
        const merge_fragment = &boundary_fragments[boundary_fragment_index];

        if (!merge_fragment.is_merge) {
            return;
        }

        var end_boundary_offset = boundary_fragment_index + 1;
        for (boundary_fragments[end_boundary_offset..]) |next_boundary_fragment| {
            if (!std.meta.eql(merge_fragment.pixel, next_boundary_fragment.pixel)) {
                break;
            }

            end_boundary_offset += 1;
        }

        const merge_boundary_fragments = boundary_fragments[boundary_fragment_index..end_boundary_offset];

        // calculate stencil mask
        merge_fragment.stencil_mask = switch (fill_rule) {
            .non_zero => BoundaryFragment.maskStencil(.non_zero, merge_boundary_fragments),
            .even_odd => BoundaryFragment.maskStencil(.even_odd, merge_boundary_fragments),
        };
    }
};

pub const Blend = struct {
    pub fn fill(
        stroke: ?Style.Stroke,
        config: KernelConfig,
        transform: TransformF32.Affine,
        brush: Style.Brush,
        brush_offset: u32,
        boundary_fragments: []const BoundaryFragment,
        draw_data: []const u8,
        range: RangeU32,
        texture: *TextureUnmanaged,
    ) void {
        _ = brush; // only color for now
        const color_blend = ColorBlend.Alpha;
        var brush_color = getColor(draw_data, brush_offset);

        if (stroke) |s| {
            const scale = transform.getScale() / 2.0;
            const stroke_width = s.width * scale;

            if (stroke_width < config.min_stroke_width) {
                brush_color.a = brush_color.a * (stroke_width / config.min_stroke_width);
            }
        }

        for (range.start..range.end) |merge_index| {
            const merge_fragment = boundary_fragments[merge_index];

            if (!merge_fragment.is_merge) {
                continue;
            }

            const pixel = merge_fragment.pixel;
            if (pixel.x < 0 or pixel.y < 0 or pixel.x >= texture.dimensions.width or pixel.y >= texture.dimensions.height) {
                continue;
            }

            const intensity = merge_fragment.getIntensity();
            const texture_pixel = PointU32{
                .x = @intCast(pixel.x),
                .y = @intCast(pixel.y),
            };
            const fragment_color = ColorF32{
                .r = brush_color.r,
                .g = brush_color.g,
                .b = brush_color.b,
                .a = brush_color.a * intensity,
            };
            const texture_color = texture.getPixelUnsafe(texture_pixel);
            const blend_color = color_blend.blend(fragment_color, texture_color);
            texture.setPixelUnsafe(texture_pixel, blend_color);
        }
    }

    pub fn fillSpan(
        fill_rule: Style.FillRule,
        stroke: ?Style.Stroke,
        config: KernelConfig,
        transform: TransformF32.Affine,
        brush: Style.Brush,
        brush_offset: u32,
        boundary_fragments: []const BoundaryFragment,
        draw_data: []const u8,
        range: RangeU32,
        texture: *TextureUnmanaged,
    ) void {
        switch (fill_rule) {
            .non_zero => {
                fillSpan2(
                    .non_zero,
                    stroke,
                    config,
                    transform,
                    brush,
                    brush_offset,
                    boundary_fragments,
                    draw_data,
                    range,
                    texture,
                );
            },
            .even_odd => {
                fillSpan2(
                    .even_odd,
                    stroke,
                    config,
                    transform,
                    brush,
                    brush_offset,
                    boundary_fragments,
                    draw_data,
                    range,
                    texture,
                );
            },
        }
    }

    pub fn fillSpan2(
        comptime fill_rule: Style.FillRule,
        stroke: ?Style.Stroke,
        config: KernelConfig,
        transform: TransformF32.Affine,
        brush: Style.Brush,
        brush_offset: u32,
        boundary_fragments: []const BoundaryFragment,
        draw_data: []const u8,
        range: RangeU32,
        texture: *TextureUnmanaged,
    ) void {
        _ = brush;
        const color_blend = ColorBlend.Alpha;
        var brush_color = getColor(draw_data, brush_offset);

        if (stroke) |s| {
            const scale = transform.getScale() / 2.0;
            const stroke_width = s.width * scale;

            if (stroke_width < config.min_stroke_width) {
                brush_color.a = brush_color.a * (stroke_width / config.min_stroke_width);
            }
        }

        for (range.start..range.end) |merge_index| {
            const merge_fragment = boundary_fragments[merge_index];

            if (merge_fragment.is_scanline and merge_fragment.pixel.y >= 0 and merge_fragment.pixel.y < texture.dimensions.height) {
                const y: u32 = @intCast(merge_fragment.pixel.y);

                // var start_span_fragment = merge_fragment;
                var previous_merge_fragment = merge_fragment;
                for (boundary_fragments[merge_index + 1 ..]) |current_merge_fragment| {
                    if (current_merge_fragment.is_scanline) {
                        break;
                    }

                    if (!current_merge_fragment.is_merge) {
                        continue;
                    }

                    flush: {
                        if (std.meta.eql(previous_merge_fragment.pixel, current_merge_fragment.pixel)) {
                            break :flush;
                        }

                        const is_span: bool = switch (fill_rule) {
                            .non_zero => current_merge_fragment.main_ray_winding != 0,
                            .even_odd => @as(u16, @intFromFloat(@abs(current_merge_fragment.main_ray_winding))) & 1 == 1,
                        };

                        if (is_span) {
                            // flush previous to current

                            // TODO: this probably needs adjusting for non_zero fill rule
                            const start_x = previous_merge_fragment.pixel.x + 1;
                            // var start_x = previous_merge_fragment.pixel.x;
                            // switch (fill_rule) {
                            //     .non_zero => start_x += 1,
                            //     .even_odd => {
                            //         if (@as(u16, @intFromFloat(@abs(current_merge_fragment.main_ray_winding))) & 1 == 1) {
                            //             start_x += 1;
                            //         }
                            //     },
                            // }

                            const end_x = current_merge_fragment.pixel.x;
                            const x_range: u32 = @intCast(end_x - start_x);

                            for (0..x_range) |x_offset| {
                                const x: i32 = @intCast(start_x + @as(i32, @intCast(x_offset)));
                                if (x >= 0 and x < texture.dimensions.width) {
                                    const texture_pixel = PointU32{
                                        .x = @intCast(x),
                                        .y = y,
                                    };
                                    const texture_color = texture.getPixelUnsafe(texture_pixel);
                                    const blend_color = color_blend.blend(brush_color, texture_color);
                                    texture.setPixelUnsafe(texture_pixel, blend_color);
                                }
                            }
                        }
                    }

                    previous_merge_fragment = current_merge_fragment;
                }
            }
        }
    }
};

fn getColor(draw_data: []const u8, offset: u32) ColorF32 {
    const color_u8 = std.mem.bytesToValue(ColorU8, draw_data[offset .. offset + @sizeOf(ColorU8)]);
    return ColorF32{
        .r = @as(f32, @floatFromInt(color_u8.r)) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
        .g = @as(f32, @floatFromInt(color_u8.g)) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
        .b = @as(f32, @floatFromInt(color_u8.b)) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
        .a = @as(f32, @floatFromInt(color_u8.a)) / @as(f32, @floatFromInt(std.math.maxInt(u8))),
    };
}

fn getStyle(styles: []const Style, style_index: i32) Style {
    if (styles.len > 0 and style_index >= 0) {
        return styles[@intCast(style_index)];
    }

    return Style{};
}

fn getTransform(transforms: []const TransformF32.Affine, transform_index: i32) TransformF32.Affine {
    if (transforms.len > 0 and transform_index >= 0) {
        return transforms[@intCast(transform_index)];
    }

    return TransformF32.Affine.IDENTITY;
}

fn getSegmentMeta(
    segment_index: u32,
    path_tags: []const PathTag,
    path_monoids: []const PathMonoid,
) SegmentMeta {
    const path_tag = path_tags[segment_index];
    const path_monoid = path_monoids[segment_index];

    return SegmentMeta{
        .segment_index = segment_index,
        .path_tag = path_tag,
        .path_monoid = path_monoid,
    };
}
