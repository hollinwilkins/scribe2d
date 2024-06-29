// Source: https://github.com/linebender/vello/blob/eb20ffcd3eff4fe842932e26e6431a7e4fb502d2/vello_shaders/src/cpu/flatten.rs

const std = @import("std");
const core = @import("../core/root.zig");
const shape_module = @import("./shape.zig");
const soup_pen = @import("./soup_pen.zig");
const curve_module = @import("./curve.zig");
const scene_module = @import("./scene.zig");
const euler = @import("./euler.zig");
const soup_module = @import("./soup.zig");
const soup_estimate = @import("./soup_estimate.zig");
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
const Style = soup_pen.Style;
const Line = curve_module.Line;
const CubicPoints = euler.CubicPoints;
const CubicParams = euler.CubicParams;
const EulerParams = euler.EulerParams;
const EulerSegment = euler.EulerSegment;
const LineSoup = soup_module.LineSoup;
const LineSoupEstimator = soup_estimate.LineSoupEstimator;
const Scene = scene_module.Scene;
const LineKernel = kernel_module.LineKernel;
const KernelConfig = kernel_module.KernelConfig;

pub const PathFlattener = struct {
    const PathRecord = struct {
        path_index: u32,
    };

    pub fn flattenSceneAlloc(
        allocator: Allocator,
        config: KernelConfig,
        scene: Scene,
    ) !LineSoup {
        return try flattenAlloc(
            allocator,
            config,
            scene.metadata.items,
            scene.styles.items,
            scene.transforms.items,
            scene.shape,
        );
    }

    pub fn flattenAlloc(
        allocator: Allocator,
        config: KernelConfig,
        metadatas: []const PathMetadata,
        styles: []const Style,
        transforms: []const TransformF32.Matrix,
        shape: Shape,
    ) !LineSoup {
        var soup = try LineSoupEstimator.estimateAlloc(
            allocator,
            config,
            metadatas,
            styles,
            transforms,
            shape,
        );
        errdefer soup.deinit();

        var thread_pool: std.Thread.Pool = undefined;
        try thread_pool.init(std.Thread.Pool.Options{
            .allocator = allocator,
            .n_jobs = config.parallelism,
        });
        defer thread_pool.deinit();

        const fill_range = RangeU32{
            .start = 0,
            .end = @intCast(soup.fill_jobs.items.len),
        };
        var fill_chunks = fill_range.chunkIterator(config.fill_job_chunk_size);

        while (fill_chunks.next()) |chunk| {
            try thread_pool.spawn(
                LineKernel.flattenFill,
                .{
                    config,
                    transforms,
                    shape.curves.items,
                    shape.points.items,
                    soup.fill_jobs.items,
                    chunk,
                    soup.flat_curves.items,
                    soup.items.items,
                },
            );
        }

        const stroke_range = RangeU32{
            .start = 0,
            .end = @intCast(soup.stroke_jobs.items.len),
        };
        var stroke_chunks = stroke_range.chunkIterator(config.stroke_job_chunk_size);

        while (stroke_chunks.next()) |chunk| {
            try thread_pool.spawn(
                LineKernel.flattenStroke,
                .{
                    config,
                    transforms,
                    styles,
                    shape.subpaths.items,
                    shape.curves.items,
                    shape.points.items,
                    soup.stroke_jobs.items,
                    chunk,
                    soup.flat_curves.items,
                    soup.items.items,
                },
            );
        }

        return soup;
    }
};
