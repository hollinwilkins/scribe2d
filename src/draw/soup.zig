const std = @import("std");
const core = @import("../core/root.zig");
const path_module = @import("./path.zig");
const pen = @import("./pen.zig");
const curve_module = @import("./curve.zig");
const euler = @import("./euler.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const Path = path_module.Path;
const PathBuilder = path_module.PathBuilder;
const PathMetadata = path_module.PathMetadata;
const Paths = path_module.Paths;
const Style = pen.Style;
const Line = curve_module.Line;
const Arc = curve_module.Arc;
const CubicPoints = euler.CubicPoints;
const CubicParams = euler.CubicParams;
const EulerParams = euler.EulerParams;
const EulerSegment = euler.EulerSegment;

pub fn Soup(comptime T: type) type {
    return struct {
        const SoupSelf = @This();

        pub const PathRecord = struct {
            fill: ?Style.Fill = null,
            subpath_offsets: RangeU32,
        };

        pub const SubpathRecord = struct {
            item_offsets: RangeU32,
        };

        pub const PathRecordList = std.ArrayListUnmanaged(PathRecord);
        pub const SubpathRecordList = std.ArrayListUnmanaged(SubpathRecord);
        pub const ItemList = std.ArrayListUnmanaged(T);

        allocator: Allocator,
        path_records: PathRecordList = PathRecordList{},
        subpath_records: SubpathRecordList = SubpathRecordList{},
        items: ItemList = ItemList{},

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.path_records.deinit(self.allocator);
            self.subpath_records.deinit(self.allocator);
            self.items.deinit(self.allocator);
        }

        pub fn getPathRecords(self: @This()) []const PathRecord {
            return self.path_records.items;
        }

        pub fn getSubpathRecords(self: @This()) []const SubpathRecord {
            return self.subpath_records.items;
        }

        pub fn getItems(self: @This()) []const T {
            return self.items.items;
        }

        pub fn openPath(self: *@This()) !void {
            const path = try self.path_records.addOne(self.allocator);
            path.* = PathRecord{
                .subpath_offsets = RangeU32{
                    .start = @intCast(self.subpath_records.items.len),
                    .end = @intCast(self.subpath_records.items.len),
                },
            };
        }

        pub fn closePath(self: *@This()) !void {
            self.path_records.items[self.path_records.items.len - 1].subpath_offsets.end = @intCast(self.subpath_records.items.len);
        }

        pub fn openSubpath(self: *@This()) !void {
            const subpath = try self.subpath_records.addOne(self.allocator);
            subpath.* = SubpathRecord{
                .item_offsets = RangeU32{
                    .start = @intCast(self.items.items.len),
                    .end = @intCast(self.items.items.len),
                },
            };
        }

        pub fn closeSubpath(self: *@This()) !void {
            self.subpath_records.items[self.subpath_records.items.len - 1].item_offsets.end = @intCast(self.items.items.len);
        }

        pub fn addItem(self: *@This()) !*T {
            return try self.items.addOne(self.allocator);
        }

        pub const Estimator = struct {
            pub fn estimateAlloc(allocator: Allocator, paths: Paths) SoupSelf {
                var soup = SoupSelf.init(allocator);
                errdefer soup.deinit();

                for (paths.path_records.items) |path_record| {
                    const subpath_records = paths.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                    for (subpath_records) |subpath_record| {
                        if (paths.isSubpathCapped(subpath_record)) {
                            // subpath is capped, so the stroke will be a single subpath
                        } else {
                            // subpath is not capped, so the stroke will be two subpaths
                        }
                    }
                }

                return soup;
            }

            fn tallySubpath(paths: Paths, subpath_record: Paths.SubpathRecord) u32 {
                var join_tally: u32 = 0;
                var line_tally: u32 = 0;
                var quadratic_tally: u32 = 0;
                var last_point: ?PointF32 = null;

                const curve_records = paths.curve_records.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
                for (curve_records) |curve_record| {
                    switch (curve_record.kind) {
                        .line => {
                            const points = paths.points.items[curve_record.point_offsets.start..curve_record.point_offsets.end];
                            last_point = points[1];

                            join_tally += 1;
                            line_tally += 1;


                            // last_pt = Some(p0);
                            // joins += 1;
                            // lineto_lines += 1;
                            // segments += count_segments_for_line(first_pt.unwrap(), last_pt.unwrap(), t);
                        },
                        .quadratic_bezier => {},
                    }
                }
            }
        };
    };
}

pub const LineSoup = Soup(Line);
pub const ArcSoup = Soup(Arc);
