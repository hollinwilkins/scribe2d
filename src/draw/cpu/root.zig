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
const PipelineState = kernel_module.PipelineState;
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
        // initialize data
        self.buffers.path_monoids[0] = PathMonoid{};
        self.buffers.path_monoids[1] = PathMonoid{};

        var segment_iterator = SegmentIterator{
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
                self.buffers.path_tags,
                &pipeline_state,
                self.buffers.path_monoids,
            );

            if (self.config.debug_flags.expand_monoids) {
                self.debugExpandMonoids(pipeline_state);
            }
        }
    }

    pub fn debugExpandMonoids(self: @This(), pipeline_state: PipelineState) void {
        const segments_size = pipeline_state.segment_indices.size();
        std.debug.print("============ Path Monoids ============\n", .{});
        for (self.buffers.path_tags[0..segments_size], self.buffers.path_monoids[2 .. 2 + segments_size]) |path_tag, path_monoid| {
            std.debug.print("{}\n", .{path_monoid});
            const data = self.buffers.segment_data[path_monoid.segment_offset .. path_monoid.segment_offset + path_tag.segment.size()];
            const points = std.mem.bytesAsSlice(PointF32, data);
            std.debug.print("Points: {any}\n", .{points});
            std.debug.print("------------\n", .{});
        }
        std.debug.print("======================================\n", .{});
    }
};

pub const DebugFlags = struct {
    expand_monoids: bool = false,
    calculate_lines: bool = false,
};

pub const BufferSizes = struct {
    pub const DEFAULT_PATHS_SIZE: u32 = 10;
    pub const DEFAULT_LINES_SIZE: u32 = 60;
    pub const DEFAULT_SEGMENTS_SIZE: u32 = 10;
    pub const DEFAULT_SEGMENT_DATA_SIZE: u32 = DEFAULT_SEGMENTS_SIZE * @sizeOf(CubicBezierF32);

    paths_size: u32 = DEFAULT_PATHS_SIZE,
    styles_size: u32 = DEFAULT_PATHS_SIZE,
    transforms_size: u32 = DEFAULT_PATHS_SIZE,
    path_tags_size: u32 = DEFAULT_SEGMENTS_SIZE,
    segment_data_size: u32 = DEFAULT_SEGMENT_DATA_SIZE,
    lines_size: u32 = DEFAULT_LINES_SIZE,

    pub fn create(encoding: Encoding) @This() {
        return @This(){
            .paths_size = encoding.paths,
            .styles_size = @intCast(encoding.styles.len),
            .transforms_size = @intCast(encoding.transforms.len),
            .path_tags_size = @intCast(encoding.path_tags.len),
            .segment_data_size = @intCast(encoding.segment_data.len),
        };
    }

    pub fn pathsSize(self: @This()) u32 {
        return self.paths_size;
    }

    pub fn stylesSize(self: @This()) u32 {
        return self.styles_size;
    }

    pub fn transformsSize(self: @This()) u32 {
        return self.transforms_size;
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
};

pub const Buffers = struct {
    path_offsets: []u32,
    styles: []Style,
    transforms: []TransformF32.Affine,
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
            .path_offsets = try allocator.alloc(
                u32,
                sizes.pathsSize(),
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
        allocator.free(self.styles);
        allocator.free(self.transforms);
        allocator.free(self.path_tags);
        allocator.free(self.path_monoids);
        allocator.free(self.segment_data);
        allocator.free(self.offsets);
        allocator.free(self.bumps);
        allocator.free(self.lines);
    }
};

pub const SegmentIterator = struct {
    path_offsets: []const u32,
    chunk_size: u32,
    path_tags: u32,
    index: u32 = 0,

    pub fn next(self: *@This()) ?RangeU32 {
        if (self.index >= self.path_offsets.len) {
            return null;
        }

        const start_segment_offset = self.path_offsets[self.index];
        var end_segment_offset = start_segment_offset;

        var end_index = self.index;
        while (end_index < self.path_offsets.len) {
            const next_index = end_index + 1;
            const next_segment_offset = if (next_index >= self.path_offsets.len) self.path_tags else self.path_offsets[next_index];

            if (next_segment_offset - start_segment_offset > self.chunk_size) {
                break;
            }

            end_segment_offset = next_segment_offset;
            end_index += 1;
        }

        if (self.index == end_index) {
            self.index = @intCast(self.path_offsets.len);
            return null;
        }

        self.index = end_index;

        return RangeU32.create(start_segment_offset, end_segment_offset);
    }
};
