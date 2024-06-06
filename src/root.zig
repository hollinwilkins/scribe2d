pub const core = @import("./core/root.zig");
pub const draw = @import("./draw/root.zig");
pub const text = @import("./text/root.zig");

test {
    const std = @import("std");
    std.testing.refAllDecls(draw.QuadraticBezier);
    std.testing.refAllDecls(@import("./draw/msaa.zig").HalfPlanesU16);
    std.testing.refAllDecls(@import("./draw/raster.zig").Raster);
}
