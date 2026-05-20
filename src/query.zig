const TraitAttribute = @import("attribute.zig").TraitAttribute;

/// Returns the number of declarations in `Trait` that match the given attribute.
fn getTraitAttributeCount(comptime Trait: type, comptime attr: TraitAttribute) usize {
    const trait_decls = @typeInfo(Trait).@"struct".decls;
    comptime var count: usize = 0;
    inline for (trait_decls) |decl| {
        if (attr.satisfy(Trait, decl.name))
            count += 1;
    }
    return count;
}

/// Returns an array of declaration names in `Trait` that match the given attribute.
pub fn getTraitAttribute(comptime Trait: type, comptime attr: TraitAttribute) [getTraitAttributeCount(Trait, attr)][:0]const u8 {
    const trait_decls = @typeInfo(Trait).@"struct".decls;
    comptime var types: [getTraitAttributeCount(Trait, attr)][:0]const u8 = undefined;
    comptime var i: usize = 0;
    inline for (trait_decls) |decl| {
        if (comptime attr.satisfy(Trait, decl.name)) {
            types[i] = decl.name;
            i += 1;
        }
    }
    return types;
}

/// If `Traits` matches one of the associated types declared in `Trait`,
/// returns the name of that associated type. Otherwise returns null.
pub fn findTraitAssociatedType(comptime Trait: type, comptime Traits: type) ?[:0]const u8 {
    const trait_type = comptime getTraitAttribute(Trait, .associated_type);
    inline for (trait_type) |name| {
        if (Traits == @field(Trait, name)) {
            return name;
        }
    }
    return null;
}
