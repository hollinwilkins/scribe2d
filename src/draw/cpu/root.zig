const std = @import("std");
const core = @import("../../core/root.zig");
const encoding_module = @import("../encoding.zig");
const kernel_module = @import("./kernel.zig");
const msaa_module = @import("../msaa.zig");
const Allocator = std.mem.Allocator;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const TransformF32 = core.TransformF32;
const CubicBezierF32 = core.CubicBezierF32;
const LineF32 = core.LineF32;
const Encoding = encoding_module.Encoding;
const PathTag = encoding_module.PathTag;
const PathMonoid = encoding_module.PathMonoid;
const Style = encoding_module.Style;
const KernelConfig = kernel_module.KernelConfig;
pub const Config = kernel_module.Config;
pub const BufferSizes = kernel_module.BufferSizes;
const Buffers = kernel_module.Buffers;
const PipelineState = kernel_module.PipelineState;
const HalfPlanesU16 = msaa_module.HalfPlanesU16;

pub const CpuRasterizer = struct {
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
        // initialize data
        self.buffers.path_monoids[self.config.buffer_sizes.pathTagsSize()] = PathMonoid{};
        self.buffers.path_monoids[self.config.buffer_sizes.pathTagsSize() + 1] = PathMonoid{};

        var path_iterator = RangeU32.create(
            0,
            @intCast(encoding.path_offsets.len),
        ).chunkIterator(self.config.buffer_sizes.pathsSize());

        while (path_iterator.next()) |path_indices| {
            var segment_iterator = SegmentIterator{
                .path_indices = path_indices,
                .path_offsets = encoding.path_offsets,
                .chunk_size = self.config.buffer_sizes.pathTagsSize(),
                .path_tags = @intCast(encoding.path_tags.len),
            };

            while (segment_iterator.next()) |segment_indices| {
                var pipeline_state = PipelineState{
                    .segment_indices = segment_indices,
                };
                std.debug.print("SegmentIndices({})\n", .{segment_indices});

                // load path tags
                std.mem.copyForwards(
                    PathTag,
                    self.buffers.path_tags,
                    encoding.path_tags[segment_indices.start..segment_indices.end],
                );

                // expand path monoids
                kernel_module.PathMonoidExpander.expand(
                    self.config,
                    self.buffers.path_tags,
                    &pipeline_state,
                    self.buffers.path_monoids,
                );

                if (self.config.debug_flags.expand_monoids) {
                    self.debugExpandMonoids(pipeline_state);
                }
            }
        }
    }

    pub fn debugExpandMonoids(self: @This(), pipeline_state: PipelineState) void {
        const segments_size = pipeline_state.segment_indices.size();
        std.debug.print("============ Path Monoids ============\n", .{});
        for (self.buffers.path_tags[0..segments_size], self.buffers.path_monoids[0..segments_size]) |path_tag, path_monoid| {
            std.debug.print("{}\n", .{path_monoid});
            const data = self.buffers.segment_data[path_monoid.segment_offset .. path_monoid.segment_offset + path_tag.segment.size()];
            const points = std.mem.bytesAsSlice(PointF32, data);
            std.debug.print("Points: {any}\n", .{points});
            std.debug.print("------------\n", .{});
        }
        std.debug.print("======================================\n", .{});
    }
};

pub const SegmentIterator = struct {
    path_indices: RangeU32,
    path_offsets: []const u32,
    chunk_size: u32,
    path_tags: u32,
    index: u32 = 0,

    pub fn next(self: *@This()) ?RangeU32 {
        const path_index = self.index + self.path_indices.start;
        if (path_index >= self.path_offsets.len) {
            return null;
        }

        const start_segment_offset = self.path_offsets[path_index];
        var end_segment_offset = start_segment_offset;

        var index_offset: u32 = 0;
        while (self.index + index_offset < self.path_indices.end) {
            const next_index = path_index + index_offset + 1;
            const next_segment_offset = if (next_index >= self.path_offsets.len) self.path_tags else self.path_offsets[next_index];

            if (next_segment_offset - start_segment_offset > self.chunk_size) {
                break;
            }

            end_segment_offset = next_segment_offset;
            index_offset += 1;
        }

        if (index_offset == 0) {
            self.index = @intCast(self.path_indices.end);
            return null;
        }

        self.index += index_offset;

        return RangeU32.create(start_segment_offset, end_segment_offset);
    }
};
