const std = @import("std");
const core = @import("../core/root.zig");
const encoding_module = @import("./encoding.zig");
const kernel_module = @import("./encoding_kernel.zig");
const texture_module = @import("./texture.zig");
const msaa_module = @import("./msaa.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RangeU32 = core.RangeU32;
const LineF32 = core.LineF32;
const KernelConfig = kernel_module.KernelConfig;
const Style = encoding_module.Style;
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
const Texture = texture_module.Texture;
const HalfPlanesU16 = msaa_module.HalfPlanesU16;

pub const CpuRasterizer = struct {
    const PathMonoidList = std.ArrayListUnmanaged(PathMonoid);
    const PathList = std.ArrayListUnmanaged(Path);
    const SubpathList = std.ArrayListUnmanaged(Subpath);
    const FlatSegmentList = std.ArrayListUnmanaged(FlatSegment);
    const SegmentOffsetList = std.ArrayListUnmanaged(SegmentOffset);
    const Buffer = std.ArrayListUnmanaged(u8);
    const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
    const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);
    const MergeFragmentList = std.ArrayListUnmanaged(MergeFragment);
    // const LineList = std.ArrayListUnmanaged(LineF32);
    // const BoolList = std.ArrayListUnmanaged(bool);
    // const SubpathList = std.ArrayListUnmanaged(Subpath);
    // const OffsetList = std.ArrayListUnmanaged(u32);

    allocator: Allocator,
    half_planes: *const HalfPlanesU16,
    config: KernelConfig,
    encoding: Encoding,
    path_monoids: PathMonoidList = PathMonoidList{},
    paths: PathList = PathList{},
    subpaths: SubpathList = SubpathList{},
    segment_offsets: SegmentOffsetList = SegmentOffsetList{},
    flat_segments: FlatSegmentList = FlatSegmentList{},
    line_data: Buffer = Buffer{},
    grid_intersections: GridIntersectionList = GridIntersectionList{},
    boundary_fragments: BoundaryFragmentList = BoundaryFragmentList{},
    merge_fragments: MergeFragmentList = MergeFragmentList{},

    pub fn init(
        allocator: Allocator,
        half_planes: *const HalfPlanesU16,
        config: KernelConfig,
        encoding: Encoding,
    ) @This() {
        return @This(){
            .allocator = allocator,
            .half_planes = half_planes,
            .config = config,
            .encoding = encoding,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.path_monoids.deinit(self.allocator);
        self.paths.deinit(self.allocator);
        self.subpaths.deinit(self.allocator);
        self.segment_offsets.deinit(self.allocator);
        self.flat_segments.deinit(self.allocator);
        self.line_data.deinit(self.allocator);
        self.grid_intersections.deinit(self.allocator);
        self.boundary_fragments.deinit(self.allocator);
        self.merge_fragments.deinit(self.allocator);
    }

    pub fn reset(self: *@This()) void {
        self.path_monoids.items.len = 0;
        self.paths.items.len = 0;
        self.subpaths.items.len = 0;
        self.segment_offsets.items.len = 0;
        self.flat_segments.items.len = 0;
        self.line_data.items.len = 0;
        self.grid_intersections.items.len = 0;
        self.boundary_fragments.items.len = 0;
        self.merge_fragments.items.len = 0;
    }

    pub fn rasterize(self: *@This(), texture: *Texture) !void {
        _ = texture;
        // reset the rasterizer
        self.reset();
        // expand path monoids
        try self.expandPathMonoids();
        // // estimate FlatEncoder memory requirements
        try self.estimateSegments();
        // allocate the FlatEncoder
        // use the FlatEncoder to flatten the encoding
        try self.flatten();
        // calculate scanline encoding
        try self.kernelRasterize();
        // write scanline encoding to texture
        // self.flushTexture(texture);
    }

    fn expandPathMonoids(self: *@This()) !void {
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
    }

    fn estimateSegments(self: *@This()) !void {
        const estimator = kernel_module.Estimate;
        const segment_offsets = try self.segment_offsets.addManyAsSlice(self.allocator, self.encoding.path_tags.len);
        const range = RangeU32{
            .start = 0,
            .end = @intCast(self.path_monoids.items.len),
        };
        var chunk_iter = range.chunkIterator(self.config.chunk_size);

        while (chunk_iter.next()) |chunk| {
            estimator.estimateSegments(
                self.config,
                self.encoding.path_tags,
                self.path_monoids.items,
                self.encoding.styles,
                self.encoding.transforms,
                self.encoding.segment_data,
                chunk,
                segment_offsets,
            );
        }

        SegmentOffset.expand(segment_offsets, segment_offsets);
    }

    fn flatten(self: *@This()) !void {
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
        var chunk_iter = range.chunkIterator(self.config.chunk_size);

        while (chunk_iter.next()) |chunk| {
            flattener.flatten(
                self.config,
                self.encoding.path_tags,
                self.path_monoids.items,
                self.encoding.styles,
                self.encoding.transforms,
                self.paths.items,
                self.subpaths.items,
                self.encoding.segment_data,
                chunk,
                self.segment_offsets.items,
                flat_segments,
                line_data,
            );
        }
    }

    fn kernelRasterize(self: *@This()) !void {
        const rasterizer = kernel_module.Rasterize;
        const last_segment_offset = self.segment_offsets.getLast();
        // const last_path = self.paths.getLast();
        // const path_bumps = try self.path_bumps.addManyAsSlice(self.allocator, self.paths.items.len);
        // for (path_bumps) |*sb| {
        //     sb.raw = 0;
        // }
        const grid_intersections = try self.grid_intersections.addManyAsSlice(self.allocator, last_segment_offset.sum.intersections);
        const boundary_fragments = try self.boundary_fragments.addManyAsSlice(self.allocator, last_segment_offset.sum.boundary_fragments);
        const merge_fragments = try self.merge_fragments.addManyAsSlice(self.allocator, last_segment_offset.sum.boundary_fragments);

        const flat_segment_range = RangeU32{
            .start = 0,
            .end = @intCast(self.flat_segments.items.len),
        };

        var chunk_iter = flat_segment_range.chunkIterator(self.config.chunk_size);
        while (chunk_iter.next()) |chunk| {
            rasterizer.intersect(
                self.line_data.items,
                chunk,
                self.flat_segments.items,
                grid_intersections,
            );
        }

        chunk_iter = flat_segment_range.chunkIterator(self.config.chunk_size);
        while (chunk_iter.next()) |chunk| {
            rasterizer.boundary(
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
            );
        }

        for (self.paths.items) |*path| {
            const path_monoid = self.path_monoids.items[path.segment_index];
            const path_offset = PathOffset.create(
                path_monoid.path_index,
                self.segment_offsets.items,
                self.paths.items,
            );

            path.start_fill_boundary_offset = path_offset.start_fill_boundary_offset;
            path.end_fill_boundary_offset = path_offset.start_fill_boundary_offset + path.fill_bump.raw;

            path.start_stroke_boundary_offset = path_offset.start_stroke_boundary_offset;
            path.end_stroke_boundary_offset = path_offset.start_stroke_boundary_offset + path.stroke_bump.raw;

            std.mem.sort(
                BoundaryFragment,
                self.boundary_fragments.items[path.start_fill_boundary_offset..path.end_fill_boundary_offset],
                @as(u32, 0),
                boundaryFragmentLessThan,
            );

            std.mem.sort(
                BoundaryFragment,
                self.boundary_fragments.items[path.start_stroke_boundary_offset..path.end_stroke_boundary_offset],
                @as(u32, 0),
                boundaryFragmentLessThan,
            );

            path.fill_bump.raw = 0;
            path.stroke_bump.raw = 0;
        }

        rasterizer.merge(
            boundary_fragments,
            self.paths.items,
            merge_fragments,
        );

        for (self.paths.items) |*path| {
            path.end_fill_merge_offset = path.start_fill_boundary_offset + path.fill_bump.raw;
            path.end_stroke_merge_offset = path.start_stroke_boundary_offset + path.stroke_bump.raw;

            path.fill_bump.raw = 0;
            path.stroke_bump.raw = 0;
        }

        // rasterizer.mask(
        //     self.config,
        //     self.paths.items,
        //     self.boundary_fragments.items,
        //     self.merge_fragments.items,
        // );
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

    pub fn debugPrint(self: @This(), texture: Texture) void {
        _ = texture;
        std.debug.print("============ Path Monoids ============\n", .{});
        for (self.path_monoids.items) |path_monoid| {
            std.debug.print("{}\n", .{path_monoid});
        }
        std.debug.print("======================================\n", .{});

        //         std.debug.print("============ Subpaths ============\n", .{});
        //         for (self.subpaths.items, 0..) |subpath, index| {
        //             std.debug.print("({}): {}\n", .{ index, subpath });
        //         }
        //         std.debug.print("==================================\n", .{});

        std.debug.print("============ Path Segments ============\n", .{});
        for (self.encoding.path_tags, self.path_monoids.items, 0..) |path_tag, path_monoid, segment_index| {
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

            const offset = self.segment_offsets.items[segment_index];
            std.debug.print("Offset: {}\n", .{offset});
            std.debug.print("----------\n", .{});
        }
        std.debug.print("======================================\n", .{});

        {
            std.debug.print("============ Flat Fill Lines ============\n", .{});
            for (self.subpaths.items) |subpath| {
                const path_monoid = self.path_monoids.items[subpath.segment_index];
                const subpath_offsets = SubpathOffset.create(
                    subpath.segment_index,
                    self.path_monoids.items,
                    self.segment_offsets.items,
                    self.paths.items,
                    self.subpaths.items,
                );

                std.debug.print("Subpath({},{})\n", .{ path_monoid.path_index, path_monoid.subpath_index });
                std.debug.print("Fill Lines\n", .{});
                std.debug.print("-----------\n", .{});
                for (subpath_offsets.start_fill_flat_segment_offset..subpath_offsets.end_fill_flat_segment_offset) |flat_segment_index| {
                    const flat_segment = self.flat_segments.items[flat_segment_index];
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
                for (subpath_offsets.start_front_stroke_flat_segment_offset..subpath_offsets.end_front_stroke_flat_segment_offset) |flat_segment_index| {
                    const flat_segment = self.flat_segments.items[flat_segment_index];
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
                for (subpath_offsets.start_back_stroke_flat_segment_offset..subpath_offsets.end_back_stroke_flat_segment_offset) |flat_segment_index| {
                    const flat_segment = self.flat_segments.items[flat_segment_index];
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

        {
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

                // std.debug.print("Front Grid Intersections\n", .{});
                // std.debug.print("-----------\n", .{});
                // for (subpath_offsets.start_front_stroke_flat_segment_offset..subpath_offsets.end_front_stroke_flat_segment_offset) |flat_segment_index| {
                //     const flat_segment = self.flat_segments.items[flat_segment_index];
                //     var line_iter = encoding_module.LineIterator{
                //         .line_data = self.line_data.items[flat_segment.start_line_data_offset..flat_segment.end_line_data_offset],
                //     };

                //     while (line_iter.next()) |line| {
                //         std.debug.print("{}\n", .{line});
                //     }
                // }
                // std.debug.print("-----------\n\n", .{});

                // std.debug.print("Back Grid Intersections\n", .{});
                // std.debug.print("-----------\n", .{});
                // for (subpath_offsets.start_back_stroke_flat_segment_offset..subpath_offsets.end_back_stroke_flat_segment_offset) |flat_segment_index| {
                //     const flat_segment = self.flat_segments.items[flat_segment_index];
                //     var line_iter = encoding_module.LineIterator{
                //         .line_data = self.line_data.items[flat_segment.start_line_data_offset..flat_segment.end_line_data_offset],
                //     };

                //     while (line_iter.next()) |line| {
                //         std.debug.print("{}\n", .{line});
                //     }
                // }
                // std.debug.print("-----------\n", .{});
            }
        }

        //         {
        //             std.debug.print("============ Boundary Fragments ============\n", .{});
        //             var start_boundary_offset: u32 = 0;
        //             for (self.paths.items) |path| {
        //                 const end_boundary_offset = path.fill.boundary_fragment.end;
        //                 const boundary_fragments = self.boundary_fragments.items[start_boundary_offset..end_boundary_offset];

        //                 std.debug.print("--- Path({}) ---\n", .{
        //                     path.index,
        //                 });
        //                 for (boundary_fragments) |boundary_fragment| {
        //                     std.debug.print("Pixel({}), Intersection1({}), Intersection2({})\n", .{
        //                         boundary_fragment.pixel,
        //                         boundary_fragment.intersections[0],
        //                         boundary_fragment.intersections[1],
        //                     });
        //                 }

        //                 start_boundary_offset = path.fill.boundary_fragment.capacity;
        //             }
        //             std.debug.print("============================================\n", .{});
        //         }

        //         {
        //             std.debug.print("============ Merge Fragments ============\n", .{});
        //             var start_merge_offset: u32 = 0;
        //             for (self.paths.items) |path| {
        //                 const end_merge_offset = path.fill.merge_fragment.end;
        //                 const merge_fragments = self.merge_fragments.items[start_merge_offset..end_merge_offset];

        //                 std.debug.print("--- Path({}) ---\n", .{
        //                     path.index,
        //                 });
        //                 for (merge_fragments) |merge_fragment| {
        //                     std.debug.print("Pixel({}), StencilMask({b:0>16})\n", .{ merge_fragment.pixel, merge_fragment.stencil_mask });
        //                 }

        //                 start_merge_offset = path.fill.merge_fragment.capacity;
        //             }
        //             std.debug.print("=======================================\n", .{});
        //         }

        //         {
        //             std.debug.print("\n============== Boundary Texture\n\n", .{});
        //             for (0..texture.dimensions.height) |y| {
        //                 std.debug.print("{:0>4}: ", .{y});
        //                 for (0..texture.dimensions.width) |x| {
        //                     const pixel = texture.getPixelUnsafe(core.PointU32{
        //                         .x = @intCast(x),
        //                         .y = @intCast(y),
        //                     });

        //                     if (pixel.r < 1.0) {
        //                         std.debug.print("#", .{});
        //                     } else {
        //                         std.debug.print(";", .{});
        //                     }
        //                 }

        //                 std.debug.print("\n", .{});
        //             }

        //             std.debug.print("==============\n", .{});
        //         }
    }
};

// pub const CpuRasterizer = struct {
//     const PathTagList = std.ArrayListUnmanaged(PathTag);
//     const PathMonoidList = std.ArrayListUnmanaged(PathMonoid);
//     const SegmentEstimateList = std.ArrayListUnmanaged(SegmentEstimates);
//     const SegmentOffsetList = std.ArrayListUnmanaged(SegmentOffsets);
//     const LineList = std.ArrayListUnmanaged(LineF32);
//     const BoolList = std.ArrayListUnmanaged(bool);
//     const Buffer = std.ArrayListUnmanaged(u8);
//     const PathList = std.ArrayListUnmanaged(Path);
//     const SubpathList = std.ArrayListUnmanaged(Subpath);
//     const GridIntersectionList = std.ArrayListUnmanaged(GridIntersection);
//     const BoundaryFragmentList = std.ArrayListUnmanaged(BoundaryFragment);
//     const MergeFragmentList = std.ArrayListUnmanaged(MergeFragment);
//     const BumpAllocatorList = std.ArrayListUnmanaged(std.atomic.Value(u32));
//     const OffsetList = std.ArrayListUnmanaged(u32);

//     allocator: Allocator,
//     half_planes: HalfPlanesU16,
//     config: KernelConfig,
//     encoding: Encoding,
//     path_monoids: PathMonoidList = PathMonoidList{},
//     flat_segment_estimates: SegmentEstimateList = SegmentEstimateList{},
//     flat_segment_offsets: SegmentOffsetList = SegmentOffsetList{},
//     flat_segment_data: Buffer = Buffer{},
//     paths: PathList = PathList{},
//     subpaths: SubpathList = SubpathList{},
//     path_bumps: BumpAllocatorList = BumpAllocatorList{},
//     boundary_fragment_offsets: OffsetList = OffsetList{},
//     grid_intersections: GridIntersectionList = GridIntersectionList{},
//     boundary_fragments: BoundaryFragmentList = BoundaryFragmentList{},
//     merge_fragments: MergeFragmentList = MergeFragmentList{},

//     pub fn init(
//         allocator: Allocator,
//         half_planes: HalfPlanesU16,
//         config: KernelConfig,
//         encoding: Encoding,
//     ) @This() {
//         return @This(){
//             .allocator = allocator,
//             .half_planes = half_planes,
//             .config = config,
//             .encoding = encoding,
//         };
//     }

//     pub fn deinit(self: *@This()) void {
//         self.path_monoids.deinit(self.allocator);
//         self.flat_segment_estimates.deinit(self.allocator);
//         self.flat_segment_offsets.deinit(self.allocator);
//         self.flat_segment_data.deinit(self.allocator);
//         self.paths.deinit(self.allocator);
//         self.subpaths.deinit(self.allocator);
//         self.path_bumps.deinit(self.allocator);
//         self.boundary_fragment_offsets.deinit(self.allocator);
//         self.grid_intersections.deinit(self.allocator);
//         self.boundary_fragments.deinit(self.allocator);
//         self.merge_fragments.deinit(self.allocator);
//     }

//     pub fn reset(self: *@This()) void {
//         self.path_monoids.items.len = 0;
//         self.flat_segment_estimates.items.len = 0;
//         self.flat_segment_offsets.items.len = 0;
//         self.flat_segment_data.items.len = 0;
//         self.paths.items.len = 0;
//         self.subpaths.items.len = 0;
//         self.path_bumps.items.len = 0;
//         self.boundary_fragment_offsets.items.len = 0;
//         self.grid_intersections.items.len = 0;
//         self.boundary_fragments.items.len = 0;
//         self.merge_fragments.items.len = 0;
//     }

//     pub fn rasterize(self: *@This(), texture: *Texture) !void {
//         // reset the rasterizer
//         self.reset();
//         // expand path monoids
//         try self.expandPathMonoids();
//         // estimate FlatEncoder memory requirements
//         try self.estimateSegments();
//         // allocate the FlatEncoder
//         // use the FlatEncoder to flatten the encoding
//         try self.flatten();
//         // calculate scanline encoding
//         try self.kernelRasterize();
//         // write scanline encoding to texture
//         self.flushTexture(texture);
//     }

//     fn expandPathMonoids(self: *@This()) !void {
//         const path_monoids = try self.path_monoids.addManyAsSlice(self.allocator, self.encoding.path_tags.len);
//         PathMonoid.expand(self.encoding.path_tags, path_monoids);
//     }

//     fn estimateSegments(self: *@This()) !void {
//         const estimator = encoding_kernel.Estimate;
//         const flat_segment_estimates = try self.flat_segment_estimates.addManyAsSlice(self.allocator, self.encoding.path_tags.len);
//         const range = RangeU32{
//             .start = 0,
//             .end = @intCast(self.path_monoids.items.len),
//         };
//         var chunk_iter = range.chunkIterator(self.config.chunk_size);

//         while (chunk_iter.next()) |chunk| {
//             estimator.estimateSegments(
//                 self.config,
//                 self.encoding.path_tags,
//                 self.path_monoids.items,
//                 self.encoding.styles,
//                 self.encoding.transforms,
//                 self.encoding.segment_data,
//                 chunk,
//                 flat_segment_estimates,
//             );
//         }

//         // TODO: expand SegmentEstimate into SegmentOffsets
//         const flat_segment_offsets = try self.flat_segment_offsets.addManyAsSlice(self.allocator, flat_segment_estimates.len);
//         SegmentOffsets.expand(flat_segment_estimates, flat_segment_offsets);

//         const paths_n = self.path_monoids.getLast().path_index + 1;
//         const paths = try self.paths.addManyAsSlice(self.allocator, paths_n);
//         const subpath_n = self.path_monoids.getLast().subpath_index + 1;
//         const subpaths = try self.subpaths.addManyAsSlice(self.allocator, subpath_n);
//         SegmentOffsets.expandPaths(
//             self.encoding.path_tags,
//             self.path_monoids.items,
//             self.flat_segment_offsets.items,
//             paths,
//             subpaths,
//         );
//     }

//     fn flatten(self: *@This()) !void {
//         const flattener = encoding_kernel.Flatten;
//         const last_segment_offsets = self.flat_segment_offsets.getLast();
//         const flat_segment_data = try self.flat_segment_data.addManyAsSlice(
//             self.allocator,
//             last_segment_offsets.fill.line.capacity,
//         );

//         const range = RangeU32{
//             .start = 0,
//             .end = @intCast(self.path_monoids.items.len),
//         };
//         var chunk_iter = range.chunkIterator(self.config.chunk_size);

//         while (chunk_iter.next()) |chunk| {
//             flattener.flatten(
//                 self.config,
//                 self.encoding.path_tags,
//                 self.path_monoids.items,
//                 self.encoding.styles,
//                 self.encoding.transforms,
//                 self.encoding.segment_data,
//                 chunk,
//                 self.flat_segment_offsets.items,
//                 flat_segment_data,
//             );
//         }
//     }

//     fn kernelRasterize(self: *@This()) !void {
//         const rasterizer = encoding_kernel.Rasterize;
//         const last_segment_offsets = self.flat_segment_offsets.getLast();
//         const last_path = self.paths.getLast();
//         const path_bumps = try self.path_bumps.addManyAsSlice(self.allocator, self.paths.items.len);
//         for (path_bumps) |*sb| {
//             sb.raw = 0;
//         }
//         const grid_intersections = try self.grid_intersections.addManyAsSlice(self.allocator, last_segment_offsets.fill.intersection.capacity);
//         const boundary_fragments = try self.boundary_fragments.addManyAsSlice(self.allocator, last_path.fill.boundary_fragment.capacity);
//         const merge_fragments = try self.merge_fragments.addManyAsSlice(self.allocator, last_path.fill.merge_fragment.capacity);

//         const range = RangeU32{
//             .start = 0,
//             .end = @intCast(self.path_monoids.items.len),
//         };
//         const path_range = RangeU32{
//             .start = 0,
//             .end = @intCast(self.paths.items.len),
//         };

//         var chunk_iter = range.chunkIterator(self.config.chunk_size);
//         while (chunk_iter.next()) |chunk| {
//             rasterizer.intersect(
//                 self.flat_segment_data.items,
//                 chunk,
//                 self.flat_segment_offsets.items,
//                 grid_intersections,
//             );
//         }

//         chunk_iter = range.chunkIterator(self.config.chunk_size);
//         while (chunk_iter.next()) |chunk| {
//             rasterizer.boundary(
//                 self.half_planes,
//                 self.path_monoids.items,
//                 self.paths.items,
//                 self.subpaths.items,
//                 grid_intersections,
//                 self.flat_segment_offsets.items,
//                 chunk,
//                 path_bumps,
//                 boundary_fragments,
//             );
//         }

//         var start_boundary_fragment: u32 = 0;
//         for (self.paths.items, path_bumps) |*path, bump| {
//             path.fill.boundary_fragment.end = start_boundary_fragment + bump.raw;
//             std.mem.sort(
//                 BoundaryFragment,
//                 self.boundary_fragments.items[start_boundary_fragment..path.fill.boundary_fragment.end],
//                 @as(u32, 0),
//                 boundaryFragmentLessThan,
//             );
//             start_boundary_fragment = path.fill.boundary_fragment.capacity;
//         }

//         for (self.path_bumps.items) |*bump| {
//             bump.raw = 0;
//         }

//         chunk_iter = path_range.chunkIterator(self.config.chunk_size);
//         while (chunk_iter.next()) |chunk| {
//             rasterizer.merge(
//                 self.paths.items,
//                 self.boundary_fragments.items,
//                 chunk,
//                 self.path_bumps.items,
//                 merge_fragments,
//             );
//         }

//         var start_merge_fragment: u32 = 0;
//         for (self.paths.items, path_bumps) |*path, bump| {
//             path.fill.merge_fragment.end = start_merge_fragment + bump.raw;
//             start_merge_fragment = path.fill.merge_fragment.capacity;
//         }

//         chunk_iter = path_range.chunkIterator(self.config.chunk_size);
//         while (chunk_iter.next()) |chunk| {
//             rasterizer.mask(
//                 self.config,
//                 self.paths.items,
//                 self.boundary_fragments.items,
//                 chunk,
//                 self.merge_fragments.items,
//             );
//         }
//     }

//     fn boundaryFragmentLessThan(_: u32, left: BoundaryFragment, right: BoundaryFragment) bool {
//         if (left.pixel.y < right.pixel.y) {
//             return true;
//         } else if (left.pixel.y > right.pixel.y) {
//             return false;
//         } else if (left.pixel.x < right.pixel.x) {
//             return true;
//         } else if (left.pixel.x > right.pixel.x) {
//             return false;
//         }

//         return false;
//     }

//     fn flushTexture(self: @This(), texture: *Texture) void {
//         const blend = ColorBlend.Alpha;

//         for (self.paths.items) |path| {
//             var start_merge_offset: u32 = 0;
//             const previous_path = if (path.index > 0) self.paths.items[path.index - 1] else null;
//             if (previous_path) |p| {
//                 start_merge_offset = p.fill.merge_fragment.capacity;
//             }
//             const end_merge_offset = path.fill.merge_fragment.end;

//             const path_merge_fragments = self.merge_fragments.items[start_merge_offset..end_merge_offset];
//             for (path_merge_fragments) |fragment| {
//                 const intensity = fragment.getIntensity();
//                 const pixel = fragment.pixel;
//                 if (pixel.x < 0 or pixel.y < 0) {
//                     continue;
//                 }

//                 const texture_pixel = PointU32{
//                     .x = @intCast(pixel.x),
//                     .y = @intCast(pixel.y),
//                 };
//                 const fragment_color = ColorF32{
//                     .r = 0.0,
//                     .g = 0.0,
//                     .b = 0.0,
//                     .a = intensity,
//                 };
//                 const texture_color = texture.getPixelUnsafe(texture_pixel);
//                 const blend_color = blend.blend(fragment_color, texture_color);
//                 texture.setPixelUnsafe(texture_pixel, blend_color);
//             }
//         }
//     }

// };

test "encoding path monoids" {
    const Encoder = encoding_module.Encoder;
    const Colors = texture_module.Colors;
    const ColorU8 = texture_module.ColorU8;

    var encoder = Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.encodeColor(ColorU8{
        .r = 255,
        .g = 255,
        .b = 0,
        .a = 255,
    });
    var style = Style{};
    style.setFill(Style.Fill{
        .brush = .color,
    });
    style.setStroke(Style.Stroke{
        .join = .bevel,
    });
    try encoder.encodeStyle(style);

    var path_encoder = encoder.pathEncoder(f32);
    try path_encoder.moveTo(core.PointF32.create(10.0, 10.0));
    _ = try path_encoder.lineTo(core.PointF32.create(20.0, 20.0));
    _ = try path_encoder.lineTo(core.PointF32.create(40.0, 20.0));
    //_ = try path_encoder.arcTo(core.PointF32.create(3.0, 3.0), core.PointF32.create(4.0, 2.0));
    _ = try path_encoder.lineTo(core.PointF32.create(10.0, 10.0));
    try path_encoder.finish();

    var path_encoder2 = encoder.pathEncoder(i16);
    try path_encoder2.moveTo(core.PointI16.create(10, 10));
    _ = try path_encoder2.lineTo(core.PointI16.create(20, 20));
    _ = try path_encoder2.lineTo(core.PointI16.create(15, 30));
    _ = try path_encoder2.quadTo(core.PointI16.create(33, 44), core.PointI16.create(100, 100));
    _ = try path_encoder2.cubicTo(
        core.PointI16.create(120, 120),
        core.PointI16.create(70, 130),
        core.PointI16.create(22, 22),
    );
    try path_encoder2.finish();

    var half_planes = try HalfPlanesU16.init(std.testing.allocator);
    defer half_planes.deinit();

    const encoding = encoder.encode();
    var rasterizer = CpuRasterizer.init(
        std.testing.allocator,
        &half_planes,
        kernel_module.KernelConfig.DEFAULT,
        encoding,
    );
    defer rasterizer.deinit();

    var texture = try Texture.init(std.testing.allocator, core.DimensionsU32{
        .width = 50,
        .height = 50,
    }, texture_module.TextureFormat.RgbaU8);
    defer texture.deinit();
    texture.clear(Colors.WHITE);

    try rasterizer.rasterize(&texture);

    rasterizer.debugPrint(texture);
    // const path_monoids = rasterizer.path_monoids.items;

    // try std.testing.expectEqualDeep(
    //     core.LineF32.create(core.PointF32.create(1.0, 1.0), core.PointF32.create(2.0, 2.0)),
    //     encoding.getSegment(core.LineF32, path_monoids[0]),
    // );
    // try std.testing.expectEqualDeep(
    //     core.ArcF32.create(
    //         core.PointF32.create(2.0, 2.0),
    //         core.PointF32.create(3.0, 3.0),
    //         core.PointF32.create(4.0, 2.0),
    //     ),
    //     encoding.getSegment(core.ArcF32, path_monoids[1]),
    // );
    // try std.testing.expectEqualDeep(
    //     core.LineF32.create(core.PointF32.create(4.0, 2.0), core.PointF32.create(1.0, 1.0)),
    //     encoding.getSegment(core.LineF32, path_monoids[2]),
    // );

    // try std.testing.expectEqualDeep(
    //     core.LineI16.create(core.PointI16.create(10, 10), core.PointI16.create(20, 20)),
    //     encoding.getSegment(core.LineI16, path_monoids[3]),
    // );
}
