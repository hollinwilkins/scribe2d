const std = @import("std");
const core = @import("../core/root.zig");
const PointF32 = core.PointF32;
const RectF32 = core.RectF32;

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

    pub fn deltaY(self: Line) f32 {
        return self.end.y - self.start.y;
    }

    pub fn deltaX(self: Line) f32 {
        return self.end.x - self.start.x;
    }

    // Java code from: https://www.geeksforgeeks.org/program-for-point-of-intersection-of-two-lines/
    pub fn intersectLine(self: Line, line: Line) ?PointF32 {
        // Line AB represented as a1x + b1y = c1
        const a1 = self.deltaY();
        // double a1 = B.y - A.y;
        const b1 = -self.deltaX();
        // double b1 = A.x - B.x;
        const c1 = a1 * (self.start.x) + b1 * (self.start.y);
        // double c1 = a1*(A.x) + b1*(A.y);

        // Line CD represented as a2x + b2y = c2
        const a2 = line.deltaY();
        // double a2 = D.y - C.y;
        const b2 = -line.deltaX();
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

    // code from: https://github.com/w8r/bezier-intersect
    pub fn getRoots(c0: f32, c1: f32, c2: f32, result: *[2]f32) []const f32 {
        const a = c2;
        const b = c1 / a;
        const c = c0 / a;
        const d = b * b - 4 * c;

        if (d > 0) {
            const e = std.math.sqrt(d);
            result[0] = 0.5 * (-b + e);
            result[1] = 0.5 * (-b - e);
            return result;
        } else if (d == 0) {
            result[0] = 0.5 * -b;
            return result[0..1];
        }
    }

    //     export function quadBezierLine(
    //   p1x, p1y, p2x, p2y, p3x, p3y,
    //   a1x, a1y, a2x, a2y, result) {

    // p1 = a, p2 = c, p3 = b
    // code from: https://github.com/w8r/bezier-intersect
    pub fn intersectLine(self: QuadraticBezier, line: Line, result: *[2]PointF32) []const PointF32 {

        // var ax, ay, bx, by;                // temporary variables
        //   var c2x, c2y, c1x, c1y, c0x, c0y;  // coefficients of quadratic
        //   var cl;               // c coefficient for normal form of line
        //   var nx, ny;           // normal for normal form of line
        //   // used to determine if point is on line segment
        //   var minx = Math.min(a1x, a2x),
        //       miny = Math.min(a1y, a2y),
        //       maxx = Math.max(a1x, a2x),
        //       maxy = Math.max(a1y, a2y);
        const bounds = RectF32.create(line.start, line.end);

        //   ax = p2x * -2; ay = p2y * -2;
        //   c2x = p1x + ax + p3x;
        //   c2y = p1y + ay + p3y;
        const ax_1 = self.control.x * -2.0;
        const ay_1 = self.control.y * -2.0;
        const c2x = self.start.x + ax_1 + self.end.x;
        const c2y = self.start.y + ay_1 + self.end.y;

        //   ax = p1x * -2; ay = p1y * -2;
        //   bx = p2x * 2;  by = p2y * 2;
        //   c1x = ax + bx;
        //   c1y = ay + by;
        const ax_2 = self.start.x * -2.0;
        const ay_2 = self.start.y * -2.0;
        const bx_2 = self.control.x * 2.0;
        const by_2 = self.control.y * 2.0;
        const c1x = ax_2 + bx_2;
        const c1y = ay_2 + by_2;

        //   c0x = p1x; c0y = p1y; // vec
        const c0x = self.start.x;
        const c0y = self.start.y;

        //   // Convert line to normal form: ax + by + c = 0
        //   // Find normal to line: negative inverse of original line's slope
        //   nx = a1y - a2y; ny = a2x - a1x;
        const nx = line.start.y - line.end.y;
        const ny = line.end.x - line.start.x;

        //   // Determine new c coefficient
        //   cl = a1x * a2y - a2x * a1y;
        const cl = line.start.x * line.end.y - line.end.x * line.start.y;

        //   // Transform cubic coefficients to line's coordinate system
        //   // and find roots of cubic
        //   var roots = getPolynomialRoots(
        //     // dot products => x * x + y * y
        //     nx * c2x + ny * c2y,
        //     nx * c1x + ny * c1y,
        //     nx * c0x + ny * c0y + cl
        //   );
        var roots_result = [2]f32;
        const roots = getRoots(
            nx * c2x + ny * c2y,
            nx * c1x + ny * c1y,
            nx * c0x + ny * c0y + cl,
            &roots_result,
        );

        var ri = 0;
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
                const p4 = self.start.lerp(self.end, t);

                //       var p5x = p2x + (p3x - p2x) * t;
                //       var p5y = p2y + (p3y - p2y) * t;
                const p5 = self.control.lerp(self.end, t);

                //       // candidate
                //       var p6x = p4x + (p5x - p4x) * t;
                //       var p6y = p4y + (p5y - p4y) * t;
                const p6 = p4.lerp(p5);

                //       // See if point is on line segment
                //       // Had to make special cases for vertical and horizontal lines due
                //       // to slight errors in calculation of p6
                //       if (a1x === a2x) {
                if (line.isVertical()) {
                    //         if (miny <= p6y && p6y <= maxy) {
                    if (bounds.min.y <= p6.y and p6.y <= bounds.max.y) {
                        //           if (result) result.push(p6x, p6y);
                        //           else        return 1;
                        result[ri] = p6;
                        ri += 1;
                    }
                    //         }
                    //       } else if (a1y === a2y) {
                } else if (line.isHorizontal()) {
                    //         if (minx <= p6x && p6x <= maxx) {
                    if (bounds.min.x <= p6.x and p6.x <= bounds.max.x) {
                        //           if (result) result.push(p6x, p6y);
                        //           else        return 1;
                        result[ri] = p6;
                        ri += 1;
                    }
                    //         }
                } else if (bounds.containsPoint(p6)) {
                    result[ri] = p6;
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

            return result[0..ri];
            //   return result ? result.length / 2 : 0;
        }
    }
};

test "intersect quadratic bezier with line" {
    const bezier = QuadraticBezier.create(PointF32{
        .x = 0.0,
        .y = 0.0,
    }, PointF32{
        .x = 0.5,
        .y = 1.0,
    }, PointF32{
        .x = 1.0,
        .y = 1.0,
    });
    const line = Line.create(PointF32{
        .x = 0.0,
        .y = 0.25,
    }, PointF32{
        .x = 1.0,
        .y = 0.25,
    });

    var intersections_result = [2]PointF32{};
    const intersections = bezier.intersectLine(line, &intersections_result);
    _ = intersections;
}
