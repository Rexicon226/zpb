const std = @import("std");
const Ast = @import("Ast.zig");
const render = @import("parser/render.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    var maybe_input_file: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (maybe_input_file == null) {
            maybe_input_file = arg;
            continue;
        }
        fail("too many arguments", .{});
    }
    const input_file_path = maybe_input_file orelse fail("expected input file", .{});

    const input = try std.fs.cwd().openFile(input_file_path, .{});
    defer input.close();

    const source = try input.readToEndAllocOptions(
        allocator,
        1024 * 1024,
        null,
        @alignOf(u8),
        0,
    );
    defer allocator.free(source);

    var ast = try Ast.parse(allocator, source, input_file_path);
    defer ast.deinit(allocator);

    const stdout = std.io.getStdOut().writer();
    try render.renderAst(ast, stdout);
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    const stderr = std.io.getStdErr().writer();
    stderr.print(fmt ++ "\n", args) catch @panic("failed to print the stderr");
    std.posix.abort();
}
