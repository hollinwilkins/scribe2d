const std = @import("std");
const core = @import("../core/root.zig");
const PointF32 = core.PointF32;
const PointI32 = core.PointI32;
const RectF32 = core.RectF32;
const RangeU32 = core.RangeU32;
const DimensionsF32 = core.DimensionsF32;

pub const Intersection = struct {
    t: f32,
    point: PointF32,
};

pub const Shape = struct {
    curve_offsets: RangeU32,
};

pub const Curve = struct {
    end_curve: bool,
    curve_fn: CurveFn,

    pub fn applyT(self: Curve, t: f32) PointF32 {
        return self.curve_fn.applyT(t);
    }

    pub fn isEndCurve(self: Curve) bool {
        return self.end_curve;
    }

    pub fn getBounds(self: Curve) RectF32 {
        return self.curve_fn.getBounds();
    }

    pub fn invertY(self: Curve) Curve {
        return Curve{
            .end_curve = self.end_curve,
            .curve_fn = self.curve_fn.invertY(),
        };
    }

    pub fn scale(self: Curve, dimensions: DimensionsF32) Curve {
        return Curve{
            .end_curve = self.end_curve,
            .curve_fn = self.curve_fn.scale(dimensions),
        };
    }

    pub fn intersectHorizontalLine(self: Curve, line: Line, result: *[3]Intersection) []const Intersection {
        return self.curve_fn.intersectHorizontalLine(line, result);
    }

    pub fn intersectVerticalLine(self: Curve, line: Line, result: *[3]Intersection) []const Intersection {
        return self.curve_fn.intersectVerticalLine(line, result);
    }

    pub fn monotonicCuts(self: Curve, result: *[2]Intersection) []const Intersection {
        return self.curve_fn.monotonicCuts(result);
    }
};

pub const CurveFn = union(enum) {
    line: Line,
    quadratic_bezier: QuadraticBezier,

    pub fn applyT(self: CurveFn, t: f32) PointF32 {
        switch (self) {
            .line => |*l| return l.applyT(t),
            .quadratic_bezier => |*qb| return qb.applyT(t),
        }
    }

    pub fn getBounds(self: CurveFn) RectF32 {
        switch (self) {
            .line => |*line| return line.getBounds(),
            .quadratic_bezier => |*qb| return qb.getBounds(),
        }
    }

    pub fn invertY(self: CurveFn) CurveFn {
        switch (self) {
            .line => |*l| return CurveFn{
                .line = l.invertY(),
            },
            .quadratic_bezier => |*qb| return CurveFn{
                .quadratic_bezier = qb.invertY(),
            },
        }
    }

    pub fn scale(self: CurveFn, dimensions: DimensionsF32) CurveFn {
        switch (self) {
            .line => |*l| return CurveFn{
                .line = l.scale(dimensions),
            },
            .quadratic_bezier => |*qb| return CurveFn{
                .quadratic_bezier = qb.scale(dimensions),
            },
        }
    }

    pub fn intersectHorizontalLine(self: CurveFn, line: Line, result: *[3]Intersection) []const Intersection {
        switch (self) {
            .line => |*l| {
                if (l.intersectHorizontalLine(line)) |intersection| {
                    result[0] = intersection;
                    return result[0..1];
                } else {
                    return &.{};
                }
            },
            .quadratic_bezier => |*qb| {
                return qb.intersectHorizontalLine(line, @ptrCast(result));
            },
        }
    }

    pub fn intersectVerticalLine(self: CurveFn, line: Line, result: *[3]Intersection) []const Intersection {
        switch (self) {
            .line => |*l| {
                if (l.intersectVerticalLine(line)) |intersection| {
                    result[0] = intersection;
                    return result[0..1];
                } else {
                    return &.{};
                }
            },
            .quadratic_bezier => |*qb| {
                return qb.intersectVerticalLine(line, @ptrCast(result));
            },
        }
    }

    // not actually making fns monotonic, just making sure they don't curve
    // back on themselves when cut at these intersections
    pub fn monotonicCuts(self: CurveFn, result: *[2]Intersection) []const Intersection {
        switch (self) {
            .line => |_| {
                return &.{};
            },
            .quadratic_bezier => |*qb| {
                if (qb.getMonotonicCut()) |intersection| {
                    result[0] = intersection;
                    return result[0..1];
                } else {
                    return &.{};
                }
            },
        }
    }
};

