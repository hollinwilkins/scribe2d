const std = @import("std");
const core = @import("../core/root.zig");
const curve = @import("./curve.zig");
const Intersection = curve.Intersection;
const PointF32 = core.PointF32;

pub const DEFAULT_TOLERANCE: f32 = 0.00001;

pub fn expectApproxEqlPointXY(expected: PointF32, actual: PointF32, x_tol: f32, y_tol: f32) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, x_tol);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, y_tol);
}

pub fn expectApproxEqlIntersectionTXY(expected: Intersection, actual: Intersection, t_tol: f32, x_tol: f32, y_tol: f32) !void {
    try std.testing.expectApproxEqAbs(expected.t, actual.t, t_tol);
    try expectApproxEqlPointXY(expected.point, actual.point, x_tol, y_tol);
}

pub fn expectApproxEqlIntersectionTX(expected: Intersection, actual: Intersection, t_tol: f32, x_tol: f32) !void {
    try expectApproxEqlIntersectionTXY(expected, actual, t_tol, x_tol, 0.0);
}

pub fn expectApproxEqlIntersectionTY(expected: Intersection, actual: Intersection, t_tol: f32, y_tol: f32) !void {
    try expectApproxEqlIntersectionTXY(expected, actual, t_tol, 0.0, y_tol);
}
