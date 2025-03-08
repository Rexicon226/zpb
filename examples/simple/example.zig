const std = @import("std");
const zpb = @import("zpb");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var example: zpb.Foo = .{
        .a = &.{10},
        .b = 20,
    };
    const bytes = try example.encode(allocator);
    defer allocator.free(bytes);

    std.debug.print("bytes: {}\n", .{std.fmt.fmtSliceHexLower(bytes)});
}
