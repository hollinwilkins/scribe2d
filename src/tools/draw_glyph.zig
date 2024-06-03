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

    const dimensions = core.DimensionsU32{
        .width = 16,
        .height = 16,
    };

    var texture = try draw.UnmanagedTextureRgba.create(allocator, dimensions);
    defer texture.deinit(allocator);
    var texture_view = texture.createView(core.RectU32{
        .min = core.PointU32{
            .x = 0,
            .y = 0,
        },
        .max = core.PointU32{
            .x = dimensions.width,
            .y = dimensions.height,
        },
    }).?;

    path.debug();

    const intersections = try draw.Pen.createIntersections(allocator, path, &texture_view);
    defer intersections.deinit();

    std.debug.print("\n============== Intersections\n", .{});
    for (intersections.items) |intersection| {
        std.debug.print("Intersection: curve({}) t({}), ({} @ {})\n", .{
            intersection.curve_index,
            intersection.intersection.t,
            intersection.intersection.point.x,
            intersection.intersection.point.y,
        });
    }
    std.debug.print("==============\n", .{});

    const boundary_fragments = try draw.Pen.createBoundaryFragmentsAlloc(allocator, intersections.items);
    defer boundary_fragments.deinit();

    std.debug.print("\n============== Boundary Texture\n", .{});
    var bf_index: usize = 0;
    for (0..dimensions.height) |y| {
        while (bf_index < boundary_fragments.items.len and boundary_fragments.items[bf_index].pixel.y < y) {
            bf_index += 1;
        }

        for (0..dimensions.width) |x| {
            while (bf_index < boundary_fragments.items.len and boundary_fragments.items[bf_index].pixel.y == y and boundary_fragments.items[bf_index].pixel.x < x) {
                bf_index += 1;
            }

            if (bf_index < boundary_fragments.items.len) {
                const pixel = boundary_fragments.items[bf_index].pixel;
                if (pixel.y == y and pixel.x == x) {
                    std.debug.print("X", .{});
                } else {
                    std.debug.print(";", .{});
                }
            } else {
                std.debug.print(";", .{});
            }
        }

        std.debug.print("\n", .{});
    }
    std.debug.print("==============\n", .{});
}
