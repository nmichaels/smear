const std = @import("std");

// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const smeartime = b.addTranslateC(.{
        .root_source_file = b.path("src/smear/smeartime.h"),
        .target = target,
        .optimize = optimize,
    });

    const time_mod = smeartime.createModule();

    const version = b.addTranslateC(.{
        .root_source_file = b.path("include/smear/version.h"),
        .target = target,
        .optimize = optimize,
    });

    var smearo = b.addObject(.{
        .name = "smear",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/smear/smear.zig"),
            .target = target,
            .imports = &.{
                .{ .name = "smeartime", .module = time_mod },
                .{ .name = "version", .module = version.createModule() },
            },
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        }),
    });
    smearo.bundle_compiler_rt = true;
    smearo.root_module.addIncludePath(b.path("include"));
    smearo.root_module.addIncludePath(b.path("src/cancelq"));
    smearo.root_module.addIncludePath(b.path("src/smear"));
    const smearo_install = b.addInstallArtifact(
        smearo,
        .{
            .dest_dir = .{ .override = .{ .custom = "../obj" } },
        },
    );
    b.getInstallStep().dependOn(&smearo_install.step);

    var cancelq = b.addObject(.{
        .name = "cancellable",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cancelq/cancellable.zig"),
            .imports = &.{
                .{
                    .name = "smeartime",
                    .module = time_mod,
                },
            },
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        }),
    });

    // We need this for the stack checking in safe build modes. I
    // suppose we could leave it out in ReleaseFast and ReleaseSmall,
    // but...the linker will drop unused symbols anyway.
    cancelq.bundle_compiler_rt = true;
    cancelq.root_module.addIncludePath(b.path("src/smear"));
    smearo.root_module.addImport("cancelq", cancelq.root_module);

    const cancelq_install = b.addInstallArtifact(
        cancelq,
        .{
            // Wow, that's pretty hacky but hey it works.
            .dest_dir = .{ .override = .{ .custom = "../obj" } },
        },
    );
    b.getInstallStep().dependOn(&cancelq_install.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const cancelq_unit_tests = b.addTest(.{
        .root_module = cancelq.root_module,
        .use_llvm = true,
    });

    const run_cancelq_unit_tests = b.addRunArtifact(cancelq_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_cancelq_unit_tests.step);
}