pub const Line = struct {
    start: PointF32,
    end: PointF32,

    pub fn create(start: PointF32, end: PointF32) Line {
        return Line{
            .start = start,
            .end = end,
        };
    }

    pub fn isVertical(self: Line) bool {
        return self.start.x == self.end.x;
    }

    pub fn isHorizontal(self: Line) bool {
        return self.start.y == self.end.y;
    }

    pub fn applyT(self: Line, t: f32) PointF32 {
        return self.start.add(
            (self.end.sub(self.start).mul(
                PointF32{
                    .x = t,
                    .y = t,
                },
            )),
        );
    }

    pub fn scale(self: Line, dimensions: DimensionsF32) Line {
        return Line{
            .start = self.start.mul(PointF32{
                .x = dimensions.width,
                .y = dimensions.height,
            }),
            .end = self.end.mul(PointF32{
                .x = dimensions.width,
                .y = dimensions.height,
            }),
        };
    }

    pub fn invert(self: Line) Line {
        return Line{
            .start = self.start.invert(),
            .end = self.end.invert(),
        };
    }

    pub fn invertX(self: Line) Line {
        return Line{
            .start = self.start.invertX(),
            .end = self.end.invertX(),
        };
    }

    pub fn invertY(self: Line) Line {
        return Line{
            .start = self.start.invertY(),
            .end = self.end.invertY(),
        };
    }

    pub fn getBounds(self: Line) RectF32 {
        return RectF32.create(self.start, self.end);
    }

    pub fn getDeltaY(self: Line) f32 {
        return self.end.y - self.start.y;
    }

    pub fn getDeltaX(self: Line) f32 {
        return self.end.x - self.start.x;
    }

    pub fn getNormal(self: Line) PointF32 {
        return PointF32{
            .x = -self.getDeltaY(),
            .y = self.getDeltaX(),
        };
    }

    pub fn getSlope(self: Line) f32 {
        return self.getDeltaY() / self.getDeltaX();
    }

    pub fn intersectHorizontalLine(self: Line, other: Line) ?Intersection {
        const delta_y = self.getDeltaY();
        if (delta_y == 0.0) {
            return null;
        }

        const t = -(self.start.y - other.start.y) / delta_y;
        if (t < 0.0 or t > 1.0) {
            return null;
        }

        const point = self.applyT(t);
        if (point.x < other.start.x or point.x > other.end.x) {
            return null;
        }

        return Intersection{
            .t = t,
            .point = PointF32{
                .x = point.x,
                .y = other.start.y,
            },
        };
    }

    pub fn intersectVerticalLine(self: Line, other: Line) ?Intersection {
        const delta_x = self.getDeltaX();
        if (delta_x == 0.0) {
            return null;
        }

        const t = -(self.start.x - other.start.x) / delta_x;
        if (t < 0.0 or t > 1.0) {
            return null;
        }

        const point = self.applyT(t);
        if (point.y < other.start.y or point.y > other.end.y) {
            return null;
        }

        return Intersection{
            .t = t,
            .point = PointF32{
                .x = other.start.x,
                .y = point.y,
            },
        };
    }
};

