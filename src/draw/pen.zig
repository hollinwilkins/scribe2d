const std = @import("std");
const path_module = @import("./path.zig");
const raster = @import("./raster.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Rasterizer = raster.Rasterizer;

pub const Pen = struct {
    rasterizer: *const Rasterizer,
};
