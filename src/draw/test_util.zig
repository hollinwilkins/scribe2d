const std = @import("std");
const core = @import("../core/root.zig");
const curve = @import("./curve.zig");
const soup_raster = @import("./soup_raster.zig");
const Intersection = curve.Intersection;
const PathIntersection = soup_raster.PathIntersection;
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

pub fn expectPathIntersectionsContains(expected: PathIntersection, intersections: []const PathIntersection, t_tol: f32) !void {
    const index = std.sort.binarySearch(
        PathIntersection,
        expected,
        intersections,
        t_tol,
        compareIntersection,
    );

    if (index == null) {
        return error.TestExpectedError;
    }
}

fn compareIntersection(t_tol: f32, key: PathIntersection, mid_item: PathIntersection) std.math.Order {
    if (key.shape_index < mid_item.shape_index) {
        return .lt;
    } else if (key.shape_index > mid_item.shape_index) {
        return .gt;
    } else if (key.curve_index < mid_item.curve_index) {
        return .lt;
    } else if (key.curve_index > mid_item.curve_index) {
        return .gt;
    } else if (std.math.approxEqAbs(f32, key.intersection.t, mid_item.intersection.t, t_tol) and key.is_end == mid_item.is_end) {
        return .eq;
    } else if (key.intersection.t < mid_item.intersection.t) {
        return .lt;
    } else if (key.intersection.t > mid_item.intersection.t) {
        return .gt;
    } else if (!key.is_end and mid_item.is_end) {
        return .lt;
    } else if (key.is_end and !mid_item.is_end) {
        return .gt;
    } else {
        return .eq;
    }
}
