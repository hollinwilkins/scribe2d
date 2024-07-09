pub const Error = error{
    DimensionOverflow,
};

const shape = @import("./shape.zig");
const texture = @import("./texture.zig");
const msaa = @import("./msaa.zig");
const kernel = @import("./kernel.zig");
const encoding = @import("./encoding.zig");
const encoding_raster = @import("./encoding_raster.zig");

pub const Shape = shape.Shape;
pub const ShapeBuilder = shape.ShapeBuilder;

pub const Colors = texture.Colors;
pub const Color = texture.Color;
pub const ColorU8 = texture.ColorU8;
pub const ColorF32 = texture.ColorF32;
pub const Texture = texture.Texture;
pub const TextureUnmanaged = texture.TextureUnmanaged;
pub const TextureFormat = texture.TextureFormat;
pub const TextureCodec = texture.TextureCodec;
pub const ColorCodec = texture.ColorCodec;

pub const HalfPlanesU16 = msaa.HalfPlanesU16;

pub const KernelConfig = kernel.KernelConfig;

pub const Encoder = encoding.Encoder;
pub const Style = encoding.Style;

pub const CpuRasterizer = encoding_raster.CpuRasterizer;
