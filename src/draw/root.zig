pub const Error = error{
    DimensionOverflow,
};

const path = @import("./path.zig");
const raster = @import("./raster.zig");
const texture = @import("./texture.zig");
const curve = @import("./curve.zig");
const pen = @import("./pen.zig");

pub const Pen = pen.Pen;
pub const Path = path.Path;
pub const PathBuilder = path.PathBuilder;
pub const Segment = path.Segment;

pub const Rasterizer = raster.Rasterizer;

pub const Color = texture.Color;
pub const Texture = texture.Texture;
pub const TextureFormat = texture.TextureFormat;
pub const TextureCodec = texture.TextureCodec;
pub const ColorCodec = texture.ColorCodec;

pub const Line = curve.Line;
pub const QuadraticBezier = curve.QuadraticBezier;
