const std = @import("std");
const core = @import("../core/root.zig");
const RectF32 = core.RectF32;
const PointF32 = core.PointF32;

const GlyphPen = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub fn moveTo(self: @This(), point: PointF32) void {
    self.vtable.moveTo(self.ptr, point);
}

pub fn lineTo(self: @This(), point: PointF32) void {
    self.vtable.lineTo(self.ptr, point);
}

pub fn quadTo(self: @This(), end: PointF32, control: PointF32) void {
    self.vtable.quadTo(self.ptr, end, control);
}

pub fn curveTo(self: @This(), end: PointF32, control1: PointF32, control2: PointF32) void {
    self.vtable.curveTo(self.ptr, end, control1, control2);
}

pub fn close(self: @This()) void {
    self.vtable.close(self.ptr);
}

pub fn finish(self: @This(), bounds: RectF32) void {
    self.vtable.finish(self.ptr, bounds);
}

pub const VTable = struct {
    moveTo: *const fn (ctx: *anyopaque, point: PointF32) void,
    lineTo: *const fn (ctx: *anyopaque, end: PointF32) void,
    quadTo: *const fn (ctx: *anyopaque, end: PointF32, control: PointF32) void,
    curveTo: *const fn (ctx: *anyopaque, end: PointF32, control1: PointF32, control2: PointF32) void,
    close: *const fn (ctx: *anyopaque) void,
    finish: *const fn (ctx: *anyopaque, bounds: RectF32) void,
};

pub const Debug = struct {
    const vtable = VTable{
        .moveTo = Debug.moveTo,
        .lineTo = Debug.lineTo,
        .quadTo = Debug.quadTo,
        .curveTo = Debug.curveTo,
        .close = Debug.close,
        .finish = Debug.finish,
    };

    pub const Instance = GlyphPen{
        .ptr = undefined,
        .vtable = &vtable,
    };

    pub fn moveTo(_: *anyopaque, point: PointF32) void {
        std.debug.print("Outliner.Debug.moveTo({})\n", .{ point });
    }

    pub fn lineTo(_: *anyopaque, end: PointF32) void {
        std.debug.print("Outliner.Debug.lineTo({})\n", .{ end });
    }

    pub fn quadTo(_: *anyopaque, end: PointF32, control: PointF32) void {
        std.debug.print("Outliner.Debug.quadTo({}, {})\n", .{ end, control });
    }

    pub fn curveTo(_: *anyopaque, end: PointF32, control1: PointF32, control2: PointF32) void {
        std.debug.print("Outliner.Debug.curveTo({}, {}, {})\n", .{ end, control1, control2 });
    }

    pub fn close(_: *anyopaque) void {
        std.debug.print("Outliner.Debug.close()\n", .{});
    }

    pub fn finish(_: *anyopaque, bounds: RectF32) void {
        std.debug.print("Outliner.Debug.finish({})\n", .{bounds});
    }
};
