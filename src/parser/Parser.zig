const std = @import("std");
const Ast = @import("../Ast.zig");
const proto = @import("../proto.zig");

const Parser = @This();

const Token = Ast.Token;
const Node = Ast.Node;

gpa: std.mem.Allocator,
source: [:0]const u8,
tokens: std.MultiArrayList(Token),
token_index: u32,
nodes: std.MultiArrayList(Node),
errors: std.ArrayListUnmanaged(Ast.Error),
scratch: std.ArrayListUnmanaged(Node.Index),
extra_data: std.ArrayListUnmanaged(Node.Index),
version: ?proto.Version,

pub fn parse(p: *Parser) !void {
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

fn failMsg(p: *Parser, msg: Ast.Error) error{ ParserError, OutOfMemory } {
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
