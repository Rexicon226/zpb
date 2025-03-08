const std = @import("std");
const proto = @import("proto.zig");
const Ast = @This();

version: proto.Version,
source_path: []const u8,
source: [:0]const u8,
tokens: std.MultiArrayList(Token).Slice,
nodes: std.MultiArrayList(Node).Slice,
extra_data: []const Node.Index,
errors: []const Error,

pub fn parse(gpa: std.mem.Allocator, input_path: []const u8) !Ast {
    const input = try std.fs.cwd().openFile(input_path, .{});
    defer input.close();

    const source = try input.readToEndAllocOptions(
        gpa,
        1024 * 1024,
        null,
        @alignOf(u8),
        0,
    );
    var tokenizer: Tokenizer = .{ .source = source };

    var tokens: std.MultiArrayList(Token) = .{};
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
        .version = proto.Version.DEFAULT,
    };
    defer {
        parser.nodes.deinit(gpa);
        parser.errors.deinit(gpa);
        parser.extra_data.deinit(gpa);
        parser.scratch.deinit(gpa);
    }

    try parser.parse();

    return .{
        .version = parser.version,
        .source_path = input_path,
        .source = source,
        .tokens = tokens.toOwnedSlice(),
        .nodes = parser.nodes.toOwnedSlice(),
        .errors = try parser.errors.toOwnedSlice(gpa),
        .extra_data = try parser.extra_data.toOwnedSlice(gpa),
    };
}

pub fn deinit(ast: *Ast, allocator: std.mem.Allocator) void {
    allocator.free(ast.source);
    ast.tokens.deinit(allocator);
    ast.nodes.deinit(allocator);
    allocator.free(ast.errors);
    allocator.free(ast.extra_data);
}

