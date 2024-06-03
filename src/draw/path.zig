const std = @import("std");
const text = @import("../text/root.zig");
const core = @import("../core/root.zig");
const curve_module = @import("./curve.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const RangeF32 = core.RangeF32;
const Curve = curve_module.Curve;
const Line = curve_module.Line;
const QuadraticBezier = curve_module.QuadraticBezier;
const SequenceU32 = core.SequenceU32;

pub const Path = struct {
    pub const Unmanaged = struct {
        var IdSequence = SequenceU32.initValue(0);

        id: u32,
        curves: []const Curve,

        pub fn create(curves: []const Curve) Unmanaged {
            return Unmanaged{
                .id = IdSequence.next(),
                .curves = curves,
            };
        }

        pub fn deinit(self: Unmanaged, allocator: Allocator) void {
            allocator.free(self.curves);
        }
    };

    allocator: Allocator,
    unmanaged: Unmanaged,

    pub fn deinit(self: Path) void {
        self.unmanaged.deinit(self.allocator);
    }

    pub fn getId(self: Path) u32 {
        return self.unmanaged.id;
    }

    pub fn getCurves(self: *const Path) []const Curve {
        return self.unmanaged.curves;
    }

    pub fn debug(self: *const Path) void {
        std.debug.print("Path\n", .{});
        for (self.unmanaged.curves) |curve| {
            std.debug.print("\t{}\n", .{curve});
        }
    }
};
