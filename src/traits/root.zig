const std = @import("std");

/// A trait that provides a `format` method for formatting values into a writer.
///
/// It is an implicit trait used to the `{f}` placeholder in format functions.
pub const Formatable = struct {
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        _ = self;
        _ = writer;

        @compileError("Not a availd implement.");
    }
};

test "Formatable" {
    const vftrait = @import("vftrait");

    const T = struct {
        a: i32,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            try writer.print("T: {d}", .{self.a});
        }
    };

    try std.testing.expect(comptime vftrait.satisfyTrait(Formatable, T));

    const msg = try std.fmt.allocPrint(std.testing.allocator, "{f}", .{T{ .a = 42 }});
    defer std.testing.allocator.free(msg);

    try std.testing.expectEqualStrings("T: 42", msg);
}
