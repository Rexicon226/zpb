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

    _ = b.addModule("zpb", .{
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
    const run_test = b.addRunArtifact(unit_test);
    if (b.args) |args| run_test.addArgs(args);
    test_step.dependOn(&run_test.step);
}
