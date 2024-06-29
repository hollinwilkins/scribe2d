const core = @import("../core/root.zig");
const soup_module = @import("./soup.zig");
const shape_module = @import("./shape.zig");
const TransformF32 = core.TransformF32;
const FlatPath = soup_module.FlatPath;
const FlatSubpath = soup_module.FlatSubpath;
const FlatCurve = soup_module.FlatCurve;
const Path = shape_module.Path;
const Subpath = shape_module.Subpath;
const Curve = shape_module.Curve;

pub fn Kernel(comptime T: type) type {
    return struct {
        pub fn flattenFill(
            // input buffers
            transforms: []TransformF32.Matrix,
            curves: []const Curve,
            flat_curves: []const FlatCurve,
            // job parameters
            transform_index: u32,
            curve_index: u32,
            flat_curve_index: u32,
            // write destination
            items: []T,
        ) void {}
    };
}
