const std = @import("std");
const core = @import("../core/root.zig");
const curve = @import("./curve.zig");
const raster = @import("./raster.zig");
const Intersection = curve.Intersection;
const PathIntersection = raster.PathIntersection;
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

pub fn expectPathIntersectionsContains(expected: PathIntersection, intersections: []const PathIntersection, tol: f32) !void {
    std.sort.binarySearch(Intersection, expected, intersections, tol, compareIntersection);
}

fn compareIntersection(tol: f32, key: PathIntersection, mid_item: PathIntersection) std.math.Order {
    if (key.path_id < mid_item.path_id) {
        return .lt;
    } else if (key.path_id > mid_item.path_id) {
        return .gt;
    } else if (key.curve_index < mid_item.curve_index) {
        return .lt;
    } else if (key.curve_index > mid_item.curve_index) {
        return .gt;
    } else if (key.intersection.t < mid_item.intersection.t) {
        return .lt;
    } else if (key.intersection.t > mid_item.intersection.t) {
        return .gt;
    } else {
        const t_eq = std.math.approxEqAbs(f32, key.intersection.t, mid_item.intersection.t, tol);

        if (t_eq) {
            return .eq;
        } else if (key.intersection.t < mid_item.intersection.t) {
            return .lt;
        } else {
            return .gt;
        }
    }
}
