const std = @import("std");
const core = @import("../core/root.zig");
const RectF32 = core.RectF32;

const TextOutliner = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub fn moveTo(self: @This(), x: f32, y: f32) void {
    self.vtable.moveTo(self.ptr, x, y);
}

pub fn lineTo(self: @This(), x: f32, y: f32) void {
    self.vtable.lineTo(self.ptr, x, y);
}

pub fn quadTo(self: @This(), x1: f32, y1: f32, x: f32, y: f32) void {
    self.vtable.quadTo(self.ptr, x1, y1, x, y);
}

pub fn curveTo(self: @This(), x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) void {
    self.vtable.curveTo(self.ptr, x1, y1, x2, y2, x, y);
}

pub fn close(self: @This()) void {
    self.vtable.close(self.ptr);
}

pub fn finish(self: @This(), bounds: RectF32) void {
    self.vtable.finish(bounds);
}

pub const VTable = struct {
    moveTo: *const fn (ctx: *anyopaque, x: f32, y: f32) void,
    lineTo: *const fn (ctx: *anyopaque, x: f32, y: f32) void,
    quadTo: *const fn (ctx: *anyopaque, x1: f32, y1: f32, x: f32, y: f32) void,
    curveTo: *const fn (ctx: *anyopaque, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) void,
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

    pub const Instance = TextOutliner{
        .ptr = undefined,
        .vtable = &vtable,
    };

    pub fn moveTo(_: *anyopaque, x: f32, y: f32) void {
        std.debug.print("Outliner.Debug.moveTo({}, {})\n", .{ x, y });
    }

    pub fn lineTo(_: *anyopaque, x: f32, y: f32) void {
        std.debug.print("Outliner.Debug.lineTo({}, {})\n", .{ x, y });
    }

    pub fn quadTo(_: *anyopaque, x1: f32, y1: f32, x: f32, y: f32) void {
        std.debug.print("Outliner.Debug.quadTo({}, {}, {}, {})\n", .{ x1, y1, x, y });
    }

    pub fn curveTo(_: *anyopaque, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) void {
        std.debug.print("Outliner.Debug.curveTo({}, {}, {}, {}, {}, {})\n", .{ x1, y1, x2, y2, x, y });
    }

    pub fn close(_: *anyopaque) void {
        std.debug.print("Outliner.Debug.close()\n", .{});
    }

    pub fn finish(_: *anyopaque, bounds: RectF32) void {
        std.debug.print("Outliner.Debug.finish({})\n", .{bounds});
    }
};
