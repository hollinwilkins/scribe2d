const std = @import("std");
const core = @import("../core/root.zig");
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;
const TransformF32 = core.TransformF32;

const GlyphPen = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub fn moveTo(self: @This(), point: PointF32) void {
    self.vtable.moveTo(self.ptr, point);
}

pub fn lineTo(self: @This(), p1: PointF32) void {
    self.vtable.lineTo(self.ptr, p1);
}

pub fn quadTo(self: @This(), p1: PointF32, p2: PointF32) void {
    self.vtable.quadTo(self.ptr, p1, p2);
}

pub fn curveTo(self: @This(), p1: PointF32, p2: PointF32, p3: PointF32) void {
    self.vtable.curveTo(self.ptr, p1, p2, p3);
}

pub fn open(self: @This()) void {
    self.vtable.open(self.ptr);
}

pub fn close(self: @This(), bounds: RectF32, ppem: f32) void {
    self.vtable.close(self.ptr, bounds, ppem);
}

pub const VTable = struct {
    moveTo: *const fn (ctx: *anyopaque, point: PointF32) void,
    lineTo: *const fn (ctx: *anyopaque, p1: PointF32) void,
    quadTo: *const fn (ctx: *anyopaque, p1: PointF32, p2: PointF32) void,
    curveTo: *const fn (ctx: *anyopaque, p1: PointF32, p2: PointF32, p3: PointF32) void,
    open: *const fn (ctx: *anyopaque) void,
    close: *const fn (ctx: *anyopaque, bounds: RectF32, ppem: f32) void,
};

pub const Debug = struct {
    const vtable = VTable{
        .moveTo = Debug.moveTo,
        .lineTo = Debug.lineTo,
        .quadTo = Debug.quadTo,
        .curveTo = Debug.curveTo,
        .open = Debug.open,
        .close = Debug.close,
    };

    pub const Instance = GlyphPen{
        .ptr = undefined,
        .vtable = &vtable,
    };

    pub fn moveTo(_: *anyopaque, point: PointF32) void {
        std.debug.print("Outliner.Debug.moveTo({})\n", .{point});
    }

    pub fn lineTo(_: *anyopaque, p1: PointF32) void {
        std.debug.print("Outliner.Debug.lineTo({})\n", .{p1});
    }

    pub fn quadTo(_: *anyopaque, p1: PointF32, p2: PointF32) void {
        std.debug.print("Outliner.Debug.quadTo({}, {})\n", .{ p1, p2 });
    }

    pub fn curveTo(_: *anyopaque, p1: PointF32, p2: PointF32, p3: PointF32) void {
        std.debug.print("Outliner.Debug.curveTo({}, {}, {})\n", .{ p1, p2, p3 });
    }

    pub fn open(_: *anyopaque) void {
        std.debug.print("Outliner.Debug.open()\n", .{});
    }

    pub fn close(_: *anyopaque, bounds: RectF32, ppem: f32) void {
        std.debug.print("Outliner.Debug.close({},{})\n", .{ bounds, ppem });
    }
};
