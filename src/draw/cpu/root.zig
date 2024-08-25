const std = @import("std");
const core = @import("../../core/root.zig");
const encoding_module = @import("../encoding.zig");
const kernel_module = @import("../kernel.zig");
const msaa_module = @import("../msaa.zig");
const Allocator = std.mem.Allocator;
const PointF32 = core.PointF32;
const Encoding = encoding_module.Encoding;
const PathTag = encoding_module.PathTag;
const PathMonoid = encoding_module.PathMonoid;
const KernelConfig = kernel_module.KernelConfig;
const HalfPlanesU16 = msaa_module.HalfPlanesU16;

pub const CpuRasterizer = struct {
    pub const DebugFlags = struct {
        expand_monoids: bool = false,
    };

    pub const Config = struct {
        pub const DEFAULT_PATH_MONOIDS_SIZE: u32 = 1024 * 1024;

        kernel_config: KernelConfig = KernelConfig.DEFAULT,
        debug_flags: DebugFlags = DebugFlags{},
        path_monoids_size: u32 = DEFAULT_PATH_MONOIDS_SIZE,
    };

    allocator: Allocator,
    half_planes: *const HalfPlanesU16,
    config: Config,
    path_monoids: []PathMonoid,

    pub fn init(
        allocator: Allocator,
        half_planes: *const HalfPlanesU16,
        config: Config,
    ) !@This() {
        return @This(){
            .allocator = allocator,
            .half_planes = half_planes,
            .config = config,
            .path_monoids = try allocator.alloc(PathMonoid, config.path_monoids_size + 1),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.path_monoids);
    }

    pub fn rasterize(self: *@This(), encoding: Encoding) void {
        var state = EncodingState.create(encoding);
        self.rasterizeState(&state);
    }

    pub fn rasterizeState(self: *@This(), state: *EncodingState) void {
        while (self.expandPathMonoids(state)) {
            if (self.config.debug_flags.expand_monoids) {
                std.debug.print("============ Path Monoids ============\n", .{});
                for (state.path_tags, state.path_monoids) |path_tag, path_monoid| {
                    std.debug.print("{}\n", .{path_monoid});
                    const data = state.encoding.segment_data[path_monoid.segment_offset .. path_monoid.segment_offset + path_tag.segment.size()];
                    const points = std.mem.bytesAsSlice(PointF32, data);
                    std.debug.print("Points: {any}\n", .{points});
                    std.debug.print("------------\n", .{});
                }
                std.debug.print("======================================\n", .{});
            }
        }
    }

    pub fn expandPathMonoids(self: *@This(), state: *EncodingState) bool {
        const path_monoid_size = @min(self.config.path_monoids_size, state.encoding.path_tags.len - state.path_monoid_offset);
        const path_tags = state.encoding.path_tags[state.path_monoid_offset .. state.path_monoid_offset + path_monoid_size];
        const path_monoids = self.path_monoids[1 .. 1 + path_monoid_size];

        var next_path_monoid = if (state.path_monoid_offset == 0) PathMonoid{} else self.path_monoids[0];
        for (path_tags, path_monoids) |path_tag, *path_monoid| {
            next_path_monoid = next_path_monoid.combine(PathMonoid.createTag(path_tag));
            path_monoid.* = next_path_monoid.calculate(path_tag);
        }

        state.path_monoid_offset += path_monoid_size;

        state.path_tags = path_tags;
        state.path_monoids = path_monoids;
        return path_monoids.len > 0;
    }
};

pub const EncodingState = struct {
    encoding: Encoding,

    path_monoid_offset: u32 = 0,

    path_tags: []const PathTag = &.{},
    path_monoids: []const PathMonoid = &.{},

    pub fn create(encoding: Encoding) @This() {
        return @This(){
            .encoding = encoding,
        };
    }
};
