const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zpb_dep = b.dependency("zpb", .{});
    const zpb_translate = zpb_dep.artifact("translate");

    const generate_proto = b.addRunArtifact(zpb_translate);
    generate_proto.addFileArg(b.path("example.proto"));
    const generated = generate_proto.addOutputFileArg("output.zig");

    const zpb_mod = b.createModule(.{
        .root_source_file = generated,
    });
    zpb_mod.addImport("zpb", zpb_dep.module("zpb"));

    const example = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("example.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("zpb", zpb_mod);

    const run_step = b.step("run", "Runs the example");
    run_step.dependOn(&b.addRunArtifact(example).step);
}
