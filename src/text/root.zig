pub const Error = error{
    InvalidFace,
    InvaidFont,
    InvalidTable,
    InvalidOutline,
    MaxDepthExceeded,
};

pub const GlyphId = u16;
pub const Range = struct {
    start: usize,
    end: usize,
};
