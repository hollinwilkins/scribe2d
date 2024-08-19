const std = @import("std");
const scribe = @import("scribe");
const zstbi = @import("zstbi");
const text = scribe.text;
const draw = scribe.draw;
const core = scribe.core;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();
    const svg_file = args.next() orelse @panic("need to provide svg file");
    const output_file = args.next() orelse @panic("need to provide output file");

    _ = svg_file;
    // var svg = try scribe.svg.Svg.parseFileAlloc(allocator, svg_file);
    // defer svg.deinit();

    var encoder = draw.Encoder.init(allocator);
    defer encoder.deinit();

    var style = draw.Style{};
    style.setFill(draw.Style.Fill{
        .brush = .color,
    });
    try encoder.encodeColor(draw.ColorU8{
        .a = 255,
    });
    try encoder.encodeStyle(style);

    {
        var path_encoder = encoder.pathEncoder(f32);
        defer path_encoder.close();
        try path_encoder.moveTo(0.0, 0.0);
        try path_encoder.lineTo(10.0, 10.0);
        try path_encoder.lineTo(0.0, 5.0);
        try path_encoder.lineTo(0.0, 0.0);
    }

    // try svg.encode(&encoder);
    const bounds = encoder.calculateBounds();

    const center = (core.TransformF32{
        .translate = core.PointF32.create(-bounds.min.x + 32.0, -bounds.min.y + 32.0),
    }).toAffine();

    for (encoder.transforms.items) |*tf| {
        tf.* = center.mul(tf.*);
    }

    const dimensions = core.DimensionsU32{
        .width = @intFromFloat(@ceil(bounds.getWidth()) + 64.0),
        .height = @intFromFloat(@ceil(bounds.getHeight()) + 64.0),
    };

    const encoding = encoder.encode();

    var half_planes = try draw.HalfPlanesU16.init(allocator);
    defer half_planes.deinit();

    const rasterizer_config = draw.CpuRasterizer.Config{
        .run_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
        .debug_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
        // .debug_flags = draw.CpuRasterizer.Config.RUN_FLAG_ESTIMATE_SEGMENTS,
        // .debug_single_pass = true,
        .kernel_config = draw.KernelConfig.DEFAULT,
        // .flush_texture_span = false,
    };
    var rasterizer = try draw.CpuRasterizer.init(
        allocator,
        &half_planes,
        rasterizer_config,
        encoding,
    );
    defer rasterizer.deinit();

    zstbi.init(allocator);
    defer zstbi.deinit();

    var image = try zstbi.Image.createEmpty(
        dimensions.width,
        dimensions.height,
        3,
        .{},
    );
    defer image.deinit();

    var texture = draw.TextureUnmanaged{
        .dimensions = dimensions,
        .format = draw.TextureFormat.RgbU8,
        .bytes = image.data,
    };
    texture.clear(draw.Colors.WHITE);

    try rasterizer.rasterize(&texture);

    rasterizer.debugPrint(texture);

    try image.writeToFile(output_file, .png);
}
