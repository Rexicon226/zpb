const std = @import("std");
const proto = @import("proto.zig");
const Ast = @This();

const Tokenizer = @import("parser/Tokenizer.zig");
const Parser = @import("parser/Parser.zig");

version: ?proto.Version,
source_path: []const u8,
source: [:0]const u8,
tokens: std.MultiArrayList(Token).Slice,
nodes: std.MultiArrayList(Node).Slice,
extra_data: []const Node.Index,
errors: []const Error,

pub fn parse(
    gpa: std.mem.Allocator,
    source: [:0]const u8,
    input_path: []const u8,
) !Ast {
    var tokenizer: Tokenizer = .{ .source = source };

    var tokens: std.MultiArrayList(Token) = .{};
    defer tokens.deinit(gpa);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(gpa, token);
        if (token.tag == .eof) break;
    }

    var parser: Parser = .{
        .gpa = gpa,
        .source = source,
        .tokens = tokens,
        .token_index = 0,
        .nodes = .{},
        .errors = .{},
        .scratch = .{},
        .extra_data = .{},
        .version = null,
    };
    defer {
        parser.nodes.deinit(gpa);
        parser.errors.deinit(gpa);
        parser.extra_data.deinit(gpa);
        parser.scratch.deinit(gpa);
    }

    try parser.parse();

    const errors = try parser.errors.toOwnedSlice(gpa);
    errdefer gpa.free(errors);
    const extra_data = try parser.extra_data.toOwnedSlice(gpa);

    return .{
        .version = parser.version,
        .source_path = input_path,
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .errors = errors,
        .extra_data = extra_data,
    };
}

pub fn deinit(ast: *Ast, allocator: std.mem.Allocator) void {
    ast.tokens.deinit(allocator);
    ast.nodes.deinit(allocator);
    allocator.free(ast.errors);
    allocator.free(ast.extra_data);
}

fn getToken(ast: Ast, idx: Token.Index) Token {
    return ast.tokens.get(@intFromEnum(idx));
}

fn stringLiteral(ast: Ast, idx: Token.Index) []const u8 {
    const string = ast.identifier(idx);
    return string[1..][0 .. string.len - 2];
}

pub fn identifier(ast: Ast, idx: Token.Index) []const u8 {
    const token = ast.getToken(idx);
    return ast.source[token.loc.start..token.loc.end];
}

pub fn spanToList(ast: Ast, idx: Node.Index) []const Node.Index {
    const root = ast.nodes.items(.data)[@intFromEnum(idx)].span;
    return ast.extra_data[@intFromEnum(root.start)..@intFromEnum(root.end)];
}

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Index = enum(u32) { _ };

    pub const OptionalIndex = enum(u32) {
        none = std.math.maxInt(u32),
        _,

        pub fn unwrap(o: OptionalIndex) ?Index {
            return switch (o) {
                .none => null,
                else => @enumFromInt(@intFromEnum(o)),
            };
        }

        pub fn wrap(i: Index) OptionalIndex {
            return @enumFromInt(@intFromEnum(i));
        }
    };

    const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(&.{
        .{ "syntax", .keyword_syntax },
        .{ "message", .keyword_message },
    });

    pub const Tag = enum {
        string_literal,
        number_literal,
        identifier,
        equal,
        semicolon,
        l_brace,
        r_brace,
        keyword_syntax,
        keyword_message,
        eof,
        invalid,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .keyword_message => "message",
                .keyword_syntax => "syntax",
                .equal => "=",
                .semicolon => ";",
                .l_brace => "{",
                .r_brace => "}",
                else => null,
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .string_literal => "a string literal",
                .number_literal => "a number literal",
                .eof => "EOF",
                .identifier => "an identifier",
                else => unreachable,
            };
        }
    };
};

