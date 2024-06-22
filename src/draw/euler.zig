// Source: https://github.com/linebender/vello/blob/eb20ffcd3eff4fe842932e26e6431a7e4fb502d2/vello_shaders/src/cpu/euler.rs

const std = @import("std");
const core = @import("../core/root.zig");
const PointF32 = core.PointF32;

pub const TANGENT_THRESH: f32 = 1e-6;
pub const TANGENT_THRESH_POW2: f32 = std.math.pow(f32, TANGENT_THRESH, 2.0);

pub const CubicPoints = struct {
    point0: PointF32 = PointF32{},
    point1: PointF32 = PointF32{},
    point2: PointF32 = PointF32{},
    point3: PointF32 = PointF32{},
};

pub const CubicParams = struct {
    // tangent at start of curve
    th0: f32,
    // tangend at end of curve
    th1: f32,
    // length of the chord
    chord_len: f32,
    // estimated error between cubic curve and a proposed Eurler spiral
    err: f32,

    pub fn create(p0: PointF32, p1: PointF32, q0: PointF32, q1: PointF32, dt: f32) @This() {
        const chord = p1.sub(p0);
        const chord_squared = chord.dot(chord); // length_squared
        const chord_len: f32 = std.math.sqrt(chord_squared);
        // Chord is near-zero; straight line case.
        if (chord_squared < TANGENT_THRESH_POW2) {
            // This error estimate was determined empirically through randomized
            // testing, though it is likely it can be derived analytically.
            const chord_err = std.math.sqrt((9.0 / 32.0) * (q0.dot(q0) + q1.dot(q1))) * dt;
            return CubicParams{
                .th0 = 0.0,
                .th1 = 0.0,
                .chord_len = TANGENT_THRESH,
                .err = chord_err,
            };
        }

        const scale: f32 = dt / chord_squared;
        const h0 = PointF32{
            .x = q0.x * chord.x + q0.y * chord.y,
            .y = q0.y * chord.x - q0.x * chord.y,
        };
        const th0 = h0.atan2();
        const d0 = h0.length() * scale;
        const h1 = PointF32{
            .x = q1.x * chord.x + q1.y * chord.y,
            .y = q1.x * chord.y - q1.y * chord.x,
        };
        const th1 = h1.atan2();
        const d1 = h1.length() * scale;
        // Robustness note: we may want to clamp the magnitude of the angles to
        // a bit less than pi. Perhaps here, perhaps downstream.

        // Estimate error of geometric Hermite interpolation to Euler spiral.
        const cth0 = std.math.cos(th0);
        const cth1 = std.math.cos(th1);
        var err: f32 = undefined;

        if (cth0 * cth1 < 0.0) {
            // A value of 2.0 represents the approximate worst case distance
            // from an Euler spiral with 0 and pi tangents to the chord. It
            // is not very critical; doubling the value would result in one more
            // subdivision in effectively a binary search for the cusp, while too
            // small a value may result in the actual error exceeding the bound.
            err = 2.0;
        } else {
            // Protect against divide-by-zero. This happens with a double cusp, so
            // should in the general case cause subdivisions.
            const e0 = (2.0 / 3.0) / @max(1.0 + cth0, 1e-9);
            const e1 = (2.0 / 3.0) / @max(1.0 + cth1, 1e-9);
            const s0 = std.math.sin(th0);
            const s1 = std.math.sin(th1);
            // Note: some other versions take sin of s0 + s1 instead. Those are incorrect.
            // Strangely, calibration is the same, but more work could be done.
            const s01 = cth0 * s1 + cth1 * s0;
            const amin = 0.15 * (2.0 * e0 * s0 + 2.0 * e1 * s1 - e0 * e1 * s01);
            const a = 0.15 * (2.0 * d0 * s0 + 2.0 * d1 * s1 - d0 * d1 * s01);
            const aerr = @abs(a - amin);
            const symm = @abs(th0 + th1);
            const asymm = @abs(th0 - th1);
            const dist = std.math.hypot(d0 - e0, d1 - e1);
            const ctr = 4.625e-6 * std.math.pow(f32, symm, 5.0) + 7.5e-3 * asymm * std.math.pow(f32, symm, 2.0);
            const halo_symm = 5e-3 * symm * dist;
            const halo_asymm = 7e-2 * asymm * dist;
            err = ctr + 1.55 * aerr + halo_symm + halo_asymm;
        }
        err *= chord_len;
        return @This(){
            .th0 = th0,
            .th1 = th1,
            .chord_len = chord_len,
            .err = err,
        };
    }
};

