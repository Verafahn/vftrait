const std = @import("std");

const format = @import("format.zig");
pub const FormatTrait = format.FormatTrait;
pub const Format = format.Format;

const allocator = @import("allocator.zig");
pub const AllocatorTrait = allocator.AllocatorTrait;
pub const Allocator = allocator.Allocator;

test "format" {
    std.testing.refAllDecls(format);
}

test "allocator" {
    std.testing.refAllDecls(allocator);
}
