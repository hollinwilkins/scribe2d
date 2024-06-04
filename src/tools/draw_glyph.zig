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
    const size_str = args.next() orelse "16";
    const size = try std.fmt.parseInt(u32, size_str, 10);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var face = try text.Face.initFile(allocator, font_file);
    defer face.deinit();

    var pen = try draw.Pen.init(allocator);
    defer pen.deinit();
    _ = try face.unmanaged.tables.glyf.?.outline(glyph_id, pen.textOutliner());
    const path = try pen.createPathAlloc(allocator);
    defer path.deinit();

    const dimensions = core.DimensionsU32{
        .width = size,
        .height = size,
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

    const intersections = try draw.Raster.createIntersections(allocator, path, &texture_view);
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

    const fragment_intersections = try draw.Raster.createFragmentIntersectionsAlloc(allocator, intersections.items);
    defer fragment_intersections.deinit();

    var boundary_fragments = try draw.Raster.unwindFragmentIntersectionsAlloc(allocator, fragment_intersections.items);
    defer boundary_fragments.deinit();

    std.debug.print("\n============== Fragment Intersections\n", .{});
    for (fragment_intersections.items) |fragment_intersection| {
        std.debug.print("Intersection: {}\n", .{fragment_intersection});
    }
    std.debug.print("==============\n", .{});

    std.debug.print("\n============== Boundary Fragments\n", .{});
    for (boundary_fragments.items) |fragment| {
        std.debug.print("Boundary Fragment: {}\n", .{fragment});
    }
    std.debug.print("==============\n", .{});

    std.debug.print("\n============== Boundary Texture\n", .{});
    const x_start: i32 = -1;
    const x_end: i32 = @intCast(dimensions.width + 1);
    const x_range: usize = @intCast(x_end - x_start);
    const y_start: i32 = -1;
    const y_end: i32 = @intCast(dimensions.height + 1);
    const y_range: usize = @intCast(y_end - y_start);
    std.debug.print("Y START: {}, Y END: {}\n", .{ y_start, y_end });
    var bf_index: usize = 0;
    for (0..y_range) |y_offset| {
        const y = y_start + @as(i32, @intCast(y_offset));
        while (bf_index < fragment_intersections.items.len and fragment_intersections.items[bf_index].pixel.y < y) {
            bf_index += 1;
        }

        std.debug.print("{:0>4}: ", .{y});

        for (0..x_range) |x_offset| {
            const x = x_start + @as(i32, @intCast(x_offset));
            while (bf_index < fragment_intersections.items.len and fragment_intersections.items[bf_index].pixel.y == y and fragment_intersections.items[bf_index].pixel.x < x) {
                bf_index += 1;
            }

            if (bf_index < fragment_intersections.items.len) {
                const pixel = fragment_intersections.items[bf_index].pixel;
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
