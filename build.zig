const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const fixtures_path = "fixtures";
    b.installDirectory(.{
        .source_dir = b.path(fixtures_path),
        .install_dir = .{ .custom = "" },
        .install_subdir = b.pathJoin(&.{"bin/fixtures"}),
    });

    const lib = b.addStaticLibrary(.{
        .name = "scriobh",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const draw_glyph_exe = b.addExecutable(.{
        .name = "draw_glyph",
        .root_source_file = b.path("src/tools/draw_glyph.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });
    draw_glyph_exe.root_module.addImport("scribe", &lib.root_module);
    b.installArtifact(draw_glyph_exe);
    const run_draw_glyph = b.addRunArtifact(draw_glyph_exe);
    run_draw_glyph.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_draw_glyph.addArgs(args);
    }
    const run_draw_glyph_step = b.step("draw_glyph", "Run the draw_glyph tool");
    run_draw_glyph_step.dependOn(&run_draw_glyph.step);

    const svg_exe = b.addExecutable(.{
        .name = "svg",
        .root_source_file = b.path("src/tools/svg.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
    });
    svg_exe.root_module.addImport("scribe", &lib.root_module);
    b.installArtifact(svg_exe);
    const run_svg = b.addRunArtifact(svg_exe);
    run_svg.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_svg.addArgs(args);
    }
    const run_svg_step = b.step("svg", "Run the svg tool");
    run_svg_step.dependOn(&run_svg.step);

    // TODO: This doesn't work yet
    //   Tracking Issue: https://github.com/ziglang/zig/issues/20454
    // const gpu_kernel = b.addStaticLibrary(gpuOptions(b, "kernel", optimize));
    // b.installArtifact(gpu_kernel);
    // test_gpu_exe.root_module.addAnonymousImport("kernel", .{
    //     .root_source_file = gpu_kernel.getEmittedBin(),
    // });

    const encoding_tests = b.addTest(.{
        .name = "test-encoding",
        .root_source_file = b.path("src/test_encoding.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_encoding_tests = b.addRunArtifact(encoding_tests);
    const test_encoding_step = b.step("test-encoding", "Run encoding unit tests");
    test_encoding_step.dependOn(&run_encoding_tests.step);
    const install_encoding_tests = b.addInstallArtifact(encoding_tests, .{});
    const install_encoding_tests_step = b.step("install-test-encoding", "Install encoding unit tests");
    install_encoding_tests_step.dependOn(&install_encoding_tests.step);

    @import("system_sdk").addLibraryPathsTo(draw_glyph_exe);
    @import("system_sdk").addLibraryPathsTo(svg_exe);
    @import("system_sdk").addLibraryPathsTo(lib);

    if (b.lazyDependency("zstbi", .{
        .target = target,
        .optimize = optimize,
    })) |dep| {
        draw_glyph_exe.root_module.addImport("zstbi", dep.module("root"));
        draw_glyph_exe.linkLibrary(dep.artifact("zstbi"));
        svg_exe.root_module.addImport("zstbi", dep.module("root"));
        svg_exe.linkLibrary(dep.artifact("zstbi"));
    }

    if (b.lazyDependency("zdawn", .{
        .target = target,
        .optimize = optimize,
    })) |dep| {
        @import("zdawn").addLibraryPathsTo(draw_glyph_exe);
        draw_glyph_exe.root_module.addImport("zdawn", dep.module("root"));
        draw_glyph_exe.linkLibrary(dep.artifact("zdawn"));
        @import("zdawn").addLibraryPathsTo(svg_exe);
        svg_exe.root_module.addImport("zdawn", dep.module("root"));
        svg_exe.linkLibrary(dep.artifact("zdawn"));
        @import("zdawn").addLibraryPathsTo(lib);
        lib.root_module.addImport("zdawn", dep.module("root"));
        lib.linkLibrary(dep.artifact("zdawn"));
    }
}

pub fn gpuOptions(
    b: *std.Build,
    name: []const u8,
    optimize: std.builtin.OptimizeMode,
) std.Build.StaticLibraryOptions {
    return std.Build.StaticLibraryOptions{
        .name = name,
        .root_source_file = b.path("src/draw/kernel.zig"),
        .target = b.resolveTargetQuery(std.Target.Query{
            .cpu_arch = .spirv64,
            .os_tag = .vulkan,
            .cpu_features_add = std.Target.spirv.featureSet(&.{
                .Int64,
                .Int16,
                .Int8,
                .Float64,
                .Float16,
                .Vector16,
            }),
        }),
        .optimize = optimize,
        .use_llvm = false,
        .use_lld = false,
    };
}
