const std = @import("std");
const core = @import("../core/root.zig");
const PointF32 = core.PointF32;
const RectF32 = core.RectF32;

pub const Curve = union(enum) {
    line: Line,
    quadratic_bezier: QuadraticBezier,

    pub fn getBounds(self: Curve) RectF32 {
        switch (self) {
            .line => |*line| return line.getBounds(),
            .quadratic_bezier => |*qb| return qb.getBounds(),
        }
    }

    pub fn intersectLine(self: Curve, line: Line, result: *[3]PointF32) []PointF32 {
        switch (self) {
            .line => |*l| return l.intersectLine(line, result),
            .quadratic_bezier => |*qb| return qb.intersectLine(line, result),
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

    // Java code from: https://www.geeksforgeeks.org/program-for-point-of-intersection-of-two-lines/
    pub fn intersectLine(self: Line, line: Line) ?PointF32 {
        // Line AB represented as a1x + b1y = c1
        const a1 = self.getDeltaY();
        // double a1 = B.y - A.y;
        const b1 = -self.getDeltaX();
        // double b1 = A.x - B.x;
        const c1 = a1 * (self.start.x) + b1 * (self.start.y);
        // double c1 = a1*(A.x) + b1*(A.y);

        // Line CD represented as a2x + b2y = c2
        const a2 = line.getDeltaY();
        // double a2 = D.y - C.y;
        const b2 = -line.getDeltaX();
        // double b2 = C.x - D.x;
        const c2 = a2 * (line.start.x) + b2 * (line.start.y);
        // double c2 = a2*(C.x)+ b2*(C.y);

        // double determinant = a1*b2 - a2*b1;
        const determinant = a1 * b2 - a2 * b1;

        if (determinant == 0) {
            // The lines are parallel. This is simplified
            return null;
        } else {
            return PointF32{
                .x = (b2 * c1 - b1 * c2) / determinant,
                .y = (a1 * c2 - a2 * c1) / determinant,
            };
            //     double x = (b2*c1 - b1*c2)/determinant;
            //     double y = (a1*c2 - a2*c1)/determinant;
            //     return new Point(x, y);
        }
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

    pub fn getBounds(self: QuadraticBezier) RectF32 {
        return RectF32.create(self.start, self.end).extendBy(self.control);
    }

    // code from: https://github.com/w8r/bezier-intersect
    pub fn getRoots(c0: f32, c1: f32, c2: f32, result: *[2]f32) []const f32 {
        const a = c0;
        //   var a = C2;
        const b = c1 / a;
        //   var b = C1 / a;
        const c = c2 / a;
        //   var c = C0 / a;
        const d = b * b - 4 * c;
        //   var d = b * b - 4 * c;

        if (d > 0) {
            //   if (d > 0) {
            const e = std.math.sqrt(d);
            //     var e = Math.sqrt(d);
            result[0] = 0.5 * (-b + e);
            //     results.push(0.5 * (-b + e));
            result[1] = 0.5 * (-b - e);
            //     results.push(0.5 * (-b - e));
            return result;
        } else if (d == 0) {
            //   } else if (d === 0) {
            result[0] = 0.5 * -b;
            //     results.push( 0.5 * -b);
            return result[0..1];
        }
        //   }

        return result[0..0];
        //   return results;
    }

    //     export function quadBezierLine(
    //   p1x, p1y, p2x, p2y, p3x, p3y,
    //   a1x, a1y, a2x, a2y, result) {

    // p1 = a, p2 = c, p3 = b
    // code from: https://github.com/w8r/bezier-intersect
    // code from: https://stackoverflow.com/questions/27664298/calculating-intersection-point-of-quadratic-bezier-curve
    pub fn intersectLine(self: QuadraticBezier, line: Line, result: *[2]PointF32) []const PointF32 {
        const bounds = line.getBounds();
        // inverse line normal
        //   var normal={
        //     x: a1.y-a2.y,
        //     y: a2.x-a1.x,
        //   }
        const normal = line.getNormal();

        //   // Q-coefficients
        //   var c2={
        //     x: p1.x + p2.x*-2 + p3.x,
        //     y: p1.y + p2.y*-2 + p3.y
        //   }
        const p2 = self.start.add(
            self.control.mul(PointF32{
                .x = -2.0,
                .y = -2.0,
            }),
        ).add(self.end);

        //   var c1={
        //     x: p1.x*-2 + p2.x*2,
        //     y: p1.y*-2 + p2.y*2,
        //   }
        const p1 = self.start.mul(
            PointF32{
                .x = -2.0,
                .y = -2.0,
            },
        ).add(self.control.mul(
            PointF32{
                .x = 2.0,
                .y = 2.0,
            },
        ));

        //   var c0={
        //     x: p1.x,
        //     y: p1.y
        //   }
        const p0 = self.start;

        //   // Transform to line
        //   var coefficient=a1.x*a2.y-a2.x*a1.y;
        const coefficient = line.start.x * line.end.y - line.end.x * line.start.y;
        //   var a=normal.x*c2.x + normal.y*c2.y;
        const c0 = normal.x * p2.x + normal.y * p2.y;
        //   var b=(normal.x*c1.x + normal.y*c1.y)/a;
        const c1 = normal.x * p1.x + normal.y * p1.y;
        //   var c=(normal.x*c0.x + normal.y*c0.y + coefficient)/a;
        const c2 = normal.x * p0.x + normal.y * p0.y + coefficient;

        //   // Transform cubic coefficients to line's coordinate system
        //   // and find roots of cubic
        var roots_result: [2]f32 = [_]f32{undefined} ** 2;
        const roots = getRoots(
            c0,
            c1,
            c2,
            &roots_result,
        );

        var ri: usize = 0;
        // Any roots in closed interval [0,1] are intersections on Bezier, but
        // might not be on the line segment.
        // Find intersections and calculate point coordinates
        //   for (var i = 0; i < roots.length; i++) {
        for (roots) |t| {
            //     var t = roots[i];
            //     if ( 0 <= t && t <= 1 ) { // We're within the Bezier curve
            if (0 <= t and t <= 1) { // we're within the Bezier curve
                //       // Find point on Bezier
                //       // lerp: x1 + (x2 - x1) * t
                //       var p4x = p1x + (p2x - p1x) * t;
                //       var p4y = p1y + (p2y - p1y) * t;
                //       var p5x = p2x + (p3x - p2x) * t;
                //       var p5y = p2y + (p3y - p2y) * t;
                //       // candidate
                //       var p6x = p4x + (p5x - p4x) * t;
                //       var p6y = p4y + (p5y - p4y) * t;
                const candidate = self.start.lerp(
                    self.control,
                    t,
                ).lerp(
                    self.control.lerp(self.end, t),
                    t,
                );

                //       // See if point is on line segment
                //       // Had to make special cases for vertical and horizontal lines due
                //       // to slight errors in calculation of p6
                //       if (a1x === a2x) {
                if (line.isVertical()) {
                    //         if (miny <= p6y && p6y <= maxy) {
                    if (bounds.min.y <= candidate.y and candidate.y <= bounds.max.y) {
                        //           if (result) result.push(p6x, p6y);
                        //           else        return 1;
                        result[ri] = candidate;
                        ri += 1;
                    }
                    //         }
                    //       } else if (a1y === a2y) {
                } else if (line.isHorizontal()) {
                    //         if (minx <= p6x && p6x <= maxx) {
                    if (bounds.min.x <= candidate.x and candidate.x <= bounds.max.x) {
                        //           if (result) result.push(p6x, p6y);
                        //           else        return 1;
                        result[ri] = candidate;
                        ri += 1;
                    }
                    //         }
                } else if (bounds.containsPoint(candidate)) {
                    result[ri] = candidate;
                    ri += 1;
                }
                //       // gte: (x1 >= x2 && y1 >= y2)
                //       // lte: (x1 <= x2 && y1 <= y2)
                //       } else if (p6x >= minx && p6y >= miny && p6x <= maxx && p6y <= maxy) {
                //         if (result) result.push(p6x, p6y);
                //         else        return 1;
                //       }
                //     }
                //   }
            }
        }

        return result[0..ri];
        //   return result ? result.length / 2 : 0;
    }
};

test "intersect line with line" {
    const line1 = Line.create(PointF32{
        .x = 0.0,
        .y = 0.0,
    }, PointF32{
        .x = 1.0,
        .y = 1.0,
    });
    const line2 = Line.create(PointF32{
        .x = 0.0,
        .y = 1.0,
    }, PointF32{ .x = 1.0, .y = 0.0 });

    const intersection = line1.intersectLine(line2);
    std.debug.print("\n================ Line x Line\n", .{});
    if (intersection) |point| {
        std.debug.print("Intersection at: {}\n", .{point});
    } else {
        std.debug.print("No intersection\n", .{});
    }
    std.debug.print("================\n", .{});
}

test "intersect quadratic bezier with line" {
    const bezier = QuadraticBezier.create(PointF32{
        .x = 0.0,
        .y = 0.0,
    }, PointF32{
        .x = 0.5,
        .y = 1.0,
    }, PointF32{
        .x = 1.0,
        .y = 0.0,
    });
    const line = Line.create(PointF32{
        .x = 0.0,
        .y = 0.25,
    }, PointF32{
        .x = 1.0,
        .y = 0.25,
    });

    var intersections_result: [2]PointF32 = [_]PointF32{undefined} ** 2;
    const intersections = bezier.intersectLine(line, &intersections_result);

    std.debug.print("\n================ Bezier x Line\n", .{});
    for (intersections) |point| {
        std.debug.print("Intersect at point: {}\n", .{point});
    }
    std.debug.print("================\n", .{});
}
