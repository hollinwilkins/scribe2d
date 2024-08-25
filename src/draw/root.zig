pub const Error = error{
    DimensionOverflow,
};

const texture = @import("./texture.zig");
const msaa = @import("./msaa.zig");
const kernel = @import("./kernel.zig");
const encoding = @import("./encoding.zig");
const encoding_raster = @import("./encoding_raster.zig");
pub const cpu = @import("./cpu/root.zig");

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

pub const PathEncoder = encoding.PathEncoder;
pub const PathEncoderF32 = encoding.PathEncoderF32;
pub const PathEncoderI16 = encoding.PathEncoderI16;
pub const Encoder = encoding.Encoder;
pub const Style = encoding.Style;

pub const CpuRasterizer = encoding_raster.CpuRasterizer;
