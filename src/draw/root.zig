pub const Error = error{
    DimensionOverflow,
};

const path = @import("./path.zig");

pub const PathOutliner = path.PathOutliner;
pub const Path = path.Path;
pub const Segment = path.Segment;
