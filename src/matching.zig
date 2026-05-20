const std = @import("std");
const TraitAttribute = @import("attribute.zig").TraitAttribute;
const query = @import("query.zig");
const isomorphic = @import("isomorphic.zig");

pub fn matchAssociatedConstants(comptime Trait: type, comptime T: type) bool {
    const trait_constant = comptime query.getTraitAttribute(Trait, .associated_constant);
    inline for (trait_constant) |name| {
        if (!@hasDecl(T, name))
            return false;

        const trait_member = @field(Trait, name);
        const target_member = @field(T, name);
        if (@TypeOf(trait_member) != @TypeOf(target_member))
            return false;
    }
    return true;
}

pub fn matchAssociatedTypes(comptime Trait: type, comptime T: type) bool {
    const trait_type = comptime query.getTraitAttribute(Trait, .associated_type);
    inline for (trait_type) |name| {
        if (!@hasDecl(T, name))
            return false;

        // If the trait declares `type` itself (e.g. `pub const Type = type;`),
        // any type satisfies it — no need to compare type kinds.
        if (@field(Trait, name) == type)
            continue;

        const trait_member = @typeInfo(@field(Trait, name));
        const target_member = @typeInfo(@field(T, name));
        if (std.meta.activeTag(trait_member) != std.meta.activeTag(target_member))
            return false;
    }
    return true;
}

pub fn matchAssociatedFunctions(comptime Trait: type, comptime T: type) bool {
    const trait_function = comptime query.getTraitAttribute(Trait, .associated_function);
    inline for (trait_function) |func_name| {
        if (!@hasDecl(T, func_name))
            return false;

        const trait_info = @typeInfo(@TypeOf(@field(Trait, func_name))).@"fn";
        const target_info = @typeInfo(@TypeOf(@field(T, func_name))).@"fn";

        if (trait_info.return_type) |R| {
            const R_target = target_info.return_type orelse return false;
            if (!isomorphic.isomorphic(Trait, T, R, R_target))
                return false;
        }
        if (trait_info.params.len != target_info.params.len)
            return false;
        inline for (trait_info.params, target_info.params) |param, param_target| {
            if ((param.type == null) ^ (param_target.type == null))
                return false;
            if (param.type != null and
                !isomorphic.isomorphic(Trait, T, param.type.?, param_target.type.?))
                return false;
        }
    }
    return true;
}

pub fn matchMethods(comptime Trait: type, comptime T: type) bool {
    const trait_function = comptime query.getTraitAttribute(Trait, .method);
    inline for (trait_function) |func_name| {
        if (!@hasDecl(T, func_name))
            return false;

        const trait_info = @typeInfo(@TypeOf(@field(Trait, func_name))).@"fn";
        const target_info = @typeInfo(@TypeOf(@field(T, func_name))).@"fn";

        // Validate self parameter
        const Self = target_info.params[0].type orelse return false;
        const TraitSelf = trait_info.params[0].type orelse return false;
        const self_info = @typeInfo(Self);
        switch (self_info) {
            .pointer => |info| {
                comptime var copy_info = info;
                const trait_self_info = if (@typeInfo(TraitSelf) == .pointer)
                    @typeInfo(TraitSelf).pointer
                else
                    return false;
                copy_info.child = trait_self_info.child;
                if (!std.meta.eql(copy_info, trait_self_info))
                    return false;
            },
            else => {
                if (Self != T)
                    return false;
            },
        }

        // Validate return type
        if (trait_info.return_type) |R| {
            const R_target = target_info.return_type orelse return false;
            if (!isomorphic.isomorphic(Trait, T, R, R_target))
                return false;
        }

        // Validate remaining parameters (skip self)
        if (trait_info.params.len != target_info.params.len)
            return false;
        inline for (trait_info.params[1..], target_info.params[1..]) |param, param_target| {
            if ((param.type == null) ^ (param_target.type == null))
                return false;
            if (param.type != null and
                !isomorphic.isomorphic(Trait, T, param.type.?, param_target.type.?))
                return false;
        }
    }
    return true;
}
