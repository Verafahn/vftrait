const std = @import("std");
const vftrait = @import("../root.zig");

/// A trait that provides a `format` method for formatting values into a writer.
///
/// It is an implicit trait used to the `{f}` placeholder in format functions.
pub const FormatTrait = struct {
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        _ = self;
        _ = writer;

        @compileError("Not a availd implement.");
    }
};

/// A convenience function for creating a `Format` type from a `Formatable` trait implementation.
///
/// Its purpose is to create a wrapper for the type for IDE recognition.
pub fn Format(comptime F: type) type {
    vftrait.assertSatisfyTrait(FormatTrait, F);
    return struct {
        const Self = @This();
        impl: F,

        pub fn from(impl: F) Self {
            return .{ .impl = impl };
        }

        pub fn format(self: *Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try self.impl.format(writer);
        }
    };
}

test "Formatable" {
    const T = struct {
        a: i32,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("T: {d}", .{self.a});
        }
    };

    try std.testing.expect(comptime vftrait.satisfyTrait(FormatTrait, T));

    const msg = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{T{ .a = 42 }});
    defer std.testing.allocator.free(msg);

    try std.testing.expectEqualStrings("T: 42", msg);
}
