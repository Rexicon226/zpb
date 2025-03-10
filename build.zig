const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const translate = b.addExecutable(.{
        .name = "translate",
        .root_source_file = b.path("src/translate.zig"),
        .target = b.graph.host,
    });
    b.installArtifact(translate);

    const zpb_mod = b.addModule("zpb", .{
        .root_source_file = b.path("src/zpb.zig"),
        .target = b.graph.host,
    });

    const translate_step = b.step("translate", "Runs the translator");
    const run_translate = b.addRunArtifact(translate);
    if (b.args) |args| run_translate.addArgs(args);
    translate_step.dependOn(&run_translate.step);

    const fmt = b.addExecutable(.{
        .name = "fmt",
        .root_source_file = b.path("src/fmt.zig"),
        .target = target,
        .optimize = optimize,
    });

    const fmt_step = b.step("fmt", "Runs the formatter");
    const run_fmt = b.addRunArtifact(fmt);
    if (b.args) |args| run_fmt.addArgs(args);
    fmt_step.dependOn(&run_fmt.step);

    const unit_test = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run the unit tests");
    const run_unit_test = b.addRunArtifact(unit_test);
    test_step.dependOn(&run_unit_test.step);

    try addIntegrationTestCase(
        b,
        "test/encode.zig",
        "test/a.proto",
        target,
        optimize,
        test_step,
        translate,
        zpb_mod,
    );
}

fn addIntegrationTestCase(
    b: *std.Build,
    path: []const u8,
    proto: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    test_step: *std.Build.Step,
    translate: *std.Build.Step.Compile,
    zpb: *std.Build.Module,
) !void {
    const test_exe = b.addTest(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    const run_test = b.addRunArtifact(test_exe);
    test_step.dependOn(&run_test.step);

    const generate_proto = b.addRunArtifact(translate);
    generate_proto.addFileArg(b.path(proto));
    const generated = generate_proto.addOutputFileArg("output.zig");

    const zpb_mod = b.createModule(.{
        .root_source_file = generated,
    });
    zpb_mod.addImport("zpb", zpb);

    test_exe.root_module.addImport("zpb", zpb_mod);
}
