const std = @import("std");
const Tokenizer = @This();

const Ast = @import("../Ast.zig");
const Token = Ast.Token;

source: [:0]const u8,
index: usize = 0,

const State = enum {
    start,
    invalid,
    identifier,
    string_literal,
    int,
};

pub fn next(self: *Tokenizer) Token {
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