pub const EulerParams = struct {
    // tangent at start of curve
    th0: f32,
    // tangent at end of curve
    th1: f32,
    k0: f32,
    k1: f32,
    ch: f32,

    pub fn create(th0: f32, th1: f32) @This() {
        const k0 = th0 + th1;
        const dth = th1 - th0;
        const d2 = dth * dth;
        const k2 = k0 * k0;
        var a: f32 = 6.0;
        a -= d2 * (1.0 / 70.0);
        a -= (d2 * d2) * (1.0 / 10780.0);
        a += (d2 * d2 * d2) * 2.769178184818219e-07;
        const b = -0.1 + d2 * (1.0 / 4200.0) + d2 * d2 * 1.6959677820260655e-05;
        const c = -1.0 / 1400.0 + d2 * 6.84915970574303e-05 - k2 * 7.936475029053326e-06;
        a += (b + c * k2) * k2;
        const k1 = dth * a;

        // calculation of chord
        var ch: f32 = 1.0;
        ch -= d2 * (1.0 / 40.0);
        ch += (d2 * d2) * 0.00034226190482569864;
        ch -= (d2 * d2 * d2) * 1.9349474568904524e-06;
        const b2 = -1.0 / 24.0 + d2 * 0.0024702380951963226 - d2 * d2 * 3.7297408997537985e-05;
        const c2 = 1.0 / 1920.0 - d2 * 4.87350869747975e-05 - k2 * 3.1001936068463107e-06;
        ch += (b2 + c2 * k2) * k2;

        return @This(){
            .th0 = th0,
            .th1 = th1,
            .k0 = k0,
            .k1 = k1,
            .ch = ch,
        };
    }

    pub fn evalTheta(self: @This(), t: f32) f32 {
        return (0 + 0.5 * self.k1 * (t - 1.0)) * t - self.th0;
    }

    pub fn apply(self: @This(), t: f32) PointF32 {
        const thm = self.evalTheta(t * 0.5);
        const k0 = self.k0;
        const k1 = self.k1;
        const uv = integrate10((k0 + k1 * (0.5 * t - 0.5)) * t, k1 * t * t);
        const u = uv.x;
        const v = uv.v;
        const s = t / self.ch * thm.sin();
        const c = t / self.ch * thm.cos();
        const x = u * c - v * s;
        const y = -v * c - u * s;
        return PointF32{
            .x = x,
            .y = y,
        };
    }

    pub fn applyOffset(self: @This(), t: f32, offset: f32) PointF32 {
        const th = self.evalTheta(t);
        const v = PointF32{
            .x = offset * std.math.sin(th),
            .y = offset * std.math.cos(th),
        };
        return self.apply(t).add(v);
    }

    pub fn integrate10(k0: f32, k1: f32) PointF32 {
        const t1_1 = k0;
        const t1_2 = 0.5 * k1;
        const t2_2 = t1_1 * t1_1;
        const t2_3 = 2.0 * (t1_1 * t1_2);
        const t2_4 = t1_2 * t1_2;
        const t3_4 = t2_2 * t1_2 + t2_3 * t1_1;
        const t3_6 = t2_4 * t1_2;
        const t4_4 = t2_2 * t2_2;
        const t4_5 = 2.0 * (t2_2 * t2_3);
        const t4_6 = 2.0 * (t2_2 * t2_4) + t2_3 * t2_3;
        const t4_7 = 2.0 * (t2_3 * t2_4);
        const t4_8 = t2_4 * t2_4;
        const t5_6 = t4_4 * t1_2 + t4_5 * t1_1;
        const t5_8 = t4_6 * t1_2 + t4_7 * t1_1;
        const t6_6 = t4_4 * t2_2;
        const t6_7 = t4_4 * t2_3 + t4_5 * t2_2;
        const t6_8 = t4_4 * t2_4 + t4_5 * t2_3 + t4_6 * t2_2;
        const t7_8 = t6_6 * t1_2 + t6_7 * t1_1;
        const t8_8 = t6_6 * t2_2;
        var u = 1.0;
        u -= (1.0 / 24.0) * t2_2 + (1.0 / 160.0) * t2_4;
        u += (1.0 / 1920.0) * t4_4 + (1.0 / 10752.0) * t4_6 + (1.0 / 55296.0) * t4_8;
        u -= (1.0 / 322560.0) * t6_6 + (1.0 / 1658880.0) * t6_8;
        u += (1.0 / 92897280.0) * t8_8;
        var v = (1.0 / 12.0) * t1_2;
        v -= (1.0 / 480.0) * t3_4 + (1.0 / 2688.0) * t3_6;
        v += (1.0 / 53760.0) * t5_6 + (1.0 / 276480.0) * t5_8;
        v -= (1.0 / 11612160.0) * t7_8;

        return PointF32{
            .x = u,
            .y = v,
        };
    }
};

pub const EulerSegment = struct {
    start: PointF32,
    end: PointF32,
    params: EulerParams,

    pub fn applyOffset(self: EulerSegment, t: f32, normalized_offset: f32) PointF32 {
        const chord = self.end.sub(self.start);
        const point = self.params.applyOffset(t, normalized_offset);

        return PointF32{
            .x = self.start.x + chord.x * point.x - chord.y * point.y,
            .y = self.start.y + chord.x * point.y + chord.y * point.x,
        };
    }
};
