const std = @import("std");
const scribe = @import("scribe");
const draw = scribe.draw;

pub fn main() !void {
    var encoder = draw.Encoder.init(std.testing.allocator);
    defer encoder.deinit();

    try encoder.encodeColor(draw.ColorU8{
        .r = 255,
        .g = 255,
        .b = 0,
        .a = 255,
    });
    var style = draw.Style{};
    style.setFill(Style.Fill{
        .brush = .color,
    });
    style.setStroke(Style.Stroke{
        .join = .bevel,
    });
    try encoder.encodeStyle(style);

    var path_encoder = encoder.pathEncoder(f32);
    try path_encoder.moveTo(core.PointF32.create(10.0, 10.0));
    _ = try path_encoder.lineTo(core.PointF32.create(20.0, 20.0));
    _ = try path_encoder.lineTo(core.PointF32.create(40.0, 20.0));
    //_ = try path_encoder.arcTo(core.PointF32.create(3.0, 3.0), core.PointF32.create(4.0, 2.0));
    _ = try path_encoder.lineTo(core.PointF32.create(10.0, 10.0));
    try path_encoder.finish();

    var path_encoder2 = encoder.pathEncoder(i16);
    try path_encoder2.moveTo(core.PointI16.create(10, 10));
    _ = try path_encoder2.lineTo(core.PointI16.create(20, 20));
    _ = try path_encoder2.lineTo(core.PointI16.create(15, 30));
    _ = try path_encoder2.quadTo(core.PointI16.create(33, 44), core.PointI16.create(100, 100));
    _ = try path_encoder2.cubicTo(
        core.PointI16.create(120, 120),
        core.PointI16.create(70, 130),
        core.PointI16.create(22, 22),
    );
    try path_encoder2.finish();

    var half_planes = try HalfPlanesU16.init(std.testing.allocator);
    defer half_planes.deinit();

    const encoding = encoder.encode();
    var rasterizer = try CpuRasterizer.init(
        std.testing.allocator,
        &half_planes,
        kernel_module.KernelConfig.DEFAULT,
        encoding,
    );
    defer rasterizer.deinit();

    var texture = try Texture.init(std.testing.allocator, core.DimensionsU32{
        .width = 50,
        .height = 50,
    }, texture_module.TextureFormat.RgbaU8);
    defer texture.deinit();
    texture.clear(Colors.WHITE);

    try rasterizer.rasterize(&texture);

    rasterizer.debugPrint(texture);
}
