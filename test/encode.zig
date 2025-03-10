const std = @import("std");
const zpb = @import("zpb");

const expectEqualSlices = std.testing.expectEqualSlices;

test "single field encode" {
    const allocator = std.testing.allocator;
    var example: zpb.A = .{
        .a = 50,
    };
    const bytes = try example.encode(allocator);
    defer allocator.free(bytes);

    try expectEqualSlices(
        u8,
        &.{ 0x08, 0x32 },
        bytes,
    );
}

test "multiple field encode" {
    const allocator = std.testing.allocator;
    var example: zpb.B = .{
        .a = &.{ 10, 20 },
        .b = 30,
        .c = false,
    };
    const bytes = try example.encode(allocator);
    defer allocator.free(bytes);

    try expectEqualSlices(
        u8,
        &.{ 0x0a, 0x02, 0x0a, 0x14, 0x10, 0x1e, 0x18, 0x00 },
        bytes,
    );
}
