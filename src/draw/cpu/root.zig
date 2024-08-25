const std = @import("std");
const core = @import("../../core/root.zig");
const encoding_module = @import("../encoding.zig");
const kernel_module = @import("./kernel.zig");
const msaa_module = @import("../msaa.zig");
const Allocator = std.mem.Allocator;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const CubicBezierF32 = core.CubicBezierF32;
const LineF32 = core.LineF32;
const Encoding = encoding_module.Encoding;
const PathTag = encoding_module.PathTag;
const PathMonoid = encoding_module.PathMonoid;
const KernelConfig = kernel_module.KernelConfig;
const HalfPlanesU16 = msaa_module.HalfPlanesU16;

pub const CpuRasterizer = struct {
    pub const Config = struct {
        kernel_config: KernelConfig = KernelConfig.DEFAULT,
        debug_flags: DebugFlags = DebugFlags{},
        buffer_sizes: BufferSizes = BufferSizes{},
    };

    allocator: Allocator,
    half_planes: *const HalfPlanesU16,
    config: Config,
    buffers: Buffers,

    pub fn init(
        allocator: Allocator,
        half_planes: *const HalfPlanesU16,
        config: Config,
    ) !@This() {
        const buffers = try Buffers.create(allocator, config.buffer_sizes);

        return @This(){
            .allocator = allocator,
            .half_planes = half_planes,
            .config = config,
            .buffers = buffers,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.buffers.deinit(self.allocator);
    }

    pub fn rasterize(self: *@This(), encoding: Encoding) void {
        // initialize buffer data
        self.buffers.path_monoids[0] = PathMonoid{};
        self.buffers.path_monoids[1] = PathMonoid{};
        self.buffers.path_offsets[0] = 0;
        self.buffers.path_offsets[1] = 0;

        var paths_iter = RangeU32.create(
            0,
            @intCast(encoding.path_offsets.len),
        ).chunkIterator(self.config.buffer_sizes.pathsSize());
        while (paths_iter.next()) |path_indices| {
            // load path_offsets
            std.mem.copyForwards(u32, self.buffers.path_offsets[2..], encoding.path_offsets[path_indices.start..path_indices.end]);
            self.buffers.path_offsets[1] = self.buffers.path_offsets[0];
            self.buffers.path_offsets[0] = encoding.path_offsets[path_indices.end - 1];

            var path_segments_iter = PathSegmentsIterator{
                .path_indices = path_indices,
                .path_offsets = self.buffers.path_offsets,
                .chunk_size = self.buffers.sizes.pathTagsSize(),
            };

            while (path_segments_iter.next()) |segment_indices| {
                // load path tags
                std.debug.print("SegmentIndices({})\n", .{segment_indices});
                // self.projections.segments = segment_indices;
                // std.mem.copyForwards(PathTag, self.buffers.path_tags, encoding.path_tags[segment_indices.start..segment_indices.end]);
                // const kernel_segment_indices = RangeU32.create(
                //     0,
                //     @intCast(segment_indices.size()),
                // );

                // kernel_module.PathMonoidExpander.expand(
                //     kernel_segment_indices,
                //     self.buffers.path_tags,
                //     self.buffers.path_monoids,
                // );

                // if (self.config.debug_flags.expand_monoids) {
                //     self.debugExpandMonoids();
                // }
            }
        }
    }

    pub fn debugExpandMonoids(self: @This()) void {
        _ = self;
        // std.debug.print("============ Path Monoids ============\n", .{});
        // const segments_size = self.projections.segments.size();
        // for (self.buffers.path_tags[0..segments_size], self.buffers.path_monoids[1 .. 1 + segments_size]) |path_tag, path_monoid| {
        //     std.debug.print("{}\n", .{path_monoid});
        //     const data = self.encoding.segment_data[path_monoid.segment_offset .. path_monoid.segment_offset + path_tag.segment.size()];
        //     const points = std.mem.bytesAsSlice(PointF32, data);
        //     std.debug.print("Points: {any}\n", .{points});
        //     std.debug.print("------------\n", .{});
        // }
        // std.debug.print("======================================\n", .{});
    }
};

pub const DebugFlags = struct {
    expand_monoids: bool = false,
    calculate_lines: bool = false,
};

pub const BufferSizes = struct {
    pub const DEFAULT_LINES_SIZE: u32 = 60;
    pub const DEFAULT_SEGMENTS_SIZE: u32 = 10;
    pub const DEFAULT_PATHS_SIZE: u32 = 10;

    paths_size: u32 = DEFAULT_PATHS_SIZE,
    path_tags_size: u32 = DEFAULT_SEGMENTS_SIZE,
    lines_size: u32 = DEFAULT_LINES_SIZE,

    pub fn pathsSize(self: @This()) u32 {
        return self.paths_size;
    }

    pub fn bumpsSize(self: @This()) u32 {
        return self.pathsSize() * 2;
    }

    pub fn pathTagsSize(self: @This()) u32 {
        return self.path_tags_size;
    }

    pub fn segmentDataSize(self: @This()) u32 {
        return self.path_tags_size * @sizeOf(CubicBezierF32);
    }

    pub fn offsetsSize(self: @This()) u32 {
        return self.pathTagsSize() * 8;
    }

    pub fn linesSize(self: @This()) u32 {
        return self.lines_size;
    }
};

pub const Buffers = struct {
    sizes: BufferSizes,

    path_offsets: []u32,
    path_tags: []PathTag,
    path_monoids: []PathMonoid,
    segment_data: []u8,
    offsets: []u32,
    bumps: []std.atomic.Value(u32),
    lines: []LineF32,

    pub fn create(allocator: Allocator, sizes: BufferSizes) !@This() {
        const bumps = try allocator.alloc(
            std.atomic.Value(u32),
            sizes.bumpsSize(),
        );

        for (bumps) |*bump| {
            bump.raw = 0;
        }

        return @This(){
            .sizes = sizes,
            .path_offsets = try allocator.alloc(
                u32,
                sizes.pathsSize() + 2,
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
            .offsets = try allocator.alloc(
                u32,
                sizes.offsetsSize() + 2,
            ),
            .bumps = bumps,
            .lines = try allocator.alloc(
                LineF32,
                sizes.linesSize(),
            ),
        };
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.path_offsets);
        allocator.free(self.path_tags);
        allocator.free(self.path_monoids);
        allocator.free(self.segment_data);
        allocator.free(self.offsets);
        allocator.free(self.bumps);
        allocator.free(self.lines);
    }
};

pub const PathsIterator = RangeU32.ChunkIterator;

pub const PathSegmentsIterator = struct {
    path_indices: RangeU32,
    path_offsets: []const u32,
    chunk_size: u32,
    index: u32 = 0,

    pub fn next(self: *@This()) ?RangeU32 {
        if (self.index >= self.path_indices.end) {
            return null;
        }

        const start_path_offset = self.path_offsets[self.index + 2 - 1];
        var end_path_offset: u32 = start_path_offset;

        while (self.index < self.path_indices.end) {
            const next_end_path_offset: u32 = self.path_offsets[self.index + 2];

            if (next_end_path_offset - start_path_offset > self.chunk_size) {
                if (end_path_offset == start_path_offset) {
                    @panic("path has too many segments");
                }
                break;
            }

            end_path_offset = next_end_path_offset;
            self.index += 1;
        }

        return RangeU32.create(start_path_offset, end_path_offset);
    }
};

// pub const PathMonoidExpander = struct {
//     encoding: *const Encoding,
//     buffers: *const Buffers,
//     debug_flags: *const DebugFlags,
//     path_index: u32 = 0,

//     pub fn next(self: *@This()) ?State {
//         if (self.path_index >= self.encoding.path_offsets.len) {
//             return null;
//         }

//         const path_index = self.path_index;
//         const start_segment_offset = if (self.path_index > 0) self.encoding.path_offsets[self.path_index - 1] else 0;
//         var end_segment_offset = start_segment_offset;

//         while (true) {
//             if (self.path_index >= self.encoding.path_offsets.len) {
//                 break;
//             }

//             const next_end_segment_offset = self.encoding.path_offsets[self.path_index];

//             if (next_end_segment_offset - start_segment_offset > self.buffers.sizes.pathMonoidsSize()) {
//                 break;
//             }

//             end_segment_offset = next_end_segment_offset;
//             self.path_index += 1;
//         }

//         const segment_size = end_segment_offset - start_segment_offset;
//         if (segment_size == 0) {
//             self.path_index = @intCast(self.encoding.path_offsets.len);
//             return null;
//         }

//         const path_tags = self.encoding.path_tags[start_segment_offset..end_segment_offset];
//         const path_monoids = self.buffers.path_monoids[1 .. 1 + segment_size];

//         var next_path_monoid = if (path_index == 0) PathMonoid{} else self.buffers.path_monoids[0];
//         for (path_tags, path_monoids) |path_tag, *path_monoid| {
//             next_path_monoid = next_path_monoid.combine(PathMonoid.createTag(path_tag));
//             path_monoid.* = next_path_monoid.calculate(path_tag);
//         }
//         self.buffers.path_monoids[0] = next_path_monoid;

//         if (self.debug_flags.expand_monoids) {
//             std.debug.print("============ Path Monoids ============\n", .{});
//             for (path_tags, path_monoids) |path_tag, path_monoid| {
//                 std.debug.print("{}\n", .{path_monoid});
//                 const data = self.encoding.segment_data[path_monoid.segment_offset .. path_monoid.segment_offset + path_tag.segment.size()];
//                 const points = std.mem.bytesAsSlice(PointF32, data);
//                 std.debug.print("Points: {any}\n", .{points});
//                 std.debug.print("------------\n", .{});
//             }
//             std.debug.print("======================================\n", .{});
//         }

//         return State{
//             .path_offset = self.path_index,
//             .segment_range = RangeU32.create(
//                 start_segment_offset,
//                 end_segment_offset,
//             ),
//             .path_tags = path_tags,
//             .path_monoids = path_monoids,
//         };
//     }

//     pub const State = struct {
//         path_offset: u32,
//         segment_range: RangeU32,
//         path_tags: []const PathTag,
//         path_monoids: []const PathMonoid,
//     };
// };

// pub const LineCalculator = struct {
//     kernel_config: KernelConfig,
//     encoding: *const Encoding,
//     buffers: *const Buffers,
//     debug_flags: *const DebugFlags,
//     path_tags: []const PathTag,
//     path_monoids: []const PathMonoid,
//     segment_index: u32 = 0,

//     pub fn calculate(self: *@This()) State {
//         const line_allocator = kernel_module.LineAllocator;
//         const offsets = self.buffers.offsets[2 .. 2 + self.path_tags.len * 2];
//         line_allocator.flatten(
//             self.kernel_config,
//             self.path_tags,
//             self.path_monoids,
//             self.encoding.styles,
//             self.encoding.transforms,
//             self.encoding.segment_data,
//             offsets,
//         );

//         var offset_sum: u32 = 0;
//         for (offsets) |*offset| {
//             offset_sum += offset.*;
//             offset.* = offset_sum;
//         }

//         if (self.debug_flags.calculate_lines) {
//             std.debug.print("============ Line Offsets ============\n", .{});
//             for (self.path_monoids, 0..) |path_monoid, segment_index| {
//                 std.debug.print("Path({})\n", .{path_monoid.path_index});
//                 const fill_offset = offsets[segment_index];
//                 const stroke_offset = offsets[self.path_tags.len + segment_index];
//                 std.debug.print("FillOffset({}), StrokeOffset({})\n", .{
//                     fill_offset,
//                     stroke_offset,
//                 });
//                 std.debug.print("------------\n", .{});
//             }
//             std.debug.print("======================================\n", .{});
//         }

//         return State{
//             .offsets = offsets,
//         };
//     }

//     pub fn chunkSize(self: @This()) u32 {
//         return self.buffers.sizes.offsetsSize() / 2;
//     }

//     pub const State = struct {
//         offsets: []const u32,
//     };
// };

// pub const Flattener = struct {
//     kernel_config: KernelConfig,
//     encoding: *const Encoding,
//     buffers: *const Buffers,
//     debug_flags: *const DebugFlags,
//     path_offset: u32 = 0,
//     path_tags: []const PathTag,
//     path_monoids: []const PathMonoid,
//     offsets: []const u32,
//     path_index: u32 = 0,

//     pub fn flatten(self: *@This()) ?State {
//         const path_index = self.path_index + self.path_offset;
//         if (path_index >= self.encoding.paths.len) {
//             return null;
//         }

//         const segment_offset = if (self.path_index > 0) self.encoding.path_offsets[self.path_index - 1] else 0;
//         const start_path_segment_offset = if (path_index > 0) self.encoding.path_offsets[path_index - 1] - segment_offset;
//         const start_fill_offset = self.offsets[start_path_segment_offset];
//         const start_stroke_offset = self.offsets[self.path_tags.len + start_path_segment_offset];
//         var end_fill_offset = start_fill_offset;
//         var end_stroke_offset = start_stroke_offset;
//         var fill_lines: u32 = 0;
//         var stroke_lines: u32 = 0;

//         var next_path_index = path_index;
//         while (true) {
//             if (next_path_index > self.encoding.path_offsets.len) {
//                 break;
//             }

//             const next_path_segment_offset = self.encoding.path_offsets[next_path_index] - segment_offset;
//             const next_end_fill_offset = self.offsets[next_path_segment_offset];
//             const next_end_stroke_offset = self.offsets[self.path_tags.len + next_path_segment_offset];
//             const next_fill_lines = next_end_fill_offset - start_fill_offset;
//             const next_stroke_lines = next_end_stroke_offset - start_stroke_offset;

//             if (next_fill_lines + next_stroke_lines > self.buffers.lines.len) {
//                 break;
//             }

//             end_fill_offset = next_end_fill_offset;
//             end_stroke_offset = next_end_stroke_offset;
//             fill_lines = next_fill_lines;
//             stroke_lines = next_stroke_lines;

//             next_path_index += 1;
//         }

//         const start_path_index = self.path_index;
//         const end_path_index = start_path_index + (next_path_index - path_index);
//         self.path_index += next_path_index - path_index;
//         if (fill_lines == 0 and stroke_lines == 0) {
//             return;
//         }

//         return null;
//     }

//     pub const State = struct {
//         lines: []const LineF32,
//     };
// };
