const std = @import("std");

pub fn build(b: *std.Build) !void {
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
}
