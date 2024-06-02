const std = @import("std");
const path_module = @import("./path.zig");
const core = @import("../core/root.zig");
const texture = @import("./texture.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const UnmanagedTexture = texture.UnmanagedTexture;
const TextureViewRgba = texture.TextureViewRgba;
const Path = path_module.Path;
const PointF32 = core.PointF32;
const PointU32 = core.PointU32;
const RectU32 = core.RectU32;

const BoundaryFragment = struct {
};

pub const Pen = struct {
    pub fn drawToTextureViewRgba(self: *Pen, allocator: Allocator, path: Path, view: *TextureViewRgba) !void {
        _ = self;
        _ = allocator;
        _ = path;
        _ = view;
        return;
    }

    pub fn createBoundarySegments(allocator: Allocator, path: Path, view: *TextureViewRgba) {
        for (path.segments()) |segment| {
        }
    }
};
