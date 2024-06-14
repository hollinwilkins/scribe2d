const core = @import("../core/root.zig");
const PointF32 = core.PointF32;

pub const CubicPoints = struct {
    point0: PointF32 = PointF32{},
    point1: PointF32 = PointF32{},
    point2: PointF32 = PointF32{},
    point3: PointF32 = PointF32{},
};
