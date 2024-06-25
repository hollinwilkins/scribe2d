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
            pub const SubpathEstimate = struct {
                intersections: u32 = 0,
                items: u32 = 0,
                join_items: u32 = 0,
                cap_items: u32 = 0,
            };

            pub fn estimateAlloc(
                allocator: Allocator,
                metadatas: []const PathMetadata,
                styles: []const Style,
                transforms: []const TransformF32,
                paths: Paths,
            ) SoupSelf {
                var soup = SoupSelf.init(allocator);
                errdefer soup.deinit();

                for (metadatas) |metadata| {
                    const style = styles[metadata.style_index];
                    const transform = transforms[metadata.transform_index];
                    _ = transform;

                    const path_records = paths.path_records.items[metadata.path_offsets.start..metadata.path_offsets.end];
                    for (path_records) |path_record| {
                        const subpath_records = paths.subpath_records.items[path_record.subpath_offsets.start..path_record.subpath_offsets.end];
                        for (subpath_records) |subpath_record| {
                            if (style.isFilled()) {}

                            if (style.isStroked()) {
                                if (paths.isSubpathCapped(subpath_record)) {
                                    // subpath is capped, so the stroke will be a single subpath
                                } else {
                                    // subpath is not capped, so the stroke will be two subpaths
                                }
                            }
                        }
                    }
                }

                return soup;
            }

            fn estimateSubpath(paths: Paths, subpath_record: Paths.SubpathRecord, style: Style, transform: TransformF32) SubpathEstimate {
                var estimate = SubpathEstimate{};
                var intersections: u32 = 0;
                var items: u32 = 0;
                var joins: u32 = 0;
                var lines: u32 = 0;
                var quadratics: u32 = 0;
                var last_point: ?PointF32 = null;

                const curve_records = paths.curve_records.items[subpath_record.curve_offsets.start..subpath_record.curve_offsets.end];
                for (curve_records) |curve_record| {
                    switch (curve_record.kind) {
                        .line => {
                            const points = paths.points.items[curve_record.point_offsets.start..curve_record.point_offsets.end];
                            last_point = points[1];
                            intersections += estimateLineIntersections(points[0], points[1], transform);
                            joins += 1;
                            lines += 1;
                            items += T.estimateLineItems(points[0], points[1]);
                        },
                        .quadratic_bezier => {
                            const points = paths.points.items[curve_record.point_offsets.start..curve_record.point_offsets.end];
                            last_point = points[2];
                            // intersections += estimateLineIntersections(points[0], points[1], transform);
                            // joins += 1;
                            // lines += 1;
                            // items += T.estimateLineItems(points[0], points[1]);
                        },
                    }
                }

                return estimate;
            }

            fn estimateLineIntersections(p0: PointF32, p1: PointF32, transform: TransformF32) u32 {
                const dxdy = transformScale(transform, p0.sub(p1));
                const x_intersections = @as(u32, @intFromFloat(@ceil(dxdy.x)));
                const y_intersections = @as(u32, @intFromFloat(@ceil(dxdy.y)));
                // add 2 for virtual intersections
                return @max(1, x_intersections + y_intersections + 2);
            }

            fn estimateLineCrossings(p0: PointF32, p1: PointF32, transform: TransformF32) u32 {
                const dxdy = transformScale(transform, p0.sub(p1));
                const segments = @ceil(@ceil(@abs(dxdy.x)) * 0.0625) + @ceil(@ceil(@abs(dxdy.y)) * 0.0625);
                return @max(1, @as(u32, @intFromFloat(segments)));
            }

            fn transformScale(t: TransformF32, point: PointF32) PointF32 {
                return PointF32{
                    .x = t.coefficients[0] * point.x + t.coefficients[2] * point.y,
                    .y = t.coefficients[1] * point.x + t.coefficients[3] * point.y,
                };
            }
        };
    };
}

pub const LineSoup = Soup(Line);
pub const ArcSoup = Soup(Arc);
