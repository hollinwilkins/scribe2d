const std = @import("std");
const soup_module = @import("./soup.zig");
const soup_estimate = @import("./soup_estimate.zig");
const curve = @import("./curve.zig");
const scene_module = @import("./scene.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Soup = soup_module.Soup;
const Line = curve.Line;
const Scene = scene_module.Scene;

pub fn SoupEncoding(comptime T: type) type {
    const S = Soup(T);

    return struct {
        fill: S,
        stroke: S,

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .fill = S.init(allocator),
                .stroke = S.init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.fill.deinit();
            self.stroke.deinit();
        }
    };
}

pub const LineSoupEncoding = SoupEncoding(Line);
