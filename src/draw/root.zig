pub const Error = error{
    DimensionOverflow,
};

const path = @import("./path.zig");
const geometry = @import("./geometry.zig");

pub const Outliner = @import("./Outliner.zig");
pub const PathOutliner = path.PathOutliner;
pub const Path = path.Path;
pub const Segment = path.Segment;

pub const Point = geometry.Point;
pub const PointF32 = geometry.PointF32;

pub const Rect = geometry.Rect;
pub const RectF32 = geometry.RectF32;
pub const RectI16 = geometry.RectI16;
