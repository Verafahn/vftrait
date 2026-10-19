const trait = @import("trait.zig");
const std = @import("std");
pub const satisfy = trait.satisfy;

pub fn requires(comptime Trait: type, comptime Type: type) void {
    comptime {
        var report: []const u8 = undefined;
        if (!satisfy(Trait, Type, &report)) {
            @compileError(report);
        }
    }
}

test trait {
    std.testing.refAllDecls(trait);
}
