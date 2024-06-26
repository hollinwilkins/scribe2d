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
    const install_fixtures_step = b.addInstallDirectory(.{
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
    run_draw_glyph_step.dependOn(&install_fixtures_step.step);

    // TODO: This doesn't work yet
    //   Tracking Issue: https://github.com/ziglang/zig/issues/20454
    // const gpu_kernel = b.addStaticLibrary(gpuOptions(b, "kernel", optimize));
    // b.installArtifact(gpu_kernel);
    // test_gpu_exe.root_module.addAnonymousImport("kernel", .{
    //     .root_source_file = gpu_kernel.getEmittedBin(),
    // });

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    if (b.lazyDependency("zstbi", .{
        .target = target,
        .optimize = optimize,
    })) |dep| {
        draw_glyph_exe.root_module.addImport("zstbi", dep.module("root"));
        draw_glyph_exe.linkLibrary(dep.artifact("zstbi"));
        exe_unit_tests.root_module.addImport("zstbi", dep.module("root"));
        exe_unit_tests.linkLibrary(dep.artifact("zstbi"));
    }

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    const test_install_step = b.step("test-install", "Run unit tests");
    const lib_unit_tests_install = b.addInstallArtifact(lib_unit_tests, .{});
    test_install_step.dependOn(&install_fixtures_step.step);
    test_install_step.dependOn(&lib_unit_tests_install.step);
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
