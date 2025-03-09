const std = @import("std");
const Ast = @import("Ast.zig");
const render = @import("parser/render.zig");

fn testRenderImpl(allocator: std.mem.Allocator, source: [:0]const u8) !void {
    const stderr = std.io.getStdErr().writer();

    var parsed = try Ast.parse(allocator, source, "");
    defer parsed.deinit(allocator);

    var buffer: std.ArrayListUnmanaged(u8) = .{};
    defer buffer.deinit(allocator);
    try render.renderAst(parsed, buffer.writer(allocator));

    for (parsed.errors) |parse_error| {
        try parse_error.render(parsed, stderr);
    }
    if (parsed.errors.len != 0) {
        return error.ParseError;
    }

    try std.testing.expectEqualSlices(u8, source, buffer.items);
}

fn testRender(source: [:0]const u8) !void {
    const allocator = std.testing.allocator;
    try std.testing.checkAllAllocationFailures(
        allocator,
        testRenderImpl,
        .{source},
    );
}

test "only syntax" {
    try testRender(
        \\syntax = "proto3";
        \\
    );
}

test "simple message" {
    try testRender(
        \\syntax = "proto3";
        \\
        \\message Foo {}
        \\
    );
}

test "simple message with field" {
    try testRender(
        \\syntax = "proto3";
        \\
        \\message Foo {
        \\  bytes bar = 1;
        \\}
        \\
    );
}

test "multiple messages with multiple fields" {
    try testRender(
        \\syntax = "proto3";
        \\
        \\message Foo {
        \\  bytes bar = 1;
        \\  bytes baz = 1;
        \\}
        \\
        \\message A {
        \\  uint32 B = 1;
        \\}
        \\
    );
}
