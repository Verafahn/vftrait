const trait = @import("trait.zig");
const std = @import("std");
const builtin = @import("builtin");

/// Returns true if `Trait` is satisfied by `T`.
///
/// A trait is a struct whose declarations specify the contract:
/// - associated constants (bool, int, float, pointer, array, optional, vector, etc.)
/// - associated types (struct, enum, union, opaque, error_set, error_union)
/// - associated functions (standalone functions)
/// - methods (functions taking self as the first parameter)
///
/// `T` satisfies the trait if it has matching declarations for all of the above.
///
/// # Requirements
///
/// - `Trait` must be a struct
/// - `Trait` must not be a tuple
pub const satisfyTrait: fn (comptime Trait: type, comptime T: type) bool = trait.satisfyTrait;

/// Returns true if `Trait` is not satisfied by `T`.
///
/// This is the negation of [`satisfyTrait`].
///
/// # Requirements
///
/// - `Trait` must be a struct
/// - `Trait` must not be a tuple
pub fn notSatisfyTrait(comptime Trait: type, comptime T: type) bool {
    return !satisfyTrait(Trait, T);
}

/// Asserts that `T` satisfies `Trait`.
///
/// This is useful for compile-time checks that a type satisfies a trait.
///
/// # Requirements
///
/// - `Trait` must be a struct
/// - `Trait` must not be a tuple
pub fn assertSatisfyTrait(comptime Trait: type, comptime T: type) void {
    if (comptime notSatisfyTrait(Trait, T)) {
        @compileError("Type '" ++ @typeName(T) ++ "' does not satisfy Trait '" ++ @typeName(Trait) ++ "'.");
    }
}

/// Requires that `T` satisfies `Trait` and returns `T`.
///
/// This is useful for compile-time checks that a type satisfies a trait.
///
/// # Requirements
///
/// - `Trait` must be a struct
/// - `Trait` must not be a tuple
pub fn requireSatisfyTrait(comptime Trait: type, comptime T: type) type {
    assertSatisfyTrait(Trait, T);
    return T;
}

/// Requires that all traits in `Traits` are satisfied by `T` and returns `T`.
///
/// This is useful for compile-time checks that a type satisfies a trait.
///
/// # Requirements
///
/// - `Traits` must be a slice of struct types
/// - `Trait` must not be a tuple
pub fn satisfyAllTraits(comptime Traits: []type, comptime T: type) bool {
    for (Traits) |Trait| {
        assertSatisfyTrait(Trait, T);
    }
    return true;
}

/// Returns true if none of the traits in `Traits` are satisfied by `T`.
///
/// This is the negation of [`satisfyAllTraits`].
///
/// # Requirements
///
/// - `Traits` must be a slice of struct types
/// - `Trait` must not be a tuple
pub fn notSatisfyTraits(comptime Traits: []type, comptime T: type) bool {
    return !satisfyAllTraits(Traits, T);
}

pub fn reportError(comptime fmt: []const u8, args: anytype) bool {
    if (builtin.is_test) {
        return false;
    }
    const msg = comptime std.fmt.comptimePrint(fmt, args);
    @compileError(msg);
}

test "trait" {
    std.testing.refAllDecls(trait);
}
