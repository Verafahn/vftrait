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

comptime {
    const Trait = struct {
        pub const Error = error{};
        pub const T = type;
        pub fn foo() Error!T {
            unreachable;
        }
    };
    const A = struct {
        pub const Error = error{A};
        pub const T = i32;
        pub fn foo() Error!u64 {
            unreachable;
        }
    };
    requires(Trait, A);
}
