const std = @import("std");
pub const core = @import("./core/root.zig");
pub const draw = @import("./draw/root.zig");
pub const svg = @import("./svg/root.zig");
pub const text = @import("./text/root.zig");

test "encoding path monoids" {
    var encoder = draw.Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.encodeColor(draw.encoding.ColorU8{
        .r = 255,
        .g = 255,
        .b = 0,
        .a = 255,
    });
    var style = draw.encoding.Style{};
    style.setFill(draw.encoding.Style.Fill{
        .brush = .color,
    });
    try encoder.encodeStyle(style);

    var path_encoder = encoder.pathEncoder(f32);
    try path_encoder.moveTo(core.PointF32.create(1.0, 1.0));
    _ = try path_encoder.lineTo(core.PointF32.create(2.0, 2.0));
    _ = try path_encoder.arcTo(core.PointF32.create(3.0, 3.0), core.PointF32.create(4.0, 2.0));
    _ = try path_encoder.lineTo(core.PointF32.create(1.0, 1.0));
    try path_encoder.finish();

    const encoding = encoder.encode();
    var rasterizer = draw.encoding.CpuRasterizer.init(std.testing.allocator, encoding);
    defer rasterizer.deinit();

    try rasterizer.rasterize();

    var path_specs = [_]draw.encoding.PathSpec{undefined} ** 3;

    for (encoding.path_tags, rasterizer.path_monoids.items, &path_specs) |tag, monoid, *spec| {
        spec.* = draw.encoding.PathSpec{ .tag = tag, .monoid = monoid };
    }

    // rasterizer.debugPrint();

    try std.testing.expectEqualDeep(
        core.LineF32.create(core.PointF32.create(1.0, 1.0), core.PointF32.create(2.0, 2.0)),
        encoding.getSegment(core.LineF32, path_specs[0].getSegmentOffset()),
    );
    try std.testing.expectEqualDeep(
        core.ArcF32.create(
            core.PointF32.create(2.0, 2.0),
            core.PointF32.create(3.0, 3.0),
            core.PointF32.create(4.0, 2.0),
        ),
        encoding.getSegment(core.ArcF32, path_specs[1].getSegmentOffset()),
    );
    try std.testing.expectEqualDeep(
        core.LineF32.create(core.PointF32.create(4.0, 2.0), core.PointF32.create(1.0, 1.0)),
        encoding.getSegment(core.LineF32, path_specs[2].getSegmentOffset()),
    );
}