pub const QuadraticBezier = struct {
    start: PointF32,
    end: PointF32,
    control: PointF32,

    pub fn create(start: PointF32, control: PointF32, end: PointF32) QuadraticBezier {
        return QuadraticBezier{
            .start = start,
            .end = end,
            .control = control,
        };
    }

    pub fn applyT(self: QuadraticBezier, t: f32) PointF32 {
        return self.start.lerp(
            self.control,
            t,
        ).lerp(
            self.control.lerp(self.end, t),
            t,
        );
    }

    // cut point ensures two segments of the curve that don't curve back on itself
    pub fn getMonotonicCut(self: QuadraticBezier) ?Intersection {
        const t = 0.5;
        return Intersection{
            .t = t,
            .point = self.applyT(t),
        };
    }

    pub fn getBounds(self: QuadraticBezier) RectF32 {
        return RectF32.create(self.start, self.end).extendBy(self.control);
    }

    pub fn scale(self: QuadraticBezier, dimensions: DimensionsF32) QuadraticBezier {
        return QuadraticBezier{
            .start = self.start.mul(PointF32{
                .x = dimensions.width,
                .y = dimensions.height,
            }),
            .end = self.end.mul(PointF32{
                .x = dimensions.width,
                .y = dimensions.height,
            }),
            .control = self.control.mul(PointF32{
                .x = dimensions.width,
                .y = dimensions.height,
            }),
        };
    }

    pub fn invert(self: QuadraticBezier) QuadraticBezier {
        return QuadraticBezier{
            .start = self.start.invert(),
            .end = self.end.invert(),
            .control = self.control.invert(),
        };
    }

    pub fn invertX(self: QuadraticBezier) QuadraticBezier {
        return QuadraticBezier{
            .start = self.start.invertX(),
            .end = self.end.invertX(),
            .control = self.control.invertX(),
        };
    }

    pub fn invertY(self: QuadraticBezier) QuadraticBezier {
        return QuadraticBezier{
            .start = self.start.invertY(),
            .end = self.end.invertY(),
            .control = self.control.invertY(),
        };
    }

    pub fn intersectHorizontalLine(self: QuadraticBezier, line: Line, result: *[2]Intersection) []const Intersection {
        std.debug.assert(line.isHorizontal());
        const a = self.start.y - (2.0 * self.control.y) + self.end.y;
        const b = 2.0 * (self.control.y - self.start.y);
        const c = self.start.y - line.start.y;
        var roots_result: [2]f32 = [_]f32{undefined} ** 2;
        const roots = getRoots(a, b, c, &roots_result);

        var intersections: usize = 0;
        for (roots) |root| {
            if (root < 0.0 or root > 1.0) {
                continue;
            }

            const point = self.applyT(root);
            if (point.x < line.start.x or point.x > line.end.x) {
                continue;
            }

            result[intersections] = Intersection{ .t = root, .point = PointF32{
                .x = point.x,
                .y = line.start.y,
            } };
            intersections += 1;
        }

        return result[0..intersections];
    }

    pub fn intersectVerticalLine(self: QuadraticBezier, line: Line, result: *[2]Intersection) []const Intersection {
        std.debug.assert(line.isVertical());
        const a = self.start.x - (2.0 * self.control.x) + self.end.x;
        const b = 2.0 * (self.control.x - self.start.x);
        const c = self.start.x - line.start.x;
        var roots_result: [2]f32 = [_]f32{undefined} ** 2;
        const roots = getRoots(a, b, c, &roots_result);

        var intersections: usize = 0;
        for (roots) |root| {
            if (root < 0.0 or root > 1.0) {
                continue;
            }

            const point = self.applyT(root);
            if (point.y < line.start.y or point.y > line.end.y) {
                continue;
            }

            result[intersections] = Intersection{ .t = root, .point = PointF32{
                .x = line.start.x,
                .y = point.y,
            } };
            intersections += 1;
        }

        return result[0..intersections];
    }

    pub fn getRoots(a: f32, b: f32, c: f32, result: *[2]f32) []const f32 {
        if (a == 0) {
            result[0] = -c / b;
            return result[0..1];
        }

        const d = b * b - 4 * a * c;

        if (d > 0) {
            const e = std.math.sqrt(d);
            const two_a = 2.0 * a;
            result[0] = (-b + e) / two_a;
            result[1] = (-b - e) / two_a;
            return result[0..2];
        } else if (d == 0) {
            result[0] = -b / (2.0 * a);
            return result[0..1];
        }

        return &.{};
    }
};

