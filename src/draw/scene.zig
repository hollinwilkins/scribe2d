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
const PathsUnmanaged = path_module.PathsUnmanaged;

pub const Scene = struct {
    pub const PathMetadata = struct {
        style_index: u16,
        transform_index: u16,
        path_offsets: RangeU32 = RangeU32{},
    };

    const StyleList = std.ArrayListUnmanaged(Style);
    const TransformList = std.ArrayListUnmanaged(TransformF32);
    const PathMetadataList = std.ArrayListUnmanaged(PathMetadata);

    allocator: Allocator,
    styles: StyleList = StyleList{},
    transforms: TransformList = TransformList{},
    metadata: PathMetadataList = PathMetadataList{},
    paths: PathsUnmanaged = PathsUnmanaged{},

    pub fn init(allocator: Allocator) !@This() {
        var scene = @This(){
            .allocator = allocator,
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
        self.paths.deinit(self.allocator);
    }

    pub fn getStyles(self: @This()) []const Style {
        return self.styles.items;
    }

    pub fn pushStyle(self: *@This()) !*Style {
        const style = try self.styles.addOne(self.allocator);
        style.* = Style{};
        try self.pushMetadata();
        return style;
    }

    pub fn pushTransform(self: *@This()) !*TransformF32 {
        const transform = try self.transforms.addOne(self.allocator);
        transform.* = TransformF32{};
        try self.pushTransform();
        return transform;
    }

    pub fn close(self: *@This()) !void {
        try self.pushMetadata();
    }

    fn pushMetadata(self: *@This()) !void {
        var metadata: *PathMetadata = undefined;
        if (self.metadata.items.len > 0) {
            metadata = &self.metadata.items[self.metadata.items.len - 1];
            metadata.path_offsets.end = self.paths.path_records.items.len;

            if (metadata.path_offsets.size() > 0) {
                metadata = try self.metadata.addOne(self.allocator);
            }
        } else {
            metadata = try self.metadata.addOne(self.allocator);
        }

        metadata.* = PathMetadata{
            .style_index = self.styles.items.len - 1,
            .transform_index = self.transforms.items.len - 1,
            .path_offsets = RangeU32{
                .start = self.paths.path_records.items.len,
                .end = self.paths.path_records.items.len,
            }
        };
    }
};
