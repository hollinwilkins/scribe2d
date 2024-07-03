const std = @import("std");
pub const encoding = @import("./draw/encoding.zig");

test {
    std.testing.refAllDecls(encoding);
}
