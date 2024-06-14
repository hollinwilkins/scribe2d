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

pub fn lineTo(self: @This(), point: PointF32) void {
    self.vtable.lineTo(self.ptr, point);
}

pub fn quadTo(self: @This(), end: PointF32, control: PointF32) void {
    self.vtable.quadTo(self.ptr, end, control);
}

pub fn curveTo(self: @This(), end: PointF32, control1: PointF32, control2: PointF32) void {
    self.vtable.curveTo(self.ptr, end, control1, control2);
}

pub fn open(self: @This()) void {
    self.vtable.open(self.ptr);
}

pub fn close(self: @This()) void {
    self.vtable.close(self.ptr);
}

pub fn transform(self: @This(), t: TransformF32) void {
    self.vtable.transform(self.ptr, t);
}

pub const VTable = struct {
    moveTo: *const fn (ctx: *anyopaque, point: PointF32) void,
    lineTo: *const fn (ctx: *anyopaque, end: PointF32) void,
    quadTo: *const fn (ctx: *anyopaque, end: PointF32, control: PointF32) void,
    curveTo: *const fn (ctx: *anyopaque, end: PointF32, control1: PointF32, control2: PointF32) void,
    open: *const fn (ctx: *anyopaque) void,
    close: *const fn (ctx: *anyopaque) void,
    transform: *const fn (ctx: *anyopaque, t: TransformF32) void,
};

pub const Debug = struct {
    const vtable = VTable{
        .moveTo = Debug.moveTo,
        .lineTo = Debug.lineTo,
        .quadTo = Debug.quadTo,
        .curveTo = Debug.curveTo,
        .open = Debug.open,
        .close = Debug.close,
        .transform = Debug.transform,
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

    pub fn open(_: *anyopaque) void {
        std.debug.print("Outliner.Debug.open()\n", .{});
    }

    pub fn close(_: *anyopaque) void {
        std.debug.print("Outliner.Debug.close()\n", .{});
    }

    pub fn transform(_: *anyopaque, t: TransformF32) void {
        std.debug.print("Outliner.Debug.transform({})\n", .{t});
    }
};
