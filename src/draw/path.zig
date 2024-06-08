const std = @import("std");
const text = @import("../text/root.zig");
const core = @import("../core/root.zig");
const curve_module = @import("./curve.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const RangeF32 = core.RangeF32;
const RangeU32 = core.RangeU32;
const Curve = curve_module.Curve;
const Subpath = curve_module.Subpath;
const Line = curve_module.Line;
const QuadraticBezier = curve_module.QuadraticBezier;
const SequenceU32 = core.SequenceU32;

pub const Path = struct {
    pub const Unmanaged = struct {
        var IdSequence = SequenceU32.initValue(0);

        id: u32,
        subpaths: []const Subpath,
        curves: []const Curve,

        pub fn create(subpaths: []const Subpath, curves: []const Curve) Unmanaged {
            return Unmanaged{
                .id = IdSequence.next(),
                .subpaths = subpaths,
                .curves = curves,
            };
        }

        pub fn deinit(self: Unmanaged, allocator: Allocator) void {
            allocator.free(self.subpaths);
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

    pub fn getSubpaths(self: *const Path) []const Subpath {
        return self.unmanaged.subpaths;
    }

    pub fn getCurves(self: *const Path) []const Curve {
        return self.unmanaged.curves;
    }

    pub fn getCurvesRange(self: *const Path, range: RangeU32) []const Curve {
        return self.unmanaged.curves[range.start..range.end];
    }

    pub fn debug(self: *const Path) void {
        std.debug.print("Path\n", .{});
        for (self.unmanaged.curves) |curve| {
            std.debug.print("\t{}\n", .{curve});
        }
    }
};
