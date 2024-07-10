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
    const output_file = args.next() orelse @panic("need to provide output file");

    var encoder = draw.Encoder.init(allocator);
    defer encoder.deinit();

    const outline_width = 8.0;
    var style = draw.Style{};
    // try encoder.encodeColor(draw.ColorU8{
    //     .r = 0,
    //     .g = 0,
    //     .b = 0,
    //     .a = 255,
    // });
    // style.setFill(draw.Style.Fill{
    //     .brush = .color,
    // });
    try encoder.encodeColor(draw.ColorU8{
        .r = 255,
        .g = 0,
        .b = 0,
        .a = 255,
    });
    style.setStroke(draw.Style.Stroke{
        .brush = .color,
        .join = .round,
        .start_cap = .square,
        .end_cap = .square,
        .width = outline_width,
    });
    try encoder.encodeStyle(style);
    try encoder.encodeTransform((core.TransformF32{
        .scale = core.PointF32{
            .x = 10.0,
            .y = 10.0,
        }
    }).toAffine());

    var path_encoder = encoder.pathEncoder(f32);
    try path_encoder.moveTo(core.PointF32{
        .x = 1.0,
        .y = 1.1,
    });
    _ = try path_encoder.lineTo(core.PointF32{
        .x = 5.2,
        .y = 5.5,
    });
    _ = try path_encoder.quadTo(core.PointF32{
        .x = 5.0,
        .y = 0.0,
    }, core.PointF32{
        .x = 3.0,
        .y = 1.0,
    });
    try path_encoder.finish();

    const bounds = encoder.calculateBounds();

    const dimensions = core.DimensionsU32{
        .width = @intFromFloat(@ceil(bounds.getWidth() + outline_width / 2.0 + 4.0)),
        .height = @intFromFloat(@ceil(bounds.getHeight() + outline_width / 2.0 + 4.0)),
    };

    // const translate_center = (core.TransformF32{
    //     .translate = core.PointF32{
    //         .x = 2.0,
    //         .y = 2.0,
    //     },
    // }).toAffine();
    // encoder.transforms.items[0] = translate_center.mul(encoder.transforms.items[0]);

    const encoding = encoder.encode();

    var half_planes = try draw.HalfPlanesU16.init(allocator);
    defer half_planes.deinit();

    const rasterizer_config = draw.CpuRasterizer.Config{
        .run_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
        .debug_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
        .debug_single_pass = false,
        .kernel_config = draw.KernelConfig.SERIAL,
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
        .format = draw.TextureFormat.SrgbU8,
        .bytes = image.data,
    };
    texture.clear(draw.Colors.WHITE);

    try rasterizer.rasterize(&texture);

    rasterizer.debugPrint(texture);

    try image.writeToFile(output_file, .png);
}
