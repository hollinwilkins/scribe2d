const std = @import("std");
const core = @import("../core/root.zig");
const pen = @import("./pen.zig");
const path_module = @import("./path.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const TransformF32 = core.TransformF32;
const RangeU32 = core.RangeU32;
const PointF32 = core.PointF32;
const Style = pen.Style;
const Paths = path_module.Paths;
const PathMetadata = path_module.PathMetadata;

pub const Scene = struct {
    const StyleList = std.ArrayListUnmanaged(Style);
    const TransformList = std.ArrayListUnmanaged(TransformF32.Matrix);
    const PathMetadataList = std.ArrayListUnmanaged(PathMetadata);

    allocator: Allocator,
    styles: StyleList = StyleList{},
    transforms: TransformList = TransformList{},
    metadata: PathMetadataList = PathMetadataList{},
    paths: Paths,

    pub fn init(allocator: Allocator) !@This() {
        var scene = @This(){
            .allocator = allocator,
            .paths = Paths.init(allocator),
        };

        // push defaults
        _ = try scene.pushStyle();
        _ = try scene.pushTransform();
        try scene.pushMetadata();

        return scene;
    }

    pub fn deinit(self: *@This()) void {
        self.styles.deinit(self.allocator);
        self.transforms.deinit(self.allocator);
        self.metadata.deinit(self.allocator);
        self.paths.deinit();
    }

    // pub fn toSoupAlloc

    pub fn getMetadatas(self: @This()) []const PathMetadata {
        return self.metadata.items;
    }

    pub fn getStyles(self: @This()) []const Style {
        return self.styles.items;
    }

    pub fn getTransforms(self: @This()) []const TransformF32.Matrix {
        return self.transforms.items;
    }

    pub fn pushStyle(self: *@This()) !*Style {
        const style = try self.styles.addOne(self.allocator);
        style.* = Style{};
        try self.pushMetadata();
        return style;
    }

    pub fn pushTransform(self: *@This()) !*TransformF32.Matrix {
        const transform = try self.transforms.addOne(self.allocator);
        transform.* = TransformF32.Matrix.IDENTITY;
        try self.pushMetadata();
        return transform;
    }

    pub fn close(self: *@This()) !void {
        try self.pushMetadata();
    }

    fn pushMetadata(self: *@This()) !void {
        var metadata: *PathMetadata = undefined;
        if (self.metadata.items.len > 0) {
            metadata = &self.metadata.items[self.metadata.items.len - 1];
            metadata.path_offsets.end = @intCast(self.paths.path_records.items.len);

            if (metadata.path_offsets.size() > 0) {
                metadata = try self.metadata.addOne(self.allocator);
            }
        } else {
            metadata = try self.metadata.addOne(self.allocator);
        }

        metadata.* = PathMetadata{
            .style_index = @as(u16, @intCast(self.styles.items.len)) -| 1,
            .transform_index = @as(u16, @intCast(self.transforms.items.len)) -| 1,
            .path_offsets = RangeU32{
                .start = @intCast(self.paths.path_records.items.len),
                .end = @intCast(self.paths.path_records.items.len),
            }
        };
    }
};
