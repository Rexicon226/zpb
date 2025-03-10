const std = @import("std");
const proto = @import("proto.zig");

pub fn Info(T: type) type {
    return std.enums.EnumFieldStruct(
        std.meta.FieldEnum(T),
        FieldDesciptor,
        null,
    );
}

pub const FieldDesciptor = struct {
    field_number: ?u32,
    field_type: proto.Type,
};

const Tag = packed struct(u32) {
    type: proto.WireType,
    number: u29,
};

pub fn MessageMixin(T: type) type {
    return struct {
        const Mixin = @This();

        pub fn encode(parent: *const T, allocator: std.mem.Allocator) ![]const u8 {
            var w: Writer = .{ .gpa = allocator, .buffer = .{} };
            inline for (@typeInfo(T).@"struct".fields) |field| {
                switch (@typeInfo(field.type)) {
                    .optional => @compileError("TODO: optional"),
                    else => try w.encodeField(
                        @field(T.__info, field.name),
                        @field(parent, field.name),
                    ),
                }
            }
            return w.buffer.toOwnedSlice(allocator);
        }
    };
}

const Writer = struct {
    gpa: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),

    fn encodeVarInt(w: *Writer, value: u64) !void {
        const writer = w.buffer.writer(w.gpa);
        try std.leb.writeUleb128(writer, value);
    }

    fn encodeBytes(w: *Writer, bytes: []const u8) !void {
        try w.encodeVarInt(bytes.len);
        try w.buffer.appendSlice(w.gpa, bytes);
    }

    fn encodeField(
        w: *Writer,
        comptime fd: FieldDesciptor,
        value: anytype,
    ) !void {
        switch (fd.field_type) {
            .bool => {
                try w.encodeTag(fd);
                try w.encodeVarInt(@intFromBool(value));
            },
            .uint32, .uint64 => {
                try w.encodeTag(fd);
                try w.encodeVarInt(value);
            },
            .bytes => {
                try w.encodeTag(fd);
                try w.encodeBytes(value);
            },
        }
    }

    fn encodeTag(w: *Writer, fd: FieldDesciptor) !void {
        const tag: Tag = .{
            .number = @truncate(fd.field_number.?),
            .type = fd.field_type.wireType(),
        };
        const value: u32 = @bitCast(tag);
        try w.encodeVarInt(value);
    }
};
