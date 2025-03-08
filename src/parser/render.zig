const std = @import("std");
const Ast = @import("../Ast.zig");

pub fn renderAst(ast: Ast, stream: anytype) !void {
    if (ast.version) |explicit_version| {
        try stream.print(
            "syntax = \"{s}\";\n",
            .{@tagName(explicit_version)},
        );
    }

    // Either empty or just the root node, nothing for us to do.
    if (ast.nodes.len <= 1) return;

    var w: Writer = .{ .ast = ast };
    try w.printAst(ast, stream);
}

// TODO: maybe unify this with the one in translate.zig?
const Writer = struct {
    ident: usize = 0,
    ast: Ast,

    fn printAst(w: *Writer, ast: Ast, stream: anytype) !void {
        const roots = ast.spanToList(.root);
        for (roots) |member| {
            try stream.writeByteNTimes(' ', w.ident);
            const tag = ast.nodes.items(.tag)[@intFromEnum(member)];
            switch (tag) {
                .message => try w.printMessage(member, stream),
                else => std.debug.print("TODO: render {s}\n", .{@tagName(tag)}),
            }
        }
    }

    fn printMessage(
        w: *Writer,
        node_idx: Ast.Node.Index,
        stream: anytype,
    ) !void {
        const ast = w.ast;
        const tags = ast.nodes.items(.tag);
        const main_tokens = ast.nodes.items(.main_token);
        const datas = ast.nodes.items(.data);

        const ident_token = main_tokens[@intFromEnum(node_idx)].unwrap().?;
        const message_ident = ast.identifier(ident_token);
        const members = ast.spanToList(node_idx);

        try w.print(stream, "\nmessage {s} {{", .{message_ident});

        w.ident += 2;
        for (members) |member| {
            const tag = tags[@intFromEnum(member)];
            switch (tag) {
                .field => {
                    const field_data = datas[@intFromEnum(member)].field;
                    try stream.writeByte('\n');
                    try w.print(
                        stream,
                        "{s} {s} = {s};",
                        .{
                            @tagName(field_data.type),
                            ast.identifier(field_data.field_name),
                            ast.identifier(field_data.field_number),
                        },
                    );
                },
                else => std.debug.print("TODO: render {s}", .{@tagName(tag)}),
            }
        }
        w.ident -= 2;
        if (members.len > 0) try stream.writeByte('\n');
        try w.writeAll(stream, "}\n");
    }

    fn writeAll(
        w: *Writer,
        stream: anytype,
        bytes: []const u8,
    ) !void {
        try stream.writeByteNTimes(' ', w.ident);
        try stream.writeAll(bytes);
    }

    fn writeMultiLine(
        w: *Writer,
        stream: anytype,
        bytes: []const u8,
    ) !void {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| {
            try w.writeAll(stream, line);
            if (lines.index == null) break;
            try stream.writeByte('\n');
        }
    }

    fn print(
        w: *Writer,
        stream: anytype,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        try stream.writeByteNTimes(' ', w.ident);
        try stream.print(fmt, args);
    }
};
