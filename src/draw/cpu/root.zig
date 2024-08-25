const std = @import("std");
const core = @import("../../core/root.zig");
const encoding_module = @import("../encoding.zig");
const kernel_module = @import("../kernel.zig");
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
                config.buffer_sizes.path_monoids_size + 1,
            ),
            .offsets = try allocator.alloc(
                u32,
                config.buffer_sizes.path_monoids_size * 2 + 2,
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
            .debug_flags = self.config.debug_flags,
        };

        while (path_monoid_expander.next()) |path_monoid_state| {
            _ = path_monoid_state;
        }
    }
};

pub const DebugFlags = struct {
    expand_monoids: bool = false,
};

pub const BufferSizes = struct {
    pub const DEFAULT_PATH_MONOIDS_SIZE: u32 = 1024 * 1024;

    path_monoids_size: u32 = DEFAULT_PATH_MONOIDS_SIZE,
};

pub const Buffers = struct {
    sizes: BufferSizes,
    path_monoids: []PathMonoid,
    offsets: []u32,
};

pub const PathMonoidExpander = struct {
    encoding: *const Encoding,
    buffers: *const Buffers,
    debug_flags: DebugFlags,
    path_index: u32 = 0,

    pub fn next(self: *@This()) ?State {
        if (self.path_index >= self.encoding.path_offsets.len) {
            return null;
        }

        const path_index = self.path_index;
        const start_segment_offset = if (self.path_index > 0) self.encoding.path_offsets[self.path_index - 1] else 0;
        var end_segment_offset = start_segment_offset;

        while (true) {
            self.path_index += 1;
            if (self.path_index >= self.encoding.path_offsets.len) {
                break;
            }

            const next_end_segment_offset = self.encoding.path_offsets[self.path_index];
            if (next_end_segment_offset - start_segment_offset > self.buffers.sizes.path_monoids_size) {
                break;
            }

            end_segment_offset = next_end_segment_offset;
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
        self.buffers.path_monoids[0] = path_monoids[path_monoids.len - 1];

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

// pub const LineCalculator = struct {
//     path_monoid_expander: *PathMonoidExpander,
//     path_tags: []const PathTag,
//     path_monoids: []const PathMonoid,

//     pub const State = struct {
//         path_tags: []const PathTag,
//         path_monoids: []const PathMonoid,
//         fill_offsets: []const u32,
//         stroke_offsets: []const u32,
//     };
// };
