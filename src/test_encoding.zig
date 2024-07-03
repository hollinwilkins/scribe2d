const std = @import("std");
pub const core = @import("./core/root.zig");
pub const draw = @import("./draw/root.zig");
pub const svg = @import("./svg/root.zig");
pub const text = @import("./text/root.zig");

test "encoding path monoids" {
    var encoder = draw.Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    var path_encoder = encoder.pathEncoder(f32);
    try path_encoder.finish();
}
