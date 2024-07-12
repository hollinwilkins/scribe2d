const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "mrubyc",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    lib.addIncludePath(b.path("mrubyc/src"));
    lib.addIncludePath(b.path("mrubyc/hal/posix"));
    lib.addCSourceFiles(.{ .files = &sources, .flags = &.{} });
    lib.installHeadersDirectory(b.path("mrubyc/src"), "mrubyc", .{});


    const zruby_module = b.addModule("zruby", .{
        .root_source_file = b.path("src/root.zig"),
    });

    zruby_module.linkLibrary(lib);

    b.installArtifact(lib);
}

const sources = [_][]const u8{
    "mrubyc/src/alloc.c",
    "mrubyc/src/c_array.c",
    "mrubyc/src/c_hash.c",
    "mrubyc/src/c_math.c",
    "mrubyc/src/c_numeric.c",
    "mrubyc/src/c_object.c",
    "mrubyc/src/c_range.c",
    "mrubyc/src/c_string.c",
    "mrubyc/src/class.c",
    "mrubyc/src/console.c",
    "mrubyc/src/error.c",
    "mrubyc/src/global.c",
    "mrubyc/src/keyvalue.c",
    "mrubyc/src/load.c",
    "mrubyc/src/mrblib.c",
    "mrubyc/src/rrt0.c",
    "mrubyc/src/symbol.c",
    "mrubyc/src/value.c",
    "mrubyc/src/vm.c",
    "mrubyc/hal/posix/hal.c",
};
