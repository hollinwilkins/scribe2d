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
            // load path offsets
            std.mem.copyForwards(
                u32,
                self.buffers.path_offsets,
                encoding.path_offsets[path_indices.start..path_indices.end],
            );

            var segment_iterator = SegmentIterator{
                .path_indices = path_indices,
                .path_offsets = encoding.path_offsets,
                .chunk_size = self.config.buffer_sizes.pathTagsSize(),
                .path_tags = @intCast(encoding.path_tags.len),
            };

            while (segment_iterator.next()) |segment_indices| {
                var pipeline_state = PipelineState{
                    .path_indices = path_indices,
                    .segment_indices = segment_indices,
                };

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
                    self.buffers.path_offsets,
                    self.buffers.path_monoids,
                );

                // load styles
                if (pipeline_state.style_indices.start >= 0) {
                    const start: u32 = @intCast(pipeline_state.style_indices.start);
                    const end: u32 = @intCast(pipeline_state.style_indices.end);
                    std.mem.copyForwards(
                        Style,
                        self.buffers.styles,
                        encoding.styles[start..end],
                    );
                }

                // load transforms
                if (pipeline_state.transform_indices.start >= 0) {
                    const start: u32 = @intCast(pipeline_state.transform_indices.start);
                    const end: u32 = @intCast(pipeline_state.transform_indices.end);
                    std.mem.copyForwards(
                        TransformF32.Affine,
                        self.buffers.transforms,
                        encoding.transforms[start..end],
                    );
                }

                // load segment data
                std.mem.copyForwards(
                    u8,
                    self.buffers.segment_data,
                    encoding.segment_data[pipeline_state.segment_data_indices.start..pipeline_state.segment_data_indices.end],
                );

                if (self.config.debug_flags.expand_monoids) {
                    self.debugExpandMonoids(pipeline_state);
                }

                kernel_module.LineAllocator.flatten(
                    self.config,
                    self.buffers.path_offsets,
                    self.buffers.path_tags,
                    self.buffers.path_monoids,
                    self.buffers.styles,
                    self.buffers.transforms,
                    self.buffers.segment_data,
                    &pipeline_state,
                    self.buffers.offsets,
                );

                if (self.config.debug_flags.calculate_lines) {
                    self.debugCalculateLines(pipeline_state, encoding);
                }
            }
        }
    }

    pub fn debugExpandMonoids(self: @This(), pipeline_state: PipelineState) void {
        const segments_size = pipeline_state.segment_indices.size();
        std.debug.print("============ Path Monoids ============\n", .{});
        for (self.buffers.path_tags[0..segments_size], self.buffers.path_monoids[0..segments_size]) |path_tag, path_monoid| {
            std.debug.print("{}\n", .{path_monoid});
            const segment_offset = path_monoid.segment_offset - pipeline_state.segment_data_indices.start;
            const data = self.buffers.segment_data[segment_offset .. segment_offset + path_tag.segment.size()];
            const points = std.mem.bytesAsSlice(PointF32, data);
            std.debug.print("Points: {any}\n", .{points});
            std.debug.print("------------\n", .{});
        }
        std.debug.print("======================================\n", .{});
    }

    pub fn debugCalculateLines(self: @This(), pipeline_state: PipelineState, encoding: Encoding) void {
        std.debug.print("============ Line Offsets ============\n", .{});
        for (pipeline_state.path_indices.start..pipeline_state.path_indices.end) |path_index| {
            std.debug.print("Path({})\n", .{path_index});
            const start_segment_offset = encoding.path_offsets[path_index] - pipeline_state.segment_indices.start;
            const end_segment_offset = if (path_index + 1 < encoding.path_offsets.len) encoding.path_offsets[path_index + 1] - pipeline_state.segment_indices.start else pipeline_state.segment_indices.size();

            std.debug.print("LineOffsetSegments({},{})\n", .{
                start_segment_offset,
                end_segment_offset,
            });

            for (start_segment_offset..end_segment_offset) |segment_index| {
                const fill_offset = self.buffers.offsets[segment_index];
                const stroke_offset = self.buffers.offsets[pipeline_state.segment_indices.size() + segment_index];

                std.debug.print("FillOffset({}), StrokeOffset({})\n", .{
                    fill_offset,
                    stroke_offset,
                });
            }
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
        if (path_index >= self.path_indices.end) {
            return null;
        }

        const start_segment_offset = self.path_offsets[path_index];
        var end_segment_offset = start_segment_offset;

        var index_offset: u32 = 0;
        while (path_index + index_offset < self.path_indices.end) {
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