pub const Node = struct {
    tag: Tag,
    main_token: Token.OptionalIndex,
    data: Data,

    pub const Index = enum(u32) {
        root,
        _,
    };

    pub const OptionalIndex = enum(u32) {
        none = std.math.maxInt(u32),
        _,

        pub fn unwrap(o: OptionalIndex) ?Index {
            return switch (o) {
                .none => null,
                else => @enumFromInt(@intFromEnum(o)),
            };
        }

        pub fn wrap(i: Index) OptionalIndex {
            return @enumFromInt(@intFromEnum(i));
        }
    };

    const Tag = enum {
        root,
        field,
        message,
    };

    pub const Span = struct {
        start: Node.Index,
        end: Node.Index,
    };

    pub const Data = union(enum) {
        span: Span,
        field: Field,

        pub const Field = struct {
            type: proto.Type,
            field_name: Token.Index,
            field_number: Token.Index,
        };
    };
};

pub const Error = struct {
    tag: Tag,
    token: Token.Index,
    extra: Extra = .{ .none = {} },

    const Tag = enum {
        unsupported_version,
        expected_top_level_def,
        invalid_version,
        expected_token,
    };

    const Extra = union {
        none: void,
        version: proto.Version,
        expected_tag: Token.Tag,
    };

    pub fn render(err: Error, ast: Ast, stderr: anytype) !void {
        const ttyconf = std.zig.Color.get_tty_conf(.auto);
        try ttyconf.setColor(stderr, .bold);

        // Somehow an invalid token.
        if (@intFromEnum(err.token) >= ast.tokens.len) {
            try ttyconf.setColor(stderr, .red);
            try stderr.writeAll("error: ");
            try ttyconf.setColor(stderr, .reset);
            try ttyconf.setColor(stderr, .bold);
            try stderr.writeAll("unexpected EOF\n");
            try ttyconf.setColor(stderr, .reset);
            return;
        }

        const token = ast.getToken(err.token);
        const byte_offset = token.loc.start;
        const err_loc = std.zig.findLineColumn(ast.source, byte_offset);

        try stderr.print("{s}:{d}:{d}: ", .{
            ast.source_path,
            err_loc.line + 1,
            err_loc.column + 1,
        });
        try ttyconf.setColor(stderr, .red);
        try stderr.writeAll("error: ");
        try ttyconf.setColor(stderr, .reset);

        try ttyconf.setColor(stderr, .bold);
        try err.write(ast, stderr);
        try stderr.writeByte('\n');
        try ttyconf.setColor(stderr, .reset);
    }

    fn write(err: Error, ast: Ast, stderr: anytype) !void {
        const token_tags = ast.tokens.items(.tag);
        switch (err.tag) {
            .invalid_version => {
                const string_literal = ast.stringLiteral(err.token);
                return stderr.print(
                    "expected a valid protobuf version, found '{s}'",
                    .{string_literal},
                );
            },
            .unsupported_version => {
                const unsupported = err.extra.version;
                return stderr.print(
                    "found unsupported protobuf version '{s}'",
                    .{@tagName(unsupported)},
                );
            },
            .expected_top_level_def => {
                const found_tag = token_tags[@intFromEnum(err.token)];
                return stderr.print(
                    "expected top level definition, found '{s}'",
                    .{found_tag.symbol()},
                );
            },
            .expected_token => {
                const found_tag = token_tags[@intFromEnum(err.token)];
                const expected_symbol = err.extra.expected_tag.symbol();
                switch (found_tag) {
                    .invalid => return stderr.print(
                        "expected '{s}', found invalid bytes",
                        .{expected_symbol},
                    ),
                    else => return stderr.print(
                        "expected '{s}', found '{s}'",
                        .{ expected_symbol, found_tag.symbol() },
                    ),
                }
            },
        }
    }
};

fn testParse(_: void, input: []const u8) !void {
    const allocator = std.testing.allocator;
    const null_source = try allocator.dupeZ(u8, input);
    defer allocator.free(null_source);

    var parsed = try Ast.parse(allocator, null_source, "fuzz");
    defer parsed.deinit(allocator);
}

test "fuzz parser" {
    try std.testing.fuzz({}, testParse, .{});
}
