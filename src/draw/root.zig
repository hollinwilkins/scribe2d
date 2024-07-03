pub const Error = error{
    DimensionOverflow,
};

const shape = @import("./shape.zig");
const flatten = @import("./flatten.zig");
const scene = @import("./scene.zig");
const soup = @import("./soup.zig");
const estimate = @import("./estimate.zig");
const raster = @import("./raster.zig");
const pen = @import("./pen.zig");
const texture = @import("./texture.zig");
const curve = @import("./curve.zig");
const msaa = @import("./msaa.zig");
const kernel = @import("./kernel.zig");
pub const encoding = @import("./encoding.zig");

pub const Shape = shape.Shape;
pub const ShapeBuilder = shape.ShapeBuilder;

pub const Soup = soup.Soup;
pub const Estimator = estimate.Estimator;
pub const Rasterizer = raster.Rasterizer;

pub const SoupPen = pen.Pen;
pub const Style = pen.Style;

pub const Color = texture.Color;
pub const Texture = texture.Texture;
pub const TextureUnmanaged = texture.TextureUnmanaged;
pub const TextureFormat = texture.TextureFormat;
pub const TextureCodec = texture.TextureCodec;
pub const ColorCodec = texture.ColorCodec;

pub const Arc = curve.Arc;
pub const Line = curve.Line;
pub const QuadraticBezier = curve.QuadraticBezier;

pub const PathFlattener = flatten.Flattener;

pub const Scene = scene.Scene;

pub const HalfPlanesU16 = msaa.HalfPlanesU16;

pub const KernelConfig = kernel.KernelConfig;

pub const Encoder = encoding.Encoder;
