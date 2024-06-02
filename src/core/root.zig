const geometry = @import("./geometry.zig");
const range = @import("./range.zig");

pub const Point = geometry.Point;
pub const PointF32 = geometry.PointF32;
pub const PointI16 = geometry.PointI16;
pub const PointU32 = geometry.PointU32;
pub const PointI32 = geometry.PointI32;

pub const Rect = geometry.Rect;
pub const RectF32 = geometry.RectF32;
pub const RectI16 = geometry.RectI16;
pub const RectU32 = geometry.RectU32;

pub const Dimensions = geometry.Dimensions;
pub const DimensionsF32 = geometry.DimensionsF32;
pub const DimensionsU32 = geometry.DimensionsU32;

pub const Range = range.Range;
pub const RangeU32 = range.RangeU32;
pub const RangeI32 = range.RangeI32;
pub const RangeF32 = range.RangeF32;