const Token = struct {
    tag: Tag,
    loc: Loc,

    const Index = enum(u32) { _ };

    const OptionalIndex = enum(u32) {
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

    const keywords = std.StaticStringMap(Tag).initComptime(&.{
        .{ "syntax", .keyword_syntax },
        .{ "message", .keyword_message },
    });

    const Tag = enum {
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

    const OptionalIndex = enum(u32) {
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

    const Span = struct {
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

const Tokenizer = struct {
    source: [:0]const u8,
    index: usize = 0,

    const State = enum {
        start,
        invalid,
        identifier,
        string_literal,
        int,
    };

    fn next(self: *Tokenizer) Token {
        var result: Token = .{
            .tag = undefined,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };

        state: switch (State.start) {
            .start => switch (self.source[self.index]) {
                0 => {
                    if (self.index == self.source.len) {
                        return .{
                            .tag = .eof,
                            .loc = .{
                                .start = self.index,
                                .end = self.index,
                            },
                        };
                    } else continue :state .invalid;
                },
                ' ', '\n', '\t', '\r' => {
                    self.index += 1;
                    result.loc.start = self.index;
                    continue :state .start;
                },
                '"' => {
                    result.tag = .string_literal;
                    continue :state .string_literal;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    result.tag = .identifier;
                    continue :state .identifier;
                },
                '=' => {
                    self.index += 1;
                    result.tag = .equal;
                },
                ';' => {
                    result.tag = .semicolon;
                    self.index += 1;
                },
                '{' => {
                    result.tag = .l_brace;
                    self.index += 1;
                },
                '}' => {
                    result.tag = .r_brace;
                    self.index += 1;
                },
                '0'...'9' => {
                    result.tag = .number_literal;
                    self.index += 1;
                    continue :state .int;
                },
                else => continue :state .invalid,
            },
            .invalid => {
                self.index += 1;
                switch (self.source[self.index]) {
                    0 => if (self.index == self.source.len) {
                        result.tag = .invalid;
                    } else continue :state .invalid,
                    '\n' => result.tag = .invalid,
                    else => continue :state .invalid,
                }
            },
            .string_literal => {
                self.index += 1;
                switch (self.source[self.index]) {
                    0 => {
                        if (self.index != self.source.len) {
                            continue :state .invalid;
                        } else {
                            result.tag = .invalid;
                        }
                    },
                    '\n' => result.tag = .invalid,
                    '"' => self.index += 1,
                    else => continue :state .string_literal,
                }
            },
            .int => switch (self.source[self.index]) {
                '0'...'9' => {
                    self.index += 1;
                    continue :state .int;
                },
                else => {},
            },
            .identifier => {
                self.index += 1;
                switch (self.source[self.index]) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                    else => {
                        if (Token.keywords.get(self.source[result.loc.start..self.index])) |tag| {
                            result.tag = tag;
                        }
                    },
                }
            },
        }

        result.loc.end = self.index;
        return result;
    }
};

const Parser = struct {
    gpa: std.mem.Allocator,
    source: [:0]const u8,
    tokens: std.MultiArrayList(Token),
    token_index: u32,
    nodes: std.MultiArrayList(Node),
    errors: std.ArrayListUnmanaged(Error),
    scratch: std.ArrayListUnmanaged(Node.Index),
    extra_data: std.ArrayListUnmanaged(Node.Index),
    version: proto.Version,

    fn parse(p: *Parser) !void {
        try p.nodes.append(p.gpa, .{
            .tag = .root,
            .main_token = .none,
            .data = undefined,
        });

        p.parseSyntax() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParserError => {
                std.debug.assert(p.errors.items.len > 0);
                return;
            },
        };

        const defs = p.parseTopLevelDefinitions() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParserError => {
                std.debug.assert(p.errors.items.len > 0);
                return;
            },
        };

        if (p.tokens.get(p.token_index).tag != .eof) {
            return p.failExpecting(.eof);
        }
        p.nodes.items(.data)[0] = .{ .span = defs };
    }

    fn parseTopLevelDefinitions(p: *Parser) !Node.Span {
        const scratch_top = p.scratch.items.len;
        defer p.scratch.shrinkRetainingCapacity(scratch_top);

        if (p.token_index >= p.tokens.len) {
            return p.failExpecting(.eof);
        }

        while (true) {
            switch (p.tokens.get(p.token_index).tag) {
                .keyword_message,
                => {
                    const message = try p.parseMessage();
                    try p.scratch.append(p.gpa, message);
                },
                .eof => break,
                else => return p.failMsg(.{
                    .tag = .expected_top_level_def,
                    .token = @enumFromInt(p.token_index),
                }),
            }
        }

        const items = p.scratch.items[scratch_top..];
        return p.listToSpan(items);
    }

    fn parseMessage(p: *Parser) !Node.Index {
        const scratch_top = p.scratch.items.len;
        defer p.scratch.shrinkRetainingCapacity(scratch_top);

        _ = try p.expectToken(.keyword_message);
        const ident_token = try p.expectToken(.identifier);
        _ = try p.expectToken(.l_brace);

        while (true) {
            const maybe_field = try p.expectMessageField();
            if (maybe_field.unwrap()) |field| {
                try p.scratch.append(p.gpa, field);
                continue;
            }

            switch (p.tokens.get(p.token_index).tag) {
                .r_brace => break,
                else => {},
            }

            @panic("TODO: non-message field error");
        }
        _ = try p.expectToken(.r_brace);

        const items = p.scratch.items[scratch_top..];
        const span = try p.listToSpan(items);

        return p.addNode(.{
            .tag = .message,
            .main_token = .wrap(ident_token),
            .data = .{ .span = span },
        });
    }

    fn expectMessageField(p: *Parser) !Node.OptionalIndex {
        const ty, const type_token = p.expectType() orelse return .none;
        const field_name = try p.expectToken(.identifier);
        _ = try p.expectToken(.equal);
        const field_number = try p.expectToken(.number_literal);
        _ = try p.expectToken(.semicolon);

        return .wrap(try p.addNode(.{
            .tag = .field,
            .main_token = .wrap(type_token),
            .data = .{ .field = .{
                .type = ty,
                .field_name = field_name,
                .field_number = field_number,
            } },
        }));
    }

    fn expectType(p: *Parser) ?struct { proto.Type, Token.Index } {
        const type_token = p.eatToken(.identifier) orelse return null;
        const type_ident = p.ident(type_token);
        const ty = std.meta.stringToEnum(
            proto.Type,
            type_ident,
        ) orelse return null;
        return .{ ty, type_token };
    }

    /// `proto = [syntax] ...`
    fn parseSyntax(p: *Parser) !void {
        switch (p.getToken(p.nextToken()).tag) {
            .keyword_syntax => {
                _ = try p.expectToken(.equal);
                const version_token = try p.expectToken(.string_literal);
                const version_ident = p.stringLiteral(version_token);

                const version = std.meta.stringToEnum(
                    proto.Version,
                    version_ident,
                ) orelse return p.failMsg(.{
                    .tag = .invalid_version,
                    .token = version_token,
                });

                if (!proto.Version.SUPPORTED.get(version)) {
                    return p.failMsg(.{
                        .tag = .unsupported_version,
                        .token = version_token,
                        .extra = .{ .version = version },
                    });
                }
                _ = try p.expectToken(.semicolon);

                p.version = version;
            },
            else => {},
        }
    }

    fn stringLiteral(p: *Parser, idx: Token.Index) []const u8 {
        // The string literal needs to either (start and end) with " or '.
        // We string off that, to normalize it to ' in error messages and such.
        const string = p.ident(idx);
        return string[1..][0 .. string.len - 2];
    }

    fn ident(p: *Parser, idx: Token.Index) []const u8 {
        const token = p.getToken(idx);
        return p.source[token.loc.start..token.loc.end];
    }

    fn eatToken(p: *Parser, tag: Token.Tag) ?Token.Index {
        return if (p.tokens.get(p.token_index).tag == tag) p.nextToken() else null;
    }

    fn expectToken(p: *Parser, tag: Token.Tag) !Token.Index {
        const token = p.tokens.get(p.token_index);
        if (token.tag != tag) {
            return p.failExpecting(tag);
        }
        return p.nextToken();
    }

    fn nextToken(p: *Parser) Token.Index {
        const result = p.token_index;
        p.token_index += 1;
        return @enumFromInt(result);
    }

    fn getToken(p: *Parser, idx: Token.Index) Token {
        return p.tokens.get(@intFromEnum(idx));
    }

    fn failExpecting(p: *Parser, expected_tag: Token.Tag) error{ ParserError, OutOfMemory } {
        @branchHint(.cold);
        return p.failMsg(.{
            .tag = .expected_token,
            .token = @enumFromInt(p.token_index),
            .extra = .{ .expected_tag = expected_tag },
        });
    }

    fn failMsg(p: *Parser, msg: Error) error{ ParserError, OutOfMemory } {
        @branchHint(.cold);
        try p.errors.append(p.gpa, msg);
        return error.ParserError;
    }

    fn addNode(p: *Parser, node: Node) !Node.Index {
        const result: Node.Index = @enumFromInt(p.nodes.len);
        try p.nodes.append(p.gpa, node);
        return result;
    }

    fn listToSpan(p: *Parser, list: []const Node.Index) !Node.Span {
        try p.extra_data.appendSlice(p.gpa, list);
        return .{
            .start = @enumFromInt(p.extra_data.items.len - list.len),
            .end = @enumFromInt(p.extra_data.items.len),
        };
    }
};

const Error = struct {
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
