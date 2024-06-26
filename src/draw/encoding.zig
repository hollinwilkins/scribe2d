const std = @import("std");
const soup_module = @import("./soup.zig");
const soup_estimate = @import("./soup_estimate.zig");
const curve = @import("./curve.zig");
const scene_module = @import("./scene.zig");
const mem = std.mem;
const Allocator = mem.Allocator;
const Soup = soup_module.Soup;
const Estimate = soup_module.Estimate;
const Line = curve.Line;
const Scene = scene_module.Scene;

pub fn SoupEncoding(comptime T: type) type {
    const S = Soup(T);

    return struct {
        fill: S.Encoding,
        stroke: S.Encoding,
    };
}

pub const LineSoupEncoding = SoupEncoding(Line);

pub fn SoupEncoder(comptime T: type) type {
    const EstimateList = std.ArrayListUnmanaged(Estimate);

    const S = Soup(T);
    const SE = SoupEncoding(T);

    return struct {
        allocator: Allocator,
        fill: S,
        stroke: S,
        base_estimates: EstimateList = EstimateList{},

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .allocator = allocator,
                .fill = S.init(allocator),
                .stroke = S.init(allocator),
            };
        }

        pub fn toEncoding(self: @This()) SE {
            return SE{
                .fill = self.fill.toEncoding(),
                .stroke = self.stroke.toEncoding(),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.fill.deinit();
            self.stroke.deinit();
            self.base_estimates.deinit(self.allocator);
        }

        pub fn addBaseEstimate(self: *@This()) !*Estimate {
            return try self.base_estimates.addOne(self.allocator);
        }

        pub fn addBaseEstimates(self: *@This(), n: usize) ![]Estimate {
            return try self.base_estimates.addManyAsSlice(self.allocator, n);
        }
    };
}

pub const LineSoupEncoder = SoupEncoder(Line);
