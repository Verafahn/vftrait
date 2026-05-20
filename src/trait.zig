const std = @import("std");
const matching = @import("matching.zig");

pub const TraitAttribute = @import("attribute.zig").TraitAttribute;

/// Returns true if `Trait` is satisfied by `T`.
///
/// A trait is a struct whose declarations specify the contract:
/// - associated constants (bool, int, float, pointer, array, optional, vector, etc.)
/// - associated types (struct, enum, union, opaque, error_set, error_union)
/// - associated functions (standalone functions)
/// - methods (functions taking self as the first parameter)
///
/// `T` satisfies the trait if it has matching declarations for all of the above.
pub fn satisfyTrait(comptime Trait: type, comptime T: type) R: {
    if (@typeInfo(Trait) != .@"struct")
        @compileError("Trait must be a struct");
    if (@typeInfo(Trait).@"struct".is_tuple)
        @compileError("Trait must be not a tuple");
    break :R bool;
} {
    return matching.matchAssociatedConstants(Trait, T) and
        matching.matchAssociatedTypes(Trait, T) and
        matching.matchMethods(Trait, T) and
        matching.matchAssociatedFunctions(Trait, T);
}

// ===================================== TESTS =====================================

test "satisfyTrait: empty trait" {
    const Trait = struct {};
    const T = struct {};

    try std.testing.expect(satisfyTrait(Trait, T));
}

test "satisfyTrait: trait with constant" {
    const Trait = struct {
        pub const value: i32 = undefined;
    };
    const A = struct {};

    try std.testing.expect(!satisfyTrait(Trait, A));

    const B = struct {
        pub const value: i32 = 42;
    };

    try std.testing.expect(satisfyTrait(Trait, B));
}

test "satisfyTrait: trait with type" {
    const Trait = struct {
        pub const Type = struct {};
        pub const Error = error{};
    };
    const T = struct {};

    try std.testing.expect(!satisfyTrait(Trait, T));

    const A = struct {
        pub const Type = struct {
            a: i32,
            b: u32,
        };
        pub const Error = error{
            one_error,
            two_error,
        };
    };

    try std.testing.expect(satisfyTrait(Trait, A));

    const B = struct {
        pub const Type = struct {};
        pub const Error = struct {};
    };

    try std.testing.expect(!satisfyTrait(Trait, B));
}

test "satisfyTrait: trait with function" {
    const Trait = struct {
        pub fn foo(arg: i32) void {
            _ = arg;
        }
    };
    const T = struct {};

    try std.testing.expect(!satisfyTrait(Trait, T));

    const A = struct {
        pub fn foo(arg: i32) void {
            _ = arg;
        }
    };

    try std.testing.expect(satisfyTrait(Trait, A));
}

test "satisfyTrait: trait with method" {
    const Trait = struct {
        pub fn foo(self: *@This()) void {
            _ = self;
        }
    };
    const T = struct {};

    try std.testing.expect(!satisfyTrait(Trait, T));

    const A = struct {
        pub fn foo(self: *@This()) void {
            _ = self;
        }
    };

    try std.testing.expect(satisfyTrait(Trait, A));

    const B = struct {
        pub fn foo(self: *const @This()) void {
            _ = self;
        }
    };

    try std.testing.expect(!satisfyTrait(Trait, B));
}

test "satisfyTrait: trait with type & function" {
    const Trait = struct {
        pub const Type = struct {};
        pub fn foo(arg: Type) void {
            _ = arg;
        }
    };
    const T = struct {};

    try std.testing.expect(!satisfyTrait(Trait, T));

    const A = struct {
        pub const Type = struct {
            a: i32,
            b: u32,
        };
        pub fn foo(arg: Type) void {
            _ = arg;
        }
    };

    try std.testing.expect(satisfyTrait(Trait, A));
}

test "satisfyTrait: trait with type & method" {
    const Trait = struct {
        pub const Type = struct {};
        pub fn foo(self: *@This()) Type {
            _ = self;
        }
    };
    const T = struct {};

    try std.testing.expect(!satisfyTrait(Trait, T));

    const A = struct {
        pub const Type = struct {};
        pub fn foo(self: *@This()) Type {
            _ = self;
        }
    };

    try std.testing.expect(satisfyTrait(Trait, A));
}

test "satisfyTrait: anytype" {
    const Trait = struct {
        pub const Type = type;
    };

    // The empty struct misses `Type`, should fail.
    const Missing = struct {};
    try std.testing.expect(!satisfyTrait(Trait, Missing));

    // All these should pass — any type kind satisfies `type`.
    const WithU32 = struct {
        pub const Type = u32;
    };
    try std.testing.expect(satisfyTrait(Trait, WithU32));

    const WithStruct = struct {
        pub const Type = struct {};
    };
    try std.testing.expect(satisfyTrait(Trait, WithStruct));

    const WithError = struct {
        pub const Type = error{};
    };
    try std.testing.expect(satisfyTrait(Trait, WithError));

    const WithUnion = struct {
        pub const Type = union {};
    };
    try std.testing.expect(satisfyTrait(Trait, WithUnion));

    const WithEnum = struct {
        pub const Type = enum { a, b };
    };
    try std.testing.expect(satisfyTrait(Trait, WithEnum));

    const WithPointer = struct {
        pub const Type = *u32;
    };
    try std.testing.expect(satisfyTrait(Trait, WithPointer));

    const WithOptional = struct {
        pub const Type = ?u32;
    };
    try std.testing.expect(satisfyTrait(Trait, WithOptional));
}

test "satisfyTrait: anytype in function signature" {
    const Trait = struct {
        pub const Type = type;
        pub fn foo(arg: Type) Type {
            _ = arg;
        }
    };

    const T = struct {
        pub const Type = u32;
        pub fn foo(arg: u32) u32 {
            return arg;
        }
    };
    try std.testing.expect(satisfyTrait(Trait, T));

    // struct type as parameter (void return)
    const T2 = struct {
        pub const Type = struct { x: i32 };
        pub fn foo(arg: Type) Type {
            _ = arg;
        }
    };
    try std.testing.expect(satisfyTrait(Trait, T2));

    // struct type as return type
    const T3 = struct {
        pub const Type = struct { x: i32 };
        pub fn foo() struct { x: i32 } {
            return .{ .x = 0 };
        }
    };
    try std.testing.expect(!satisfyTrait(Trait, T3));
}

test "satisfyTrait: all in" {
    const Trait = struct {
        pub const M: usize = undefined;
        pub const N: f32 = undefined;
        pub const Type = struct {};
        pub const Error = error{};
        pub fn function(param: Type) Error!void {
            _ = param;
            @compileError("Not Impl");
        }
        pub fn method(self: *@This(), param: ?Type) Error!Type {
            _ = self;
            _ = param;
            @compileError("Not Impl");
        }
    };

    const T = struct {};
    try std.testing.expect(!satisfyTrait(Trait, T));

    const A = struct {
        pub const M: usize = 12;
        pub const N: f32 = 13.5;
        pub const Type = struct {
            a: i32,
        };
        pub const Error = error{
            best,
        };
        pub fn function(param: Type) Error!void {
            _ = param;
        }
        pub fn method(self: *@This(), param: ?Type) Error!Type {
            _ = self;
            _ = param;
        }
    };

    try std.testing.expect(satisfyTrait(Trait, A));
}
