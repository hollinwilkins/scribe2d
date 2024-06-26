const language = @import("./language.zig");
const face = @import("./face.zig");
pub const GlyphPen = @import("./GlyphPen.zig");

pub const Face = face.Face;
pub const Language = language.Language;

pub const Error = error{
    InvalidFace,
    InvaidFont,
    InvalidTable,
    InvalidOutline,
    MaxDepthExceeded,
};

pub const GlyphId = u16;