test "horizontal line intersections" {
    const test_util = @import("./test_util.zig");

    const line1 = Line.create(PointF32{
        .x = 0.0,
        .y = 0.0,
    }, PointF32{
        .x = 10.0,
        .y = 10.0,
    });
    const line2 = Line.create(PointF32{
        .x = -3.452342,
        .y = -22.5924872,
    }, PointF32{
        .x = 22.124312,
        .y = 13.242313739,
    });
    const line3 = Line.create(PointF32{
        .x = -3.145,
        .y = -66.7420,
    }, PointF32{
        .x = 10.0,
        .y = -66.7420,
    });
    const line4 = Line.create(PointF32{
        .x = 420.69,
        .y = -10.0,
    }, PointF32{ .x = 420.69, .y = 10.0 });

    const intersection1 = line1.intersectHorizontalLine(Line.create(PointF32{
        .x = 0.0,
        .y = 2.0,
    }, PointF32{
        .x = 10.0,
        .y = 2.0,
    })).?;
    const intersection2 = line1.intersectHorizontalLine(Line.create(PointF32{
        .x = 10.0,
        .y = 2.0,
    }, PointF32{
        .x = 20.0,
        .y = 2.0,
    }));
    const intersection3 = line1.intersectHorizontalLine(Line.create(PointF32{
        .x = 0.0,
        .y = 0.0,
    }, PointF32{
        .x = 20.0,
        .y = 0.0,
    })).?;
    const intersection4 = line2.intersectHorizontalLine(Line.create(PointF32{
        .x = -20.0,
        .y = 2.78324,
    }, PointF32{
        .x = 20.0,
        .y = 2.78324,
    })).?;
    const intersection5 = line3.intersectHorizontalLine(line3);
    const intersection6 = line3.intersectHorizontalLine(Line.create(PointF32{
        .x = -99.0,
        .y = 33.4,
    }, PointF32{
        .x = 99.0,
        .y = 33.4,
    }));
    const intersection7 = line4.intersectHorizontalLine(Line.create(PointF32{
        .x = 400.0,
        .y = 1.337,
    }, PointF32{
        .x = 460.0,
        .y = 1.337,
    })).?;
    const intersection8 = line4.intersectHorizontalLine(Line.create(PointF32{
        .x = 400.0,
        .y = -1000.0,
    }, PointF32{
        .x = 460.0,
        .y = -1000.0,
    }));
    const intersection9 = line4.intersectHorizontalLine(Line.create(PointF32{
        .x = 400.0,
        .y = -1000.0,
    }, PointF32{
        .x = 460.0,
        .y = -1000.0,
    }));

    try test_util.expectApproxEqlIntersectionTX(Intersection{
        .t = 0.2,
        .point = PointF32{
            .x = 2.0,
            .y = 2.0,
        },
    }, intersection1, test_util.DEFAULT_TOLERANCE, test_util.DEFAULT_TOLERANCE);
    try std.testing.expectEqual(null, intersection2);
    try test_util.expectApproxEqlIntersectionTX(Intersection{
        .t = 0.0,
        .point = PointF32{
            .x = 0.0,
            .y = 0.0,
        },
    }, intersection3, test_util.DEFAULT_TOLERANCE, test_util.DEFAULT_TOLERANCE);
    try test_util.expectApproxEqlIntersectionTX(Intersection{ .t = 7.0813084e-1, .point = PointF32{
        .x = 1.4659274e1,
        .y = 2.78324,
    } }, intersection4, test_util.DEFAULT_TOLERANCE, test_util.DEFAULT_TOLERANCE);
    try std.testing.expectEqual(intersection5, null);
    try std.testing.expectEqual(intersection6, null);
    try test_util.expectApproxEqlIntersectionTX(Intersection{ .t = 5.6685e-1, .point = PointF32{
        .x = 420.69,
        .y = 1.337,
    } }, intersection7, test_util.DEFAULT_TOLERANCE, 0.0);
    try std.testing.expectEqual(null, intersection8);
    try std.testing.expectEqual(null, intersection9);
}

