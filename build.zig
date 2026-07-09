const std = @import("std");

// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const smeartime = b.createModule(.{
        .root_source_file = b.path("src/smeartime.zig"),
        .target = target,
        .optimize = optimize,
    });

    const version = b.addTranslateC(.{
        .root_source_file = b.path("include/smear/version.h"),
        .target = target,
        .optimize = optimize,
    });

    const cancelq = b.createModule(.{
        .root_source_file = b.path("src/cancellable.zig"),
        .imports = &.{.{ .name = "smeartime", .module = smeartime }},
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });

    const smear = b.createModule(.{
        .root_source_file = b.path("src/smear.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "smeartime", .module = smeartime },
            .{ .name = "version", .module = version.createModule() },
            .{ .name = "cancelq", .module = cancelq },
        },
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
        .strip = true,
    });

    var smearo = b.addObject(.{
        .name = "smear",
        .root_module = smear,
    });
    smearo.bundle_compiler_rt = true;
    smearo.root_module.addIncludePath(b.path("include"));
    smearo.root_module.addIncludePath(b.path("src"));

    const smeara = b.addLibrary(
        .{
            .name = "smear",
            .root_module = smear,
        },
    );

    const smeara_install = b.addInstallArtifact(
        smeara,
        .{ .dest_dir = .{ .override = .{ .custom = "../" } } },
    );
    b.getInstallStep().dependOn(&smeara_install.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const cancelq_unit_tests = b.addTest(.{
        .root_module = cancelq,
        .use_llvm = true,
    });

    const run_cancelq_unit_tests = b.addRunArtifact(cancelq_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_cancelq_unit_tests.step);
}
