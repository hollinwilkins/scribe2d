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
const Encoding = encoding_module.Encoding;
const PathMonoid = encoding_module.PathMonoid;
const BumpAllocator = encoding_module.BumpAllocator;
const Path = encoding_module.Path;
const Subpath = encoding_module.Subpath;
const PathOffset = encoding_module.PathOffset;
const FlatPath = encoding_module.FlatPath;
const FlatSubpath = encoding_module.FlatSubpath;
const FlatSegment = encoding_module.FlatSegment;
const LineOffset = encoding_module.PathOffset;
const SegmentOffset = encoding_module.SegmentOffset;
const IntersectionOffset = encoding_module.IntersectionOffset;
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
        pub const RUN_FLAG_ALLOCATE_LINES: u8 = 0b00000010;
        pub const RUN_FLAG_FLATTEN: u8 = 0b00000100;
        pub const RUN_FLAG_INTERSECT: u8 = 0b00001000;
        pub const RUN_FLAG_BOUNDARY: u8 = 0b00010000;
        pub const RUN_FLAG_MERGE: u8 = 0b00100000;
        pub const RUN_FLAG_MASK: u8 = 0b01000000;
        pub const RUN_FLAG_FLUSH_TEXTURE: u8 = 0b10000000;
        pub const RUN_FLAG_ALL = RUN_FLAG_EXPAND_MONOIDS | RUN_FLAG_ALLOCATE_LINES |
            RUN_FLAG_FLATTEN | RUN_FLAG_INTERSECT | RUN_FLAG_BOUNDARY |
            RUN_FLAG_MERGE | RUN_FLAG_MASK | RUN_FLAG_FLUSH_TEXTURE;

        run_flags: u8 = RUN_FLAG_FLUSH_TEXTURE,
        debug_flags: u8 = RUN_FLAG_ALL,
        debug_single_pass: bool = false,
        flush_texture_boundary: bool = true,
        flush_texture_span: bool = true,
        kernel_config: KernelConfig = KernelConfig.DEFAULT,

        pub fn runExpandMonoids(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_EXPAND_MONOIDS;
        }

        pub fn debugExpandMonoids(self: @This()) bool {
            return self.runExpandMonoids() and self.debug_flags & RUN_FLAG_EXPAND_MONOIDS > 0;
        }

        pub fn runAllocateLines(self: @This()) bool {
            return self.run_flags >= RUN_FLAG_ALLOCATE_LINES;
        }

        pub fn debugEstimateSegments(self: @This()) bool {
            return self.runAllocateLines() and self.debug_flags & RUN_FLAG_ALLOCATE_LINES > 0;
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
            return self.debug_single_pass and self.runIntersect() and self.debug_flags & RUN_FLAG_INTERSECT > 0;
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
    const PathList = std.ArrayListUnmanaged(Path);
    const SubpathList = std.ArrayListUnmanaged(Subpath);
    const FlatSegmentList = std.ArrayListUnmanaged(FlatSegment);
    const SegmentOffsetList = std.ArrayListUnmanaged(SegmentOffset);
    const IntersectionOffsetList = std.ArrayListUnmanaged(IntersectionOffset);
    const LinesList = std.ArrayListUnmanaged(LineF32);
    const Buffer = std.ArrayListUnmanaged(u8);
    const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
    const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);

    allocator: Allocator,
    half_planes: *const HalfPlanesU16,
    config: Config,
    encoding: Encoding,
    path_monoids: PathMonoidList = PathMonoidList{},
    style_offsets: SegmentOffsetList = SegmentOffsetList{},
    paths: PathList = PathList{},
    subpaths: SubpathList = SubpathList{},
    segment_offsets: SegmentOffsetList = SegmentOffsetList{},
    intersection_offsets: IntersectionOffsetList = IntersectionOffsetList{},
    flat_segments: FlatSegmentList = FlatSegmentList{},
    lines: LinesList = LinesList{},
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
        self.intersection_offsets.deinit(self.allocator);
        self.flat_segments.deinit(self.allocator);
        self.lines.deinit(self.allocator);
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
        self.lines.items.len = 0;
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

        if (!self.config.runAllocateLines()) {
            return;
        }

        // estimate FlatEncoder memory requirements
        try self.allocateLines(&pool);

        if (!self.config.runFlatten()) {
            return;
        }

        try self.flatten(&pool);

        if (!self.config.runBoundary()) {
            return;
        }

        try self.allocateBoundaryFragments(&pool);
        try self.tile(&pool);

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
        for (self.encoding.styles, style_offsets) |style, *style_offset| {
            style_offset.* = SegmentOffset{
                .fill_offset = style.fill.brush.offset(),
                .stroke_offset = style.stroke.brush.offset(),
            };
        }

        SegmentOffset.expand(style_offsets, style_offsets);
    }

    fn allocateLines(self: *@This(), pool: *std.Thread.Pool) !void {
        var wg = std.Thread.WaitGroup{};
        const allocator = kernel_module.LineAllocator;
        const segment_offsets = try self.segment_offsets.addManyAsSlice(self.allocator, self.encoding.path_tags.len);
        const range = RangeU32{
            .start = 0,
            .end = @intCast(self.path_monoids.items.len),
        };
        var chunk_iter = range.chunkIterator(self.config.kernel_config.chunk_size);

        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                allocator.flatten,
                .{
                    self.config.kernel_config,
                    self.encoding.path_tags,
                    self.path_monoids.items,
                    self.subpaths.items,
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
        const last_segment_offset = self.segment_offsets.getLast();
        _ = try self.lines.addManyAsSlice(
            self.allocator,
            last_segment_offset.fill_offset + last_segment_offset.stroke_offset,
        );

        for (self.paths.items, 0..) |*path, path_index| {
            path.line_offset = PathOffset.lineOffset(@intCast(path_index), segment_offsets, self.paths.items);
        }
    }

    fn flatten(self: *@This(), pool: *std.Thread.Pool) !void {
        var wg = std.Thread.WaitGroup{};
        const lines = self.lines.items;

        const range = RangeU32{
            .start = 0,
            .end = @intCast(self.path_monoids.items.len),
        };
        var chunk_iter = range.chunkIterator(self.config.kernel_config.chunk_size);

        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                kernel_module.Flatten.flatten,
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
                    lines,
                },
            );
        }

        wg.wait();

        for (self.paths.items) |*path| {
            std.debug.assert(path.assertLineAllocations());
            path.fill_bump.raw = 0;
            path.stroke_bump.raw = 0;
        }
    }

    fn allocateBoundaryFragments(self: *@This(), pool: *std.Thread.Pool) !void {
        var wg = std.Thread.WaitGroup{};
        const allocator = kernel_module.BoundaryAllocator;
        const intersection_offsets = try self.intersection_offsets.addManyAsSlice(self.allocator, self.lines.items.len);
        const range = RangeU32{
            .start = 0,
            .end = @intCast(self.lines.items.len),
        };
        var chunk_iter = range.chunkIterator(self.config.kernel_config.chunk_size);

        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                allocator.intersect,
                .{
                    self.lines.items,
                    chunk,
                    intersection_offsets,
                },
            );
        }

        wg.wait();

        IntersectionOffset.expand(intersection_offsets, intersection_offsets);

        for (self.paths.items) |*path| {
            path.boundary_offset = PathOffset.lineToBoundaryOffset(path.line_offset, intersection_offsets);
        }

        const last_boundary_offset = self.paths.getLast().boundary_offset;
        _ = try self.boundary_fragments.addManyAsSlice(
            self.allocator,
            last_boundary_offset.end_stroke_offset,
        );
    }

    fn tile(self: *@This(), pool: *std.Thread.Pool) !void {
        var wg = std.Thread.WaitGroup{};
        const tile_generator = kernel_module.TileGenerator;
        const boundary_fragments = self.boundary_fragments.items;

        for (0..self.paths.items.len) |path_index| {
            const path = &self.paths.items[path_index];

            const fill_range = RangeU32.create(path.line_offset.start_fill_offset, path.line_offset.end_fill_offset);
            const stroke_range = RangeU32.create(path.line_offset.start_stroke_offset, path.line_offset.end_stroke_offset);

            const fill_bump = BumpAllocator{
                .start = path.boundary_offset.start_fill_offset,
                .end = path.boundary_offset.end_fill_offset,
                .offset = &path.fill_bump,
            };
            const stroke_bump = BumpAllocator{
                .start = path.boundary_offset.start_stroke_offset,
                .end = path.boundary_offset.end_stroke_offset,
                .offset = &path.stroke_bump,
            };

            pool.spawnWg(
                &wg,
                tile_generator.tile,
                .{
                    self.half_planes,
                    self.lines.items,
                    fill_range,
                    fill_bump,
                    boundary_fragments,
                },
            );

            pool.spawnWg(
                &wg,
                tile_generator.tile,
                .{
                    self.half_planes,
                    self.lines.items,
                    stroke_range,
                    stroke_bump,
                    boundary_fragments,
                },
            );
        }

        wg.wait();

        for (self.paths.items) |*path| {
            path.boundary_offset.end_fill_offset = path.boundary_offset.start_fill_offset + path.fill_bump.raw;
            path.boundary_offset.end_stroke_offset = path.boundary_offset.start_stroke_offset + path.stroke_bump.raw;
            path.fill_bump.raw = 0;
            path.stroke_bump.raw = 0;
        }
    }

    fn kernelRasterize(self: *@This(), pool: *std.Thread.Pool) !void {
        if (!self.config.runMerge()) {
            return;
        }

        var wg = std.Thread.WaitGroup{};
        const rasterizer = kernel_module.Rasterize;

        const path_range = RangeU32{
            .start = 0,
            .end = @intCast(self.paths.items.len),
        };
        var chunk_iter = path_range.chunkIterator(self.config.kernel_config.chunk_size);
        while (chunk_iter.next()) |chunk| {
            pool.spawnWg(
                &wg,
                rasterizer.boundaryFinish,
                .{
                    chunk,
                    self.paths.items,
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
                    self.path_monoids.items,
                    self.paths.items,
                    self.encoding.styles,
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
            const transform = self.encoding.getTransform(path_monoid.transform_index);
            const style = self.encoding.getStyle(path_monoid.style_index);
            const style_offset = PathOffset.styleOffset(
                @intCast(path_monoid.style_index),
                self.style_offsets.items,
            );

            if (style.isFill()) {
                const fill_range = RangeU32{
                    .start = path.boundary_offset.start_fill_offset,
                    .end = path.boundary_offset.end_fill_offset,
                };

                if (self.config.flush_texture_boundary) {
                    var chunk_iter = fill_range.chunkIterator(self.config.kernel_config.chunk_size);
                    while (chunk_iter.next()) |chunk| {
                        pool.spawnWg(
                            &wg,
                            blender.fill,
                            .{
                                null,
                                self.config.kernel_config,
                                transform,
                                style.fill.brush,
                                style_offset.start_fill_offset,
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

                if (self.config.flush_texture_span) {
                    var chunk_iter = fill_range.chunkIterator(self.config.kernel_config.chunk_size);
                    while (chunk_iter.next()) |chunk| {
                        pool.spawnWg(
                            &wg,
                            blender.fillSpan,
                            .{
                                style.fill.rule,
                                null,
                                self.config.kernel_config,
                                transform,
                                style.fill.brush,
                                style_offset.start_fill_offset,
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

            if (style.isStroke()) {
                const stroke_range = RangeU32{
                    .start = path.boundary_offset.start_stroke_offset,
                    .end = path.boundary_offset.end_stroke_offset,
                };

                if (self.config.flush_texture_boundary) {
                    var chunk_iter = stroke_range.chunkIterator(self.config.kernel_config.chunk_size);
                    while (chunk_iter.next()) |chunk| {
                        pool.spawnWg(
                            &wg,
                            blender.fill,
                            .{
                                style.stroke,
                                self.config.kernel_config,
                                transform,
                                style.stroke.brush,
                                style_offset.start_stroke_offset,
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

                if (self.config.flush_texture_span) {
                    var chunk_iter = stroke_range.chunkIterator(self.config.kernel_config.chunk_size);
                    while (chunk_iter.next()) |chunk| {
                        pool.spawnWg(
                            &wg,
                            blender.fillSpan,
                            .{
                                .non_zero,
                                style.stroke,
                                self.config.kernel_config,
                                transform,
                                style.stroke.brush,
                                style_offset.start_stroke_offset,
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
    }

    pub fn debugPrint(self: @This(), texture: TextureUnmanaged) void {
        _ = texture;

        if (self.config.debugExpandMonoids()) {
            std.debug.print("============ Path Monoids ============\n", .{});
            for (self.path_monoids.items) |path_monoid| {
                std.debug.print("{}\n", .{path_monoid});
            }
            std.debug.print("======================================\n", .{});

            std.debug.print("========== Subpaths ============\n", .{});
            for (self.subpaths.items) |subpath| {
                const subpath_tag = self.encoding.path_tags[subpath.segment_index];
                const subpath_monoid = self.path_monoids.items[subpath.segment_index];
                std.debug.print("Subpath({},{},{})\n", .{
                    subpath_monoid.path_index,
                    subpath_monoid.subpath_index,
                    subpath_tag.segment.cap,
                });
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
            if (self.config.runFlatten()) {
                std.debug.print("============ Flat Fill Lines ============\n", .{});

                for (self.paths.items) |path| {
                    const path_monoid = self.path_monoids.items[path.segment_index];
                    std.debug.print("Path({})\n", .{path_monoid.path_index});

                    std.debug.print("-------------------- Fill Lines ----------------\n", .{});
                    const fill_lines = self.lines.items[path.line_offset.start_fill_offset..path.line_offset.end_fill_offset];
                    for (fill_lines) |line| {
                        std.debug.print("Line(({},{}),({},{}))\n", .{
                            line.p0.x,
                            line.p0.y,
                            line.p1.x,
                            line.p1.y,
                        });
                    }
                    std.debug.print("------------------- Stroke Lines ---------------\n", .{});
                    const stroke_lines = self.lines.items[path.line_offset.start_stroke_offset..path.line_offset.end_stroke_offset];
                    for (stroke_lines) |line| {
                        std.debug.print("Line(({},{}),({},{}))\n", .{
                            line.p0.x,
                            line.p0.y,
                            line.p1.x,
                            line.p1.y,
                        });
                    }
                    std.debug.print("------------------------------------------------\n", .{});
                }
            }
        }

        if (self.config.debugBoundary()) {
            if (self.config.runFlatten()) {
                std.debug.print("============ Boundary Fragments ============\n", .{});

                for (self.paths.items) |path| {
                    const path_monoid = self.path_monoids.items[path.segment_index];
                    std.debug.print("Path({})\n", .{path_monoid.path_index});

                    std.debug.print("-------------------- Fill Boundary Fragments ----------------\n", .{});
                    const fill_boundary_fragments = self.boundary_fragments.items[path.boundary_offset.start_fill_offset..path.boundary_offset.end_fill_offset];
                    for (fill_boundary_fragments) |boundary_fragment| {
                        boundary_fragment.debugPrint();
                    }
                    std.debug.print("------------------- Stroke Boundary Fragments ---------------\n", .{});
                    const stroke_boundary_fragments = self.boundary_fragments.items[path.boundary_offset.start_stroke_offset..path.boundary_offset.end_stroke_offset];
                    for (stroke_boundary_fragments) |boundary_fragment| {
                        boundary_fragment.debugPrint();
                    }
                    std.debug.print("------------------------------------------------\n", .{});
                }
            }
        }

        if (self.config.debugMerge()) {
            if (self.config.runFlatten()) {
                std.debug.print("============ Merge Fragments ============\n", .{});

                for (self.paths.items) |path| {
                    const path_monoid = self.path_monoids.items[path.segment_index];
                    std.debug.print("Path({})\n", .{path_monoid.path_index});

                    std.debug.print("-------------------- Fill Merge Fragments ----------------\n", .{});
                    const fill_boundary_fragments = self.boundary_fragments.items[path.boundary_offset.start_fill_offset..path.boundary_offset.end_fill_offset];
                    for (fill_boundary_fragments) |boundary_fragment| {
                        if (boundary_fragment.is_merge) {
                            boundary_fragment.debugPrint();
                        }
                    }
                    std.debug.print("------------------- Stroke Merge Fragments ---------------\n", .{});
                    const stroke_boundary_fragments = self.boundary_fragments.items[path.boundary_offset.start_stroke_offset..path.boundary_offset.end_stroke_offset];
                    for (stroke_boundary_fragments) |boundary_fragment| {
                        if (boundary_fragment.is_merge) {
                            boundary_fragment.debugPrint();
                        }
                    }
                    std.debug.print("------------------------------------------------\n", .{});
                }
            }
        }
    }
};
