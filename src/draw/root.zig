pub const Error = error{
    DimensionOverflow,
};

const path = @import("./path.zig");
const pen = @import("./pen.zig");
const texture = @import("./texture.zig");

pub const PathOutliner = path.PathOutliner;
pub const Path = path.Path;
pub const Segment = path.Segment;

pub const Pen = pen.Pen;

pub const UnmanagedTextureRgba = texture.UnmanagedTextureRgba;
pub const UnmanagedTextureMonotone = texture.UnmanagedTextureMonotone;