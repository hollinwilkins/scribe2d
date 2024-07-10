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

    _ = args.skip();
    const font_file = args.next() orelse @panic("need to provide a font file");
    const codepoint_str = args.next() orelse @panic("need to provide a codepoint string");
    // const codepoint: u32 = @intCast(codepoint_str[0]);
    const glyph_id: u16 = try std.fmt.parseInt(u16, codepoint_str, 10);
    const size_str = args.next() orelse "16";
    const size = try std.fmt.parseInt(u32, size_str, 10);
    const output_file = args.next() orelse @panic("need to provide output file");

    var face = try text.Face.initFile(allocator, font_file);
    defer face.deinit();

    std.debug.print("Font Info: {s}\n", .{font_file});
    var rt_iter = face.unmanaged.raw_tables.table.iterator();
    while (rt_iter.next()) |table| {
        std.debug.print("Table: {s}\n", .{table.tag.toBytes()});
    }

    var encoder = draw.Encoder.init(allocator);
    defer encoder.deinit();

    const outline_width = 16.0;
    var style = draw.Style{};
    try encoder.encodeColor(draw.ColorU8{
        .r = 255,
        .g = 0,
        .b = 0,
        .a = 255,
    });
    style.setFill(draw.Style.Fill{
        .brush = .color,
    });
    try encoder.encodeColor(draw.ColorU8{
        .r = 0,
        .g = 0,
        .b = 0,
        .a = 255,
    });
    style.setStroke(draw.Style.Stroke{
        .brush = .color,
        .join = .round,
        .width = outline_width,
    });
    try encoder.encodeStyle(style);
    try encoder.encodeTransform(core.TransformF32.Affine.IDENTITY);

    var path_encoder = encoder.pathEncoder(f32);

    _ = try face.outline(glyph_id, @floatFromInt(size), text.GlyphPen.Debug.Instance);
    _ = try face.outline(glyph_id, @floatFromInt(size), path_encoder.glyphPen());

    const bounds = encoder.calculateBounds();

    const dimensions = core.DimensionsU32{
        .width = @intFromFloat(@ceil(bounds.getWidth() + outline_width / 2.0 + 16.0)),
        .height = @intFromFloat(@ceil(bounds.getHeight() + outline_width / 2.0 + 16.0)),
    };

    const translate_center = (core.TransformF32{
        .translate = core.PointF32{
            .x = @floatFromInt(dimensions.width / 2),
            .y = @floatFromInt(dimensions.height / 2),
        },
    }).toAffine();
    encoder.transforms.items[0] = translate_center;

    const encoding = encoder.encode();

    var half_planes = try draw.HalfPlanesU16.init(allocator);
    defer half_planes.deinit();

    const rasterizer_config = draw.CpuRasterizer.Config{
        .run_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
        .debug_flags = draw.CpuRasterizer.Config.RUN_FLAG_ALL,
        .kernel_config = draw.KernelConfig.DEFAULT,
        .flush_texture_span = true,
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
