const std = @import("std");
const scriobh = @import("scriobh");

pub fn main() !void {
    var args = std.process.args();

    _ = args.skip();
    const font_file = args.next() orelse @panic("need to provide a font file");
    const glyph_id_str = args.next() orelse @panic("need to provide a glyph_id");
    const glyph_id = try std.fmt.parseInt(u16, glyph_id_str, 10);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var face = try scriobh.Face.initFile(allocator, font_file);
    defer face.deinit();

    var path_outliner = try scriobh.draw.PathOutliner.init(allocator);
    defer path_outliner.deinit();
    _ = try face.unmanaged.tables.glyf.?.outline(glyph_id, path_outliner.outliner());
    const path = try path_outliner.createPathAlloc(allocator);
    defer path.deinit();
}
