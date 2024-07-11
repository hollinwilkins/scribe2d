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

    var svg = try scribe.svg.Svg.parseFileAlloc(allocator, svg_file);
    defer svg.deinit();

    var encoder = draw.Encoder.init(allocator);
    defer encoder.deinit();

    try svg.encode(&encoder);

    const scale = (core.TransformF32{
        .scale = core.PointF32.create(0.1, 0.1),
    }).toAffine();
    for (encoder.transforms.items) |*t| {
        t.* = scale.mul(t.*);
    }

    const bounds = encoder.calculateBounds();

    const dimensions = core.DimensionsU32{
        .width = @intFromFloat(@ceil(bounds.getWidth() + 64.0)),
        .height = @intFromFloat(@ceil(bounds.getHeight() + 64.0)),
    };

    const encoding = encoder.encode();

    var half_planes = try draw.HalfPlanesU16.init(allocator);
    defer half_planes.deinit();

    const rasterizer_config = draw.CpuRasterizer.Config{
        .run_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
        .debug_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
        .debug_single_pass = true,
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