test "vertical line intersections" {
    const test_util = @import("./test_util.zig");

    const line1 = Line.create(PointF32{
        .x = 0.0,
        .y = 0.0,
    }, PointF32{
        .x = 10.0,
        .y = 10.0,
    });
    const line2 = Line.create(PointF32{
        .x = -22.5924872,
        .y = -3.452342,
    }, PointF32{
        .x = 13.242313739,
        .y = 22.124312,
    });
    const line3 = Line.create(PointF32{
        .x = -66.7420,
        .y = -3.145,
    }, PointF32{
        .x = -66.7420,
        .y = 10.0,
    });
    const line4 = Line.create(PointF32{
        .x = -10.0,
        .y = 420.69,
    }, PointF32{
        .x = 10.0,
        .y = 420.69,
    });

    const intersection1 = line1.intersectVerticalLine(Line.create(PointF32{
        .x = 2.0,
        .y = 0.0,
    }, PointF32{
        .x = 2.0,
        .y = 10.0,
    })).?;
    const intersection2 = line1.intersectVerticalLine(Line.create(PointF32{
        .x = 2.0,
        .y = 10.0,
    }, PointF32{
        .x = 2.0,
        .y = 20.0,
    }));
    const intersection3 = line1.intersectVerticalLine(Line.create(PointF32{
        .x = 0.0,
        .y = 0.0,
    }, PointF32{
        .x = 0.0,
        .y = 20.0,
    })).?;
    const intersection4 = line2.intersectVerticalLine(Line.create(PointF32{
        .x = 2.78324,
        .y = -20.0,
    }, PointF32{
        .x = 2.78324,
        .y = 20.0,
    })).?;
    const intersection5 = line3.intersectVerticalLine(line3);
    const intersection6 = line3.intersectVerticalLine(Line.create(PointF32{
        .x = 33.4,
        .y = -99.0,
    }, PointF32{
        .x = 33.4,
        .y = 99.0,
    }));
    const intersection7 = line4.intersectVerticalLine(Line.create(PointF32{
        .x = 1.337,
        .y = 400.0,
    }, PointF32{
        .x = 1.337,
        .y = 460.0,
    })).?;
    const intersection8 = line4.intersectVerticalLine(Line.create(PointF32{
        .x = -1000.0,
        .y = 400.0,
    }, PointF32{
        .x = -1000.0,
        .y = 460.0,
    }));
    const intersection9 = line4.intersectVerticalLine(Line.create(PointF32{
        .x = -1000.0,
        .y = 400.0,
    }, PointF32{
        .x = -1000.0,
        .y = 460.0,
    }));

    try test_util.expectApproxEqlIntersectionTY(Intersection{
        .t = 0.2,
        .point = PointF32{
            .x = 2.0,
            .y = 2.0,
        },
    }, intersection1, test_util.DEFAULT_TOLERANCE, test_util.DEFAULT_TOLERANCE);
    try std.testing.expectEqual(null, intersection2);
    try test_util.expectApproxEqlIntersectionTY(Intersection{
        .t = 0.0,
        .point = PointF32{
            .x = 0.0,
            .y = 0.0,
        },
    }, intersection3, test_util.DEFAULT_TOLERANCE, test_util.DEFAULT_TOLERANCE);
    try test_util.expectApproxEqlIntersectionTY(Intersection{ .t = 7.0813084e-1, .point = PointF32{
        .x = 2.78324,
        .y = 1.4659274e1,
    } }, intersection4, test_util.DEFAULT_TOLERANCE, test_util.DEFAULT_TOLERANCE);
    try std.testing.expectEqual(intersection5, null);
    try std.testing.expectEqual(intersection6, null);
    try test_util.expectApproxEqlIntersectionTY(Intersection{ .t = 5.6685e-1, .point = PointF32{
        .x = 1.337,
        .y = 420.69,
    } }, intersection7, test_util.DEFAULT_TOLERANCE, 0.0);
    try std.testing.expectEqual(null, intersection8);
    try std.testing.expectEqual(null, intersection9);
}

