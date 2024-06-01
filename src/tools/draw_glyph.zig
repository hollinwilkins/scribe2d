const std = @import("std");
const scriobh = @import("scriobh");
const text = scriobh.text;
const draw = scriobh.draw;
const core = scriobh.core;

pub fn main() !void {
    var args = std.process.args();

    _ = args.skip();
    const font_file = args.next() orelse @panic("need to provide a font file");
    const glyph_id_str = args.next() orelse @panic("need to provide a glyph_id");
    const glyph_id = try std.fmt.parseInt(u16, glyph_id_str, 10);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var face = try text.Face.initFile(allocator, font_file);
    defer face.deinit();

    var path_outliner = try draw.PathOutliner.init(allocator);
    defer path_outliner.deinit();
    _ = try face.unmanaged.tables.glyf.?.outline(glyph_id, path_outliner.textOutliner());
    const path = try path_outliner.createPathAlloc(allocator);
    defer path.deinit();

    var pen = draw.Pen{};
    var texture = try draw.UnmanagedTextureRgba.create(std.testing.allocator, core.DimensionsU32{
        .width = 64,
        .height = 64,
    });
    const texture_view = texture.createView(core.RectU32{
        .min = core.PointU32{
            .x = 0,
            .y = 0,
        },
        .max = core.PointU32{
            .x = 64,
            .y = 64,
        },
    }).?;
    pen.drawToTextureViewRgba(std.testing.allocator, path, texture_view);

    path.debug();
}
