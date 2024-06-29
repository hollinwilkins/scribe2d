const soup_module = @import("./soup.zig");
const path = @import("./path.zig");
const PathRecord = soup_module.PathRecord;
const SubpathRecord = soup_module.SubpathRecord;
const CurveRecord = soup_module.CurveRecord;

pub fn Kernel(comptime T: type) type {
    return struct {
        pub fn flattenFill(
            path: []const PathRecord,
            subpath: []const SubpathRecord,
            curve: []const CurveRecord,
            source_curve: []const path.CurveRecord,
            items: []T,
        ) void {}
    };
}
