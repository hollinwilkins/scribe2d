pub const Error = error{
    DimensionOverflow,
};

const path = @import("./path.zig");
const raster = @import("./raster.zig");
const texture = @import("./texture.zig");
const curve = @import("./curve.zig");
const pen = @import("./pen.zig");
const color = @import("./color.zig");

pub const Pen = pen.Pen;
pub const Path = path.Path;
pub const Segment = path.Segment;

pub const Raster = raster.Raster;

pub const UnmanagedTextureRgba = texture.UnmanagedTextureRgba;
pub const UnmanagedTextureMonotone = texture.UnmanagedTextureMonotone;

pub const Line = curve.Line;
pub const QuadraticBezier = curve.QuadraticBezier;

pub const Rgba = color.Rgba;
pub const Monotone = color.Monotone;
