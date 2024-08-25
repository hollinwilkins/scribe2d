const std = @import("std");
const core = @import("../../core/root.zig");
const encoding_module = @import("../encoding.zig");
const kernel_module = @import("./kernel.zig");
const msaa_module = @import("../msaa.zig");
const Allocator = std.mem.Allocator;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
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
        const buffers = Buffers{
            .sizes = config.buffer_sizes,
            .path_monoids = try allocator.alloc(
                PathMonoid,
                config.buffer_sizes.pathMonoidsSize() + 1,
            ),
            .offsets = try allocator.alloc(
                u32,
                config.buffer_sizes.offsetsSize() + 2,
            ),
        };

        return @This(){
            .allocator = allocator,
            .half_planes = half_planes,
            .config = config,
            .buffers = buffers,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.buffers.path_monoids);
        self.allocator.free(self.buffers.offsets);
    }

    pub fn rasterize(self: *@This(), encoding: Encoding) void {
        var path_monoid_expander = PathMonoidExpander{
            .encoding = &encoding,
            .buffers = &self.buffers,
            .debug_flags = &self.config.debug_flags,
        };

        while (path_monoid_expander.next()) |expansion| {
            var line_calculator = LineCalculator{
                .kernel_config = self.config.kernel_config,
                .buffers = &self.buffers,
                .debug_flags = &self.config.debug_flags,
                .encoding = &encoding,
                .path_tags = expansion.path_tags,
                .path_monoids = expansion.path_monoids,
            };
            const line_offsets = line_calculator.calculate();
            _ = line_offsets;
        }
    }
};

pub const DebugFlags = struct {
    expand_monoids: bool = false,
    calculate_lines: bool = false,
};

pub const BufferSizes = struct {
    pub const DEFAULT_PATH_MONOIDS_SIZE: u32 = 60;

    path_monoids_size: u32 = DEFAULT_PATH_MONOIDS_SIZE,

    pub fn pathMonoidsSize(self: @This()) u32 {
        return self.path_monoids_size;
    }

    pub fn offsetsSize(self: @This()) u32 {
        return self.pathMonoidsSize() * 2;
    }
};

pub const Buffers = struct {
    sizes: BufferSizes,
    path_monoids: []PathMonoid,
    offsets: []u32,
};

pub const PathMonoidExpander = struct {
    encoding: *const Encoding,
    buffers: *const Buffers,
    debug_flags: *const DebugFlags,
    path_index: u32 = 0,

    pub fn next(self: *@This()) ?State {
        if (self.path_index >= self.encoding.path_offsets.len) {
            return null;
        }

        const path_index = self.path_index;
        const start_segment_offset = if (self.path_index > 0) self.encoding.path_offsets[self.path_index - 1] else 0;
        var end_segment_offset = start_segment_offset;

        while (true) {
            if (self.path_index >= self.encoding.path_offsets.len) {
                break;
            }

            const next_end_segment_offset = self.encoding.path_offsets[self.path_index];

            if (next_end_segment_offset - start_segment_offset > self.buffers.sizes.pathMonoidsSize()) {
                break;
            }

            end_segment_offset = next_end_segment_offset;
            self.path_index += 1;
        }

        const segment_size = end_segment_offset - start_segment_offset;
        if (segment_size == 0) {
            self.path_index = @intCast(self.encoding.path_offsets.len);
            return null;
        }

        const path_tags = self.encoding.path_tags[start_segment_offset..end_segment_offset];
        const path_monoids = self.buffers.path_monoids[1 .. 1 + segment_size];

        var next_path_monoid = if (path_index == 0) PathMonoid{} else self.buffers.path_monoids[0];
        for (path_tags, path_monoids) |path_tag, *path_monoid| {
            next_path_monoid = next_path_monoid.combine(PathMonoid.createTag(path_tag));
            path_monoid.* = next_path_monoid.calculate(path_tag);
        }
        self.buffers.path_monoids[0] = next_path_monoid;

        if (self.debug_flags.expand_monoids) {
            std.debug.print("============ Path Monoids ============\n", .{});
            for (path_tags, path_monoids) |path_tag, path_monoid| {
                std.debug.print("{}\n", .{path_monoid});
                const data = self.encoding.segment_data[path_monoid.segment_offset .. path_monoid.segment_offset + path_tag.segment.size()];
                const points = std.mem.bytesAsSlice(PointF32, data);
                std.debug.print("Points: {any}\n", .{points});
                std.debug.print("------------\n", .{});
            }
            std.debug.print("======================================\n", .{});
        }

        return State{
            .segment_range = RangeU32.create(
                start_segment_offset,
                end_segment_offset,
            ),
            .path_tags = path_tags,
            .path_monoids = path_monoids,
        };
    }

    pub const State = struct {
        segment_range: RangeU32,
        path_tags: []const PathTag,
        path_monoids: []const PathMonoid,
    };
};

pub const LineCalculator = struct {
    kernel_config: KernelConfig,
    encoding: *const Encoding,
    buffers: *const Buffers,
    debug_flags: *const DebugFlags,
    path_tags: []const PathTag,
    path_monoids: []const PathMonoid,
    segment_index: u32 = 0,

    pub fn calculate(self: *@This()) State {
        const line_allocator = kernel_module.LineAllocator;
        const offsets = self.buffers.offsets[2 .. 2 + self.path_tags.len * 2];
        line_allocator.flatten(
            self.kernel_config,
            self.path_tags,
            self.path_monoids,
            self.encoding.styles,
            self.encoding.transforms,
            self.encoding.segment_data,
            offsets,
        );

        var offset_sum: u32 = 0;
        for (offsets) |*offset| {
            offset_sum += offset.*;
            offset.* = offset_sum;
        }

        if (self.debug_flags.calculate_lines) {
            std.debug.print("============ Line Offsets ============\n", .{});
            for (self.path_monoids, 0..) |path_monoid, segment_index| {
                std.debug.print("Path({})\n", .{path_monoid.path_index});
                const fill_offset = offsets[segment_index];
                const stroke_offset = offsets[self.path_tags.len + segment_index];
                std.debug.print("FillOffset({}), StrokeOffset({})\n", .{
                    fill_offset,
                    stroke_offset,
                });
                std.debug.print("------------\n", .{});
            }
            std.debug.print("======================================\n", .{});
        }

        return State{
            .offsets = offsets,
        };
    }

    pub fn chunkSize(self: @This()) u32 {
        return self.buffers.sizes.offsetsSize() / 2;
    }

    pub const State = struct {
        offsets: []const u32,
    };
};
