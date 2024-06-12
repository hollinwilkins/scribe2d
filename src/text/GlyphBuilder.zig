const std = @import("std");
const core = @import("../core/root.zig");
const util = @import("./util.zig");
const GlyphPen = @import("./GlyphPen.zig");
const RectF32 = core.RectF32;
const DimensionsF32 = core.DimensionsF32;
const PointF32 = core.PointF32;
const Transform = util.Transform;
const TransformF32 = core.TransformF32;

const EMPTY_BOUNDS: RectF32 = RectF32{
    .min = PointF32{
        .x = std.math.floatMax(f32),
        .y = std.math.floatMax(f32),
    },
    .max = PointF32{
        .x = std.math.floatMin(f32),
        .y = std.math.floatMin(f32),
    },
};

pen: GlyphPen,
bounds: RectF32,
transform: Transform,
is_default_transform: bool,
first_on_curve: ?PointF32,
first_off_curve: ?PointF32,
last_off_curve: ?PointF32,

pub fn create(bounds: ?RectF32, transform: Transform, pen: GlyphPen) @This() {
    const bounds2 = bounds orelse EMPTY_BOUNDS;

    return @This(){
        .pen = pen,
        .bounds = bounds2,
        .transform = transform,
        .is_default_transform = transform.isDefault(),
        .first_on_curve = null,
        .first_off_curve = null,
        .last_off_curve = null,
    };
}

pub fn moveTo(self: *@This(), point: PointF32) void {
    var point2 = point;
    if (!self.is_default_transform) {
        point2 = self.transform.apply(point);
    }

    self.bounds = self.bounds.extendBy(point2);
    self.pen.moveTo(point2);
}

pub fn lineTo(self: *@This(), end: PointF32) void {
    var end2 = end;
    if (!self.is_default_transform) {
        end2 = self.transform.apply(end);
    }

    self.bounds = self.bounds.extendBy(end2);
    self.pen.lineTo(end2);
}

pub fn quadTo(self: *@This(), end: PointF32, control: PointF32) void {
    var end2 = end;
    var control2 = control;
    if (!self.is_default_transform) {
        end2 = self.transform.apply(end);
        control2 = self.transform.apply(control);
    }

    self.bounds = self.bounds.extendBy(end2).extendBy(control2);
    self.pen.quadTo(end2, control2);
}

pub fn getBounds(self: @This()) RectF32 {
    if (std.meta.eql(self.bounds, EMPTY_BOUNDS)) {
        return RectF32{};
    } else {
        return self.bounds;
    }
}

pub fn pushPoint(self: *@This(), point: PointF32, on_curve_point: bool, last_point: bool) void {
    if (self.first_on_curve == null) {
        if (on_curve_point) {
            self.first_on_curve = point;
            self.moveTo(point);
        } else {
            if (self.first_off_curve) |off_curve| {
                const mid = off_curve.lerp(point, 0.5);
                self.first_on_curve = mid;
                self.last_off_curve = point;
                self.moveTo(mid);
            } else {
                self.first_off_curve = point;
            }
        }
    } else {
        if (self.last_off_curve) |off_curve| {
            if (on_curve_point) {
                self.last_off_curve = null;
                self.quadTo(point, off_curve);
            } else {
                self.last_off_curve = point;
                const mid = off_curve.lerp(point, 0.5);
                self.quadTo(mid, off_curve);
            }
        } else {
            if (on_curve_point) {
                self.lineTo(point);
            } else {
                self.last_off_curve = point;
            }
        }
    }

    if (last_point) {
        self.finishContour();
    }
}

fn finishContour(self: *@This()) void {
    if (self.first_off_curve) |off_curve1| {
        if (self.last_off_curve) |off_curve2| {
            self.last_off_curve = null;
            const mid = off_curve2.lerp(off_curve1, 0.5);
            self.quadTo(mid, off_curve2);
        }
    }

    if (self.first_on_curve) |point| {
        if (self.first_off_curve) |off_curve1| {
            self.quadTo(point, off_curve1);
        } else if (self.last_off_curve) |off_curve2| {
            self.quadTo(point, off_curve2);
        } else {
            self.lineTo(point);
        }

        self.first_on_curve = null;
        self.first_off_curve = null;
        self.last_off_curve = null;

        self.pen.close();
    }
}
