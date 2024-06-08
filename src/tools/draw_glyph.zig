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

    var raster = try draw.Raster.init(allocator);
    defer raster.deinit();

    const intersections = try draw.Raster.createIntersections(allocator, path, &texture_view);
    defer intersections.deinit();

    std.debug.print("\n============== Intersections\n", .{});
    for (intersections.items) |intersection| {
        std.debug.print("Intersection: shape({}) curve({}) t({}), ({} @ {})\n", .{
            intersection.shape_index,
            intersection.curve_index,
            intersection.getT(),
            intersection.getPoint().x,
            intersection.getPoint().y,
        });
    }
    std.debug.print("==============\n", .{});

    const fragment_intersections = try raster.createFragmentIntersectionsAlloc(allocator, intersections.items);
    defer fragment_intersections.deinit();

    var boundary_fragments = try draw.Raster.unwindFragmentIntersectionsAlloc(allocator, fragment_intersections.items);
    defer boundary_fragments.deinit();

    std.debug.print("\n============== Fragment Intersections\n", .{});
    for (fragment_intersections.items) |fragment_intersection| {
        std.debug.print("Intersection: {}\n", .{fragment_intersection});
    }
    std.debug.print("==============\n", .{});

    // std.debug.print("\n============== Boundary Fragments\n", .{});
    // for (boundary_fragments.items) |fragment| {
    //     std.debug.print("Boundary Fragment: {}\n", .{fragment});
    // }
    // std.debug.print("==============\n", .{});

    std.debug.print("\n============== Boundary Texture\n\n", .{});
    var boundary_texture = try draw.UnmanagedTextureMonotone.create(allocator, core.DimensionsU32{
        .width = dimensions.width + 2,
        .height = dimensions.height + 2,
    });
    defer boundary_texture.deinit(allocator);
    boundary_texture.clear(draw.Monotone{ .a = 0.0 });
    var boundary_texture_view = boundary_texture.createView(core.RectU32.create(core.PointU32{
        .x = 1,
        .y = 1,
    }, core.PointU32{
        .x = dimensions.width + 1,
        .y = dimensions.height + 1,
    })).?;

    for (boundary_fragments.items) |fragment| {
        // const pixel = fragment.getPixel();
        const pixel = fragment.pixel;
        if (pixel.x >= 0 and pixel.y >= 0) {
            boundary_texture_view.getPixelUnsafe(core.PointU32{
                .x = @intCast(pixel.x),
                .y = @intCast(pixel.y),
            }).* = draw.Monotone{
                .a = 1.0,
            };
        }
    }

    for (0..boundary_texture_view.view.getHeight()) |y| {
        std.debug.print("{:0>4}: ", .{y});
        for (boundary_texture_view.getRow(@intCast(y)).?) |pixel| {
            if (pixel.a > 0.0) {
                std.debug.print("#", .{});
            } else {
                std.debug.print(";", .{});
            }
        }

        std.debug.print("\n", .{});
    }

    std.debug.print("==============\n", .{});
}