test "horizontal line x quadratic bezier intersections" {
    const test_util = @import("./test_util.zig");
    const bezier1 = QuadraticBezier.create(PointF32{
        .x = 0.0,
        .y = 0.0,
    }, PointF32{
        .x = 0.5,
        .y = 0.5,
    }, PointF32{
        .x = 1.0,
        .y = 0.0,
    });
    const bezier2 = QuadraticBezier.create(PointF32{
        .x = 3.1415926535,
        .y = 5.241417893,
    }, PointF32{
        .x = 1.3242938,
        .y = -5.471239,
    }, PointF32{
        .x = -13.2223,
        .y = -8.7432498,
    });

    var intersections_result: [2]Intersection = [_]Intersection{undefined} ** 2;

    const intersections1 = bezier1.intersectHorizontalLine(Line.create(PointF32{ .x = -1.0, .y = 0.25 }, PointF32{
        .x = 2.0,
        .y = 0.25,
    }), &intersections_result);

    try test_util.expectApproxEqlIntersectionTX(Intersection{ .t = 0.5, .point = PointF32{
        .x = 0.5,
        .y = 0.25,
    } }, intersections1[0], test_util.DEFAULT_TOLERANCE, 0.0);

    const intersections2 = bezier1.intersectHorizontalLine(Line.create(PointF32{ .x = -1.0, .y = 0.25 }, PointF32{
        .x = -0.5,
        .y = 0.25,
    }), &intersections_result);
    try std.testing.expectEqual(0, intersections2.len);

    const intersections4 = bezier1.intersectHorizontalLine(Line.create(PointF32{
        .x = -1.0,
        .y = 0.0,
    }, PointF32{
        .x = 2.0,
        .y = 0.0,
    }), &intersections_result);

    try test_util.expectApproxEqlIntersectionTX(Intersection{ .t = 0.0, .point = PointF32{
        .x = 0.0,
        .y = 0.0,
    } }, intersections4[0], test_util.DEFAULT_TOLERANCE, 0.0);
    try test_util.expectApproxEqlIntersectionTX(Intersection{ .t = 1.0, .point = PointF32{
        .x = 1.0,
        .y = 0.0,
    } }, intersections4[1], test_util.DEFAULT_TOLERANCE, 0.0);

    const intersections5 = bezier2.intersectHorizontalLine(Line.create(PointF32{
        .x = -15.0,
        .y = -3.89213,
    }, PointF32{
        .x = 40.0,
        .y = -3.89213,
    }), &intersections_result);
    try test_util.expectApproxEqlIntersectionTX(Intersection{ .t = 5.2031684e-1, .point = PointF32{
        .x = -2.1957464e0,
        .y = -3.89213,
    } }, intersections5[0], test_util.DEFAULT_TOLERANCE, 0.0);
}

test "vertical line x quadratic bezier intersections" {
    const test_util = @import("./test_util.zig");
    const bezier1 = QuadraticBezier.create(PointF32{
        .x = 0.0,
        .y = 0.0,
    }, PointF32{
        .x = 0.5,
        .y = 0.5,
    }, PointF32{
        .x = 0.0,
        .y = 1.0,
    });
    const bezier2 = QuadraticBezier.create(PointF32{
        .x = 5.241417893,
        .y = 3.1415926535,
    }, PointF32{
        .x = -5.471239,
        .y = 1.3242938,
    }, PointF32{
        .x = -8.7432498,
        .y = -13.2223,
    });

    var intersections_result: [2]Intersection = [_]Intersection{undefined} ** 2;

    const intersections1 = bezier1.intersectVerticalLine(Line.create(PointF32{
        .x = 0.25,
        .y = -1.0,
    }, PointF32{
        .x = 0.25,
        .y = 2.0,
    }), &intersections_result);

    try test_util.expectApproxEqlIntersectionTY(Intersection{ .t = 0.5, .point = PointF32{
        .x = 0.25,
        .y = 0.5,
    } }, intersections1[0], test_util.DEFAULT_TOLERANCE, 0.0);

    const intersections2 = bezier1.intersectVerticalLine(Line.create(PointF32{
        .x = 0.25,
        .y = -1.0,
    }, PointF32{
        .x = 0.25,
        .y = -0.5,
    }), &intersections_result);
    try std.testing.expectEqual(0, intersections2.len);

    const intersections4 = bezier1.intersectVerticalLine(Line.create(PointF32{
        .x = 0.0,
        .y = -1.0,
    }, PointF32{
        .x = 0.0,
        .y = 2.0,
    }), &intersections_result);

    try test_util.expectApproxEqlIntersectionTY(Intersection{ .t = 0.0, .point = PointF32{
        .x = 0.0,
        .y = 0.0,
    } }, intersections4[0], test_util.DEFAULT_TOLERANCE, 0.0);
    try test_util.expectApproxEqlIntersectionTY(Intersection{ .t = 1.0, .point = PointF32{
        .x = 0.0,
        .y = 1.0,
    } }, intersections4[1], test_util.DEFAULT_TOLERANCE, 0.0);

    const intersections5 = bezier2.intersectVerticalLine(Line.create(PointF32{
        .x = -3.89213,
        .y = -15.0,
    }, PointF32{
        .x = -3.89213,
        .y = 40.0,
    }), &intersections_result);
    try test_util.expectApproxEqlIntersectionTY(Intersection{ .t = 5.2031684e-1, .point = PointF32{
        .x = -3.89213,
        .y = -2.1957464e0,
    } }, intersections5[0], test_util.DEFAULT_TOLERANCE, 0.0);
}
