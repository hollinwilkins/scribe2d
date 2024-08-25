const std = @import("std");
const core = @import("../../core/root.zig");
const encoding_module = @import("../encoding.zig");
const kernel_module = @import("./kernel.zig");
const msaa_module = @import("../msaa.zig");
const Allocator = std.mem.Allocator;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
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
            .bumps = try allocator.alloc(
                std.atomic.Value(u32),
                config.buffer_sizes.bumpsSize(),
            ),
            .lines = try allocator.alloc(
                LineF32,
                config.buffer_sizes.linesSize(),
            ),
        };
        for (buffers.bumps) |*bump| {
            bump.raw = 0;
        }

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
    pub const DEFAULT_LINES_SIZE: u32 = 60;
    pub const DEFAULT_PATH_MONOIDS_SIZE: u32 = 60;
    pub const DEFAULT_PATHS_SIZE: u32 = 10;

    paths_size: u32 = DEFAULT_PATHS_SIZE,
    path_monoids_size: u32 = DEFAULT_PATH_MONOIDS_SIZE,
    lines_size: u32 = DEFAULT_LINES_SIZE,

    pub fn bumpsSize(self: @This()) u32 {
        return self.paths_size * 2;
    }

    pub fn pathMonoidsSize(self: @This()) u32 {
        return self.path_monoids_size;
    }

    pub fn offsetsSize(self: @This()) u32 {
        return self.pathMonoidsSize() * 2;
    }

    pub fn linesSize(self: @This()) u32 {
        return self.lines_size;
    }
};

pub const Buffers = struct {
    sizes: BufferSizes,
    path_monoids: []PathMonoid,
    offsets: []u32,
    bumps: []std.atomic.Value(u32),
    lines: []LineF32,
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
            .path_offset = self.path_index,
            .segment_range = RangeU32.create(
                start_segment_offset,
                end_segment_offset,
            ),
            .path_tags = path_tags,
            .path_monoids = path_monoids,
        };
    }

    pub const State = struct {
        path_offset: u32,
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
