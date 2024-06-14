const std = @import("std");
const path_module = @import("./path.zig");
const pen = @import("./pen.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;
const Style = pen.Pen.Style;

pub const PathFlattener = struct {
    const PathRecord = struct {
        path_index: u32,
    };

    // pub fn flatten(paths: []const Path, styles: []const Style, flat_paths: []Path) void {

    // }
};



    // for (self.path.getSubpathRecords()) |subpath_record| {
    //     for (self.path.getCurveRecords()) |curve_record| {
    //         const cubic_points = self.path.getCubicPoints(curve_record);
    //         _ = cubic_points;
    //         _ = subpath_record;
    //     }
    // }
