//! Defines different stuff about the Protobuf spec

const std = @import("std");

pub const Version = enum {
    proto2,
    proto3,

    pub const SUPPORTED: std.EnumArray(Version, bool) = .init(.{
        .proto2 = false,
        .proto3 = true,
    });

    pub const DEFAULT: Version = .proto3;
};

pub const Type = enum {
    uint32,
    bytes,

    /// See: https://protobuf.dev/programming-guides/encoding/#structure
    pub fn wireType(t: Type) WireType {
        return switch (t) {
            .uint32 => .varint,
            .bytes => .len,
        };
    }
};

pub const WireType = enum(u3) {
    varint,
    i64,
    len,
    sgroup,
    egroup,
    i32,
};
