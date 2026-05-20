const trait = @import("trait.zig");
const std = @import("std");

pub const satisfyTrait: fn (comptime Trait: type, comptime T: type) bool = trait.satisfyTrait;

pub fn notSatisfyTrait(comptime Trait: type, comptime T: type) bool {
    return !satisfyTrait(Trait, T);
}

pub fn assertSatisfyTrait(comptime Trait: type, comptime T: type) void {
    if (comptime notSatisfyTrait(Trait, T)) {
        @compileError("Type '" ++ @typeName(T) ++ "' does not satisfy Trait '" ++ @typeName(Trait) ++ "'.");
    }
}

pub fn requireSatisfyTrait(comptime Trait: type, comptime T: type) type {
    assertSatisfyTrait(Trait, T);
    return T;
}

pub fn satisfyAllTraits(comptime Traits: []type, comptime T: type) bool {
    for (Traits) |Trait| {
        assertSatisfyTrait(Trait, T);
    }
    return true;
}

pub fn notSatisfyTraits(comptime Traits: []type, comptime T: type) bool {
    return !satisfyAllTraits(Traits, T);
}
