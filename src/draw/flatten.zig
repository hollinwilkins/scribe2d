const path_module = @import("./path.zig");
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;

pub const OutlineData = struct {
    builder: PathBuilder,
};

pub const PathOutliner = struct {
    path: *const Path,

    pub fn create(path: *const Path) @This() {
        return @This() {
            .path = path,
        };
    }

    pub fn outline(self: *@This(), outline_data: *OutlineData) void {
        _ = outline_data;

        for (self.path.getSubpathRecords()) |subpath_record| {
            for (self.path.getCurveRecords()) |curve_record| {
                const cubic_points = self.path.getCubicPoints(curve_record);
                _ = cubic_points;
                _ = subpath_record;
            }
        }
    }
};
