const std = @import("std");
const core = @import("../core/root.zig");
const encoding_module = @import("./encoding.zig");
const kernel_module = @import("./kernel.zig");
const texture_module = @import("./texture.zig");
const msaa_module = @import("./msaa.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RangeU32 = core.RangeU32;
const LineF32 = core.LineF32;
const PointU32 = core.PointU32;
const KernelConfig = kernel_module.KernelConfig;
const Style = encoding_module.Style;
const StyleOffset = encoding_module.StyleOffset;
const Encoding = encoding_module.Encoding;
const PathMonoid = encoding_module.PathMonoid;
const Path = encoding_module.Path;
const Subpath = encoding_module.Subpath;
const PathOffset = encoding_module.PathOffset;
const SubpathOffset = encoding_module.SubpathOffset;
const FlatPath = encoding_module.FlatPath;
const FlatSubpath = encoding_module.FlatSubpath;
const FlatSegment = encoding_module.FlatSegment;
const SegmentOffset = encoding_module.SegmentOffset;
const GridIntersection = encoding_module.GridIntersection;
const BoundaryFragment = encoding_module.BoundaryFragment;
const MergeFragment = encoding_module.MergeFragment;
const TextureUnmanaged = texture_module.TextureUnmanaged;
const ColorBlend = texture_module.ColorBlend;
const ColorF32 = texture_module.ColorF32;
const HalfPlanesU16 = msaa_module.HalfPlanesU16;

pub const CpuRasterizer = struct {
    pub const Config = struct {
        pub const RUN_FLAG_EXPAND_MONOIDS: u8 = 0b00000001;
        pub const RUN_FLAG_ESTIMATE_SEGMENTS: u8 = 0b00000010;
        pub const RUN_FLAG_FLATTEN: u8 = 0b00000100;
        pub const RUN_FLAG_INTERSECT: u8 = 0b00001000;
        pub const RUN_FLAG_BOUNDARY: u8 = 0b00010000;
        pub const RUN_FLAG_MERGE: u8 = 0b00100000;
        pub const RUN_FLAG_MASK: u8 = 0b01000000;
        pub const RUN_FLAG_FLUSH_TEXTURE: u8 = 0b10000000;
        pub const RUN_FLAG_ALL = RUN_FLAG_EXPAND_MONOIDS | RUN_FLAG_ESTIMATE_SEGMENTS |
            RUN_FLAG_FLATTEN | RUN_FLAG_INTERSECT | RUN_FLAG_BOUNDARY |
            RUN_FLAG_MERGE | RUN_FLAG_MASK | RUN_FLAG_FLUSH_TEXTURE;

        run_flags: u8 = RUN_FLAG_FLUSH_TEXTURE,
        debug_flags: u8 = RUN_FLAG_ALL,
        kernel_config: KernelConfig = KernelConfig.DEFAULT,

        pub fn runExpandMonoids(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_EXPAND_MONOIDS;
        }

        pub fn debugExpandMonoids(self: @This()) bool {
            return self.runExpandMonoids() and self.debug_flags & RUN_FLAG_EXPAND_MONOIDS > 0;
        }

        pub fn runEstimateSegments(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_ESTIMATE_SEGMENTS;
        }

        pub fn debugEstimateSegments(self: @This()) bool {
            return self.runEstimateSegments() and self.debug_flags & RUN_FLAG_ESTIMATE_SEGMENTS > 0;
        }

        pub fn runFlatten(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_FLATTEN;
        }

        pub fn debugFlatten(self: @This()) bool {
            return self.runFlatten() and self.debug_flags & RUN_FLAG_FLATTEN > 0;
        }

        pub fn runIntersect(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_INTERSECT;
        }

        pub fn debugIntersect(self: @This()) bool {
            return self.runIntersect() and self.debug_flags & RUN_FLAG_INTERSECT > 0;
        }

        pub fn runBoundary(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_BOUNDARY;
        }

        pub fn debugBoundary(self: @This()) bool {
            return self.runBoundary() and self.debug_flags & RUN_FLAG_BOUNDARY > 0;
        }

        pub fn runMerge(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_MERGE;
        }

        pub fn debugMerge(self: @This()) bool {
            return self.runMerge() and self.debug_flags & RUN_FLAG_MERGE > 0;
        }

        pub fn runMask(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_MASK;
        }

        pub fn debugMask(self: @This()) bool {
            return self.runMask() and self.debug_flags & RUN_FLAG_MASK > 0;
        }

        pub fn runFlushTexture(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_FLUSH_TEXTURE;
        }

        pub fn debugFlushTexture(self: @This()) bool {
            return self.runFlushTexture() and self.debug_flags & RUN_FLAG_FLUSH_TEXTURE > 0;
        }
    };

    const PathMonoidList = std.ArrayListUnmanaged(PathMonoid);
    const StyleOffsetList = std.ArrayListUnmanaged(StyleOffset);
    const PathList = std.ArrayListUnmanaged(Path);
    const SubpathList = std.ArrayListUnmanaged(Subpath);
    const FlatSegmentList = std.ArrayListUnmanaged(FlatSegment);
    const SegmentOffsetList = std.ArrayListUnmanaged(SegmentOffset);
    const Buffer = std.ArrayListUnmanaged(u8);
    const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
    const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);

    allocator: Allocator,
    half_planes: *const HalfPlanesU16,
    config: Config,
    encoding: Encoding,
    path_monoids: PathMonoidList = PathMonoidList{},
    style_offsets: StyleOffsetList = StyleOffsetList{},
    paths: PathList = PathList{},
    subpaths: SubpathList = SubpathList{},
    segment_offsets: SegmentOffsetList = SegmentOffsetList{},
    flat_segments: FlatSegmentList = FlatSegmentList{},
    line_data: Buffer = Buffer{},
    grid_intersections: GridIntersectionList = GridIntersectionList{},
    boundary_fragments: BoundaryFragmentList = BoundaryFragmentList{},

    pub fn init(
        allocator: Allocator,
        half_planes: *const HalfPlanesU16,
        config: Config,
        encoding: Encoding,
    ) !@This() {
        return @This(){
            .allocator = allocator,
            .half_planes = half_planes,
            .config = config,
            .encoding = encoding,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.path_monoids.deinit(self.allocator);
        self.style_offsets.deinit(self.allocator);
        self.paths.deinit(self.allocator);
        self.subpaths.deinit(self.allocator);
        self.segment_offsets.deinit(self.allocator);
        self.flat_segments.deinit(self.allocator);
        self.line_data.deinit(self.allocator);
        self.grid_intersections.deinit(self.allocator);
        self.boundary_fragments.deinit(self.allocator);
    }

    pub fn reset(self: *@This()) void {
        self.path_monoids.items.len = 0;
        self.style_offsets.items.len = 0;
        self.paths.items.len = 0;
        self.subpaths.items.len = 0;
        self.segment_offsets.items.len = 0;
        self.flat_segments.items.len = 0;
        self.line_data.items.len = 0;
        self.grid_intersections.items.len = 0;
        self.boundary_fragments.items.len = 0;
    }

    pub fn rasterize(self: *@This(), texture: *TextureUnmanaged) !void {
        var pool: std.Thread.Pool = undefined;
        try pool.init(.{
            .allocator = self.allocator,
            .n_jobs = self.config.kernel_config.parallelism,
        });
        defer pool.deinit();

        // reset the rasterizer
        self.reset();

        if (!self.config.runExpandMonoids()) {
            return;
        }

        // expand path monoids
        try self.expandMonoids();

        if (!self.config.runEstimateSegments()) {
            return;
        }

        // estimate FlatEncoder memory requirements
        try self.estimateSegments(&pool);

        if (!self.config.runFlatten()) {
            return;
        }

        // allocate the FlatEncoder
        // use the FlatEncoder to flatten the encoding
        try self.flatten(&pool);

        // calculate scanline encoding
        try self.kernelRasterize(&pool);

        if (!self.config.runFlushTexture()) {
            return;
        }

        // write scanline encoding to texture
        self.flushTexture(&pool, texture);
    }

    fn expandMonoids(self: *@This()) !void {
        const path_monoids = try self.path_monoids.addManyAsSlice(self.allocator, self.encoding.path_tags.len);
        PathMonoid.expand(self.encoding.path_tags, path_monoids);

        const last_path_monoid = path_monoids[path_monoids.len - 1];
        const paths = try self.paths.addManyAsSlice(self.allocator, last_path_monoid.path_index + 1);
        const subpaths = try self.subpaths.addManyAsSlice(self.allocator, last_path_monoid.subpath_index + 1);
        for (self.encoding.path_tags, path_monoids) |path_tag, path_monoid| {
            if (path_tag.index.path == 1) {
                paths[path_monoid.path_index] = Path{
                    .segment_index = path_monoid.segment_index,
                };
            }

            if (path_tag.index.subpath == 1) {
                subpaths[path_monoid.subpath_index] = Subpath{
                    .segment_index = path_monoid.segment_index,
                };
            }
        }

        const style_offsets = try self.style_offsets.addManyAsSlice(self.allocator, self.encoding.styles.len);
        StyleOffset.expand(self.encoding.styles, style_offsets);
    }

    fn estimateSegments(self: *@This(), pool: *std.Thread.Pool) !void {
        var wg = std.Thread.WaitGroup{};
        const estimator = kernel_module.Estimate;
        const segment_offsets = try self.segment_offsets.addManyAsSlice(self.allocator, self.encoding.path_tags.len);
        const range = RangeU32{
            .start = 0,
            .end = @intCast(self.path_monoids.items.len),
        };
        var chunk_iter = range.chunkIterator(self.config.kernel_config.chunk_size);

        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                estimator.estimateSegments,
                .{
                    self.config.kernel_config,
                    self.encoding.path_tags,
                    self.path_monoids.items,
                    self.encoding.styles,
                    self.encoding.transforms,
                    self.encoding.segment_data,
                    chunk,
                    segment_offsets,
                },
            );
        }

        wg.wait();

        SegmentOffset.expand(segment_offsets, segment_offsets);
    }

    fn flatten(self: *@This(), pool: *std.Thread.Pool) !void {
        var wg = std.Thread.WaitGroup{};
        const flattener = kernel_module.Flatten;
        const last_segment_offset = self.segment_offsets.getLast();
        const flat_segments = try self.flat_segments.addManyAsSlice(
            self.allocator,
            last_segment_offset.sum.flat_segment,
        );
        const line_data = try self.line_data.addManyAsSlice(
            self.allocator,
            last_segment_offset.sum.line_offset,
        );

        const range = RangeU32{
            .start = 0,
            .end = @intCast(self.path_monoids.items.len),
        };
        var chunk_iter = range.chunkIterator(self.config.kernel_config.chunk_size);

        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                flattener.flatten,
                .{
                    self.config.kernel_config,
                    self.encoding.path_tags,
                    self.path_monoids.items,
                    self.encoding.styles,
                    self.encoding.transforms,
                    self.subpaths.items,
                    self.encoding.segment_data,
                    chunk,
                    self.paths.items,
                    self.segment_offsets.items,
                    flat_segments,
                    line_data,
                },
            );
        }

        wg.wait();
    }

    fn kernelRasterize(self: *@This(), pool: *std.Thread.Pool) !void {
        if (!self.config.runIntersect()) {
            return;
        }

        var wg = std.Thread.WaitGroup{};
        const rasterizer = kernel_module.Rasterize;
        const last_segment_offset = self.segment_offsets.getLast();
        const grid_intersections = try self.grid_intersections.addManyAsSlice(self.allocator, last_segment_offset.sum.intersections);
        const boundary_fragments = try self.boundary_fragments.addManyAsSlice(self.allocator, last_segment_offset.sum.intersections);

        const flat_segment_range = RangeU32{
            .start = 0,
            .end = @intCast(self.flat_segments.items.len),
        };

        var chunk_iter = flat_segment_range.chunkIterator(self.config.kernel_config.chunk_size);
        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                rasterizer.intersect,
                .{
                    self.line_data.items,
                    chunk,
                    self.flat_segments.items,
                    grid_intersections,
                },
            );
        }

        wg.wait();
        wg.reset();

        if (!self.config.runBoundary()) {
            return;
        }

        chunk_iter.reset();
        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                rasterizer.boundary,
                .{
                    self.half_planes,
                    self.encoding.path_tags,
                    self.path_monoids.items,
                    self.subpaths.items,
                    self.flat_segments.items,
                    grid_intersections,
                    self.segment_offsets.items,
                    chunk,
                    self.paths.items,
                    boundary_fragments,
                },
            );
        }

        wg.wait();
        wg.reset();

        const path_range = RangeU32{
            .start = 0,
            .end = @intCast(self.paths.items.len),
        };
        chunk_iter = path_range.chunkIterator(self.config.kernel_config.chunk_size);
        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                rasterizer.boundaryFinish,
                .{
                    self.path_monoids.items,
                    self.segment_offsets.items,
                    chunk,
                    self.paths.items,
                    boundary_fragments,
                },
            );
        }

        wg.wait();
        wg.reset();

        if (!self.config.runMerge()) {
            return;
        }

        chunk_iter.reset();
        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                rasterizer.merge,
                .{
                    self.config.kernel_config,
                    self.paths.items,
                    chunk,
                    self.boundary_fragments.items,
                },
            );
        }

        wg.wait();
        wg.reset();

        if (!self.config.runMask()) {
            return;
        }

        chunk_iter.reset();
        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                rasterizer.windMainRay,
                .{
                    self.config.kernel_config,
                    self.paths.items,
                    chunk,
                    self.boundary_fragments.items,
                },
            );
        }

        wg.wait();
        wg.reset();

        chunk_iter.reset();
        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                rasterizer.mask,
                .{
                    self.config.kernel_config,
                    self.paths.items,
                    chunk,
                    self.boundary_fragments.items,
                },
            );
        }

        wg.wait();
    }

    fn flushTexture(self: @This(), pool: *std.Thread.Pool, texture: *TextureUnmanaged) void {
        var wg = std.Thread.WaitGroup{};
        const blender = kernel_module.Blend;

        for (0..self.paths.items.len) |path_index| {
            const path = self.paths.items[path_index];
            const path_monoid = self.path_monoids.items[path.segment_index];
            const style = self.encoding.getStyle(path_monoid.style_index);
            const style_offset = self.getStyleOffset(path_monoid.style_index);

            if (style.isFill()) {
                const fill_range = RangeU32{
                    .start = path.start_fill_boundary_offset,
                    .end = path.end_fill_boundary_offset,
                };

                var chunk_iter = fill_range.chunkIterator(self.config.kernel_config.chunk_size);
                while (chunk_iter.next()) |chunk| {
                    pool.spawnWg(
                        &wg,
                        blender.fill,
                        .{
                            style.fill.brush,
                            style_offset.fill_brush_offset,
                            self.boundary_fragments.items,
                            self.encoding.draw_data,
                            chunk,
                            texture,
                        },
                    );
                }

                wg.wait();
                wg.reset();

                chunk_iter.reset();
                while (chunk_iter.next()) |chunk| {
                    pool.spawnWg(
                        &wg,
                        blender.fillSpan,
                        .{
                            style.fill.brush,
                            style_offset.fill_brush_offset,
                            self.boundary_fragments.items,
                            self.encoding.draw_data,
                            chunk,
                            texture,
                        },
                    );
                }

                wg.wait();
                wg.reset();
            }

            if (style.isStroke()) {
                const stroke_range = RangeU32{
                    .start = path.start_stroke_boundary_offset,
                    .end = path.end_stroke_boundary_offset,
                };

                var chunk_iter = stroke_range.chunkIterator(self.config.kernel_config.chunk_size);
                while (chunk_iter.next()) |chunk| {
                    pool.spawnWg(
                        &wg,
                        blender.fill,
                        .{
                            style.stroke.brush,
                            style_offset.stroke_brush_offset,
                            self.boundary_fragments.items,
                            self.encoding.draw_data,
                            chunk,
                            texture,
                        },
                    );
                }

                wg.wait();
                wg.reset();

                chunk_iter.reset();
                while (chunk_iter.next()) |chunk| {
                    pool.spawnWg(
                        &wg,
                        blender.fillSpan,
                        .{
                            style.stroke.brush,
                            style_offset.stroke_brush_offset,
                            self.boundary_fragments.items,
                            self.encoding.draw_data,
                            chunk,
                            texture,
                        },
                    );
                }

                wg.wait();
                wg.reset();
            }
        }
    }

    pub fn getStyleOffset(self: @This(), style_index: i32) StyleOffset {
        if (self.style_offsets.items.len > 0 and style_index >= 0) {
            return self.style_offsets.items[@intCast(style_index)];
        }

        return StyleOffset{};
    }

    pub fn debugPrint(self: @This(), texture: TextureUnmanaged) void {
        if (self.config.debugExpandMonoids()) {
            std.debug.print("============ Path Monoids ============\n", .{});
            for (self.path_monoids.items) |path_monoid| {
                std.debug.print("{}\n", .{path_monoid});
            }
            std.debug.print("======================================\n", .{});
        }

        if (self.config.debugEstimateSegments()) {
            std.debug.print("============ Path Segments ============\n", .{});
            for (self.subpaths.items) |subpath| {
                const subpath_path_monoid = self.path_monoids.items[subpath.segment_index];
                var end_segment_offset: u32 = undefined;
                if (subpath_path_monoid.subpath_index + 1 < self.subpaths.items.len) {
                    end_segment_offset = self.subpaths.items[subpath_path_monoid.subpath_index + 1].segment_index;
                } else {
                    end_segment_offset = @intCast(self.encoding.path_tags.len);
                }

                std.debug.print("Subpath({},{})\n", .{ subpath_path_monoid.path_index, subpath_path_monoid.subpath_index });
                const subpath_path_tags = self.encoding.path_tags[subpath.segment_index..end_segment_offset];
                const subpath_path_monoids = self.path_monoids.items[subpath.segment_index..end_segment_offset];
                for (subpath_path_tags, subpath_path_monoids) |path_tag, path_monoid| {
                    switch (path_tag.segment.kind) {
                        .line_f32 => std.debug.print("LineF32: {}\n", .{
                            self.encoding.getSegment(core.LineF32, path_monoid),
                        }),
                        .arc_f32 => std.debug.print("ArcF32: {}\n", .{
                            self.encoding.getSegment(core.ArcF32, path_monoid),
                        }),
                        .quadratic_bezier_f32 => std.debug.print("QuadraticBezierF32: {}\n", .{
                            self.encoding.getSegment(core.QuadraticBezierF32, path_monoid),
                        }),
                        .cubic_bezier_f32 => std.debug.print("CubicBezierF32: {}\n", .{
                            self.encoding.getSegment(core.CubicBezierF32, path_monoid),
                        }),
                        .line_i16 => std.debug.print("LineI16: {}\n", .{
                            self.encoding.getSegment(core.LineI16, path_monoid),
                        }),
                        .arc_i16 => std.debug.print("ArcI16: {}\n", .{
                            self.encoding.getSegment(core.ArcI16, path_monoid),
                        }),
                        .quadratic_bezier_i16 => std.debug.print("QuadraticBezierI16: {}\n", .{
                            self.encoding.getSegment(core.QuadraticBezierI16, path_monoid),
                        }),
                        .cubic_bezier_i16 => std.debug.print("CubicBezierI16: {}\n", .{
                            self.encoding.getSegment(core.CubicBezierI16, path_monoid),
                        }),
                    }
                }
                std.debug.print("--------------------------------------\n", .{});
            }
            std.debug.print("======================================\n", .{});
        }

        if (self.config.debugFlatten()) {
            std.debug.print("================= Paths ==================\n", .{});
            for (self.paths.items) |path| {
                const path_monoid = self.path_monoids.items[path.segment_index];
                std.debug.print("Path({})\n", .{path_monoid.path_index});
                std.debug.print("Fill Bounds: {}\n", .{path.fill_bounds});
                std.debug.print("Stroke Bounds: {}\n", .{path.stroke_bounds});
                std.debug.print("---------------------\n", .{});
            }
            std.debug.print("==========================================\n", .{});

            if (self.config.runFlatten()) {
                std.debug.print("============ Flat Fill Lines ============\n", .{});
                for (self.subpaths.items) |subpath| {
                    const path_monoid = self.path_monoids.items[subpath.segment_index];
                    const subpath_offset = SubpathOffset.create(
                        subpath.segment_index,
                        self.path_monoids.items,
                        self.segment_offsets.items,
                        self.paths.items,
                        self.subpaths.items,
                    );

                    std.debug.print("Subpath({},{})\n", .{ path_monoid.path_index, path_monoid.subpath_index });
                    std.debug.print("Fill Lines\n", .{});
                    std.debug.print("-----------\n", .{});
                    for (subpath_offset.start_fill_flat_segment_offset..subpath_offset.end_fill_flat_segment_offset) |flat_segment_index| {
                        const flat_segment = self.flat_segments.items[flat_segment_index];
                        std.debug.print("--- Segment({}) ---\n", .{flat_segment.segment_index});
                        var line_iter = encoding_module.LineIterator{
                            .line_data = self.line_data.items[flat_segment.start_line_data_offset..flat_segment.end_line_data_offset],
                        };

                        while (line_iter.next()) |line| {
                            std.debug.print("{}\n", .{line});
                        }
                    }
                    std.debug.print("-----------\n\n", .{});

                    std.debug.print("Front Stroke Lines\n", .{});
                    std.debug.print("-----------\n", .{});
                    for (subpath_offset.start_front_stroke_flat_segment_offset..subpath_offset.end_front_stroke_flat_segment_offset) |flat_segment_index| {
                        const flat_segment = self.flat_segments.items[flat_segment_index];
                        std.debug.print("--- Segment({}) ---\n", .{flat_segment.segment_index});
                        var line_iter = encoding_module.LineIterator{
                            .line_data = self.line_data.items[flat_segment.start_line_data_offset..flat_segment.end_line_data_offset],
                        };

                        while (line_iter.next()) |line| {
                            std.debug.print("{}\n", .{line});
                        }
                    }
                    std.debug.print("-----------\n\n", .{});

                    std.debug.print("Back Stroke Lines\n", .{});
                    std.debug.print("-----------\n", .{});
                    for (subpath_offset.start_back_stroke_flat_segment_offset..subpath_offset.end_back_stroke_flat_segment_offset) |flat_segment_index| {
                        const flat_segment = self.flat_segments.items[flat_segment_index];
                        std.debug.print("--- Segment({}) ---\n", .{flat_segment.segment_index});
                        var line_iter = encoding_module.LineIterator{
                            .line_data = self.line_data.items[flat_segment.start_line_data_offset..flat_segment.end_line_data_offset],
                        };

                        while (line_iter.next()) |line| {
                            std.debug.print("{}\n", .{line});
                        }
                    }
                    std.debug.print("-----------\n", .{});
                }
            }
        }

        if (self.config.debugIntersect()) {
            std.debug.print("============ Grid Intersections ============\n", .{});
            for (self.subpaths.items) |subpath| {
                const path_monoid = self.path_monoids.items[subpath.segment_index];
                const subpath_offsets = SubpathOffset.create(
                    @intCast(path_monoid.segment_index),
                    self.path_monoids.items,
                    self.segment_offsets.items,
                    self.paths.items,
                    self.subpaths.items,
                );

                std.debug.print("Subpath({},{})\n", .{ path_monoid.path_index, path_monoid.subpath_index });
                std.debug.print("Fill Grid Intersections\n", .{});
                std.debug.print("-----------\n", .{});
                for (subpath_offsets.start_fill_flat_segment_offset..subpath_offsets.end_fill_flat_segment_offset) |flat_segment_index| {
                    const flat_segment = self.flat_segments.items[flat_segment_index];
                    std.debug.print("--- Segment({}) ---\n", .{flat_segment.segment_index});
                    const intersections = self.grid_intersections.items[flat_segment.start_intersection_offset..flat_segment.end_intersection_offset];

                    for (intersections) |intersection| {
                        std.debug.print("Pixel({},{}), T({}), Intersection({},{})\n", .{
                            intersection.pixel.x,
                            intersection.pixel.y,
                            intersection.intersection.t,
                            intersection.intersection.point.x,
                            intersection.intersection.point.y,
                        });
                    }
                }
                std.debug.print("-----------\n\n", .{});

                std.debug.print("Front Stroke Grid Intersections\n", .{});
                std.debug.print("-----------\n", .{});
                for (subpath_offsets.start_front_stroke_flat_segment_offset..subpath_offsets.end_front_stroke_flat_segment_offset) |flat_segment_index| {
                    const flat_segment = self.flat_segments.items[flat_segment_index];
                    std.debug.print("--- Segment({}) ---\n", .{flat_segment.segment_index});
                    const intersections = self.grid_intersections.items[flat_segment.start_intersection_offset..flat_segment.end_intersection_offset];

                    for (intersections) |intersection| {
                        std.debug.print("Pixel({},{}), T({}), Intersection({},{})\n", .{
                            intersection.pixel.x,
                            intersection.pixel.y,
                            intersection.intersection.t,
                            intersection.intersection.point.x,
                            intersection.intersection.point.y,
                        });
                    }
                }
                std.debug.print("-----------\n\n", .{});

                std.debug.print("Back Stroke Grid Intersections\n", .{});
                std.debug.print("-----------\n", .{});
                for (subpath_offsets.start_back_stroke_flat_segment_offset..subpath_offsets.end_back_stroke_flat_segment_offset) |flat_segment_index| {
                    const flat_segment = self.flat_segments.items[flat_segment_index];
                    std.debug.print("--- Segment({}) ---\n", .{flat_segment.segment_index});
                    const intersections = self.grid_intersections.items[flat_segment.start_intersection_offset..flat_segment.end_intersection_offset];

                    for (intersections) |intersection| {
                        std.debug.print("Pixel({},{}), T({}), Intersection({},{})\n", .{
                            intersection.pixel.x,
                            intersection.pixel.y,
                            intersection.intersection.t,
                            intersection.intersection.point.x,
                            intersection.intersection.point.y,
                        });
                    }
                }
                std.debug.print("-----------\n\n", .{});
            }
        }

        if (self.config.debugBoundary()) {
            std.debug.print("============ Boundary Fragments ============\n", .{});
            for (self.paths.items) |path| {
                const path_monoid = self.path_monoids.items[path.segment_index];

                std.debug.print("Path({})\n", .{path_monoid.path_index});
                std.debug.print("Fill Boundary Fragments\n", .{});
                std.debug.print("-----------\n", .{});
                for (path.start_fill_boundary_offset..path.end_fill_boundary_offset) |boundary_index| {
                    const boundary_fragment = self.boundary_fragments.items[boundary_index];
                    std.debug.print("Pixel({},{})\n", .{
                        boundary_fragment.pixel.x,
                        boundary_fragment.pixel.y,
                    });
                }
                std.debug.print("-----------\n\n", .{});

                std.debug.print("Stroke Boundary Fragments\n", .{});
                std.debug.print("-----------\n", .{});
                for (path.start_stroke_boundary_offset..path.end_stroke_boundary_offset) |boundary_index| {
                    const boundary_fragment = self.boundary_fragments.items[boundary_index];
                    std.debug.print("Pixel({},{})\n", .{
                        boundary_fragment.pixel.x,
                        boundary_fragment.pixel.y,
                    });
                }
                std.debug.print("-----------\n\n", .{});
            }
        }

        if (self.config.debugMerge()) {
            std.debug.print("============ Merge Fragments ============\n", .{});
            for (self.paths.items) |path| {
                const path_monoid = self.path_monoids.items[path.segment_index];

                std.debug.print("Path({})\n", .{path_monoid.path_index});
                std.debug.print("Fill Merge Fragments\n", .{});
                std.debug.print("-----------\n", .{});
                for (path.start_fill_boundary_offset..path.end_fill_boundary_offset) |merge_index| {
                    const merge_fragment = self.boundary_fragments.items[merge_index];
                    if (merge_fragment.is_merge) {
                        std.debug.print("Pixel({},{}), MainRayWinding({}), Stencil({b:0>16})\n", .{
                            merge_fragment.pixel.x,
                            merge_fragment.pixel.y,
                            merge_fragment.main_ray_winding,
                            merge_fragment.stencil_mask,
                        });
                    }
                }
                std.debug.print("-----------\n\n", .{});

                std.debug.print("Stroke Merge Fragments\n", .{});
                std.debug.print("-----------\n", .{});
                for (path.start_stroke_boundary_offset..path.end_stroke_boundary_offset) |merge_index| {
                    const merge_fragment = self.boundary_fragments.items[merge_index];
                    if (merge_fragment.is_merge) {
                        std.debug.print("Pixel({},{}), MainRayWinding({}), Stencil({b:0>16}\n", .{
                            merge_fragment.pixel.x,
                            merge_fragment.pixel.y,
                            merge_fragment.main_ray_winding,
                            merge_fragment.stencil_mask,
                        });
                    }
                }
                std.debug.print("-----------\n\n", .{});
            }
        }

        if (self.config.debugFlushTexture()) {
            std.debug.print("\n============== Boundary Texture\n\n", .{});
            for (0..texture.dimensions.height) |y| {
                std.debug.print("{:0>4}: ", .{y});
                for (0..texture.dimensions.width) |x| {
                    const pixel = texture.getPixelUnsafe(core.PointU32{
                        .x = @intCast(x),
                        .y = @intCast(y),
                    });

                    if (pixel.r < 1.0 or pixel.g < 1.0 or pixel.b < 1.0 or pixel.a < 1.0) {
                        std.debug.print("#", .{});
                    } else {
                        std.debug.print(";", .{});
                    }
                }

                std.debug.print("\n", .{});
            }

            std.debug.print("==============\n", .{});
        }
    }
};
