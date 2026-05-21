const std = @import("std");
const TraitAttribute = @import("attribute.zig").TraitAttribute;
const query = @import("query.zig");
const isomorphic = @import("isomorphic.zig");
const reportError = @import("root.zig").reportError;

pub fn matchAssociatedConstants(comptime Trait: type, comptime T: type) bool {
    const trait_constant = comptime query.getTraitAttribute(Trait, .associated_constant);
    inline for (trait_constant) |name| {
        if (!@hasDecl(T, name))
            return reportError(
                \\Type '{any}' not satisfied by trait '{any}':
                \\  - '{any}' is missing the necessary associated constant '{s}' by trait '{any}'.
            ,
                .{ T, Trait, T, name, Trait },
            );

        const trait_member = @field(Trait, name);
        const target_member = @field(T, name);
        if (@TypeOf(trait_member) != @TypeOf(target_member))
            return reportError(
                \\Type '{any}' not satisfied by trait '{any}':
                \\  - The types of '{s}' in '{any}' and '{s}' in '{any}' are inconsistent.
                \\  - Expected '{any}', but found '{any}'.
            ,
                .{ T, Trait, name, T, name, Trait, @TypeOf(trait_member), @TypeOf(target_member) },
            );
    }
    return true;
}

pub fn matchAssociatedTypes(comptime Trait: type, comptime T: type) bool {
    const trait_type = comptime query.getTraitAttribute(Trait, .associated_type);
    inline for (trait_type) |name| {
        if (!@hasDecl(T, name))
            return reportError(
                \\Type '{any}' not satisfied by trait '{any}':
                \\  - '{any}' is missing the necessary associated type '{s}' by trait '{any}'.
            ,
                .{ T, Trait, T, name, Trait },
            );

        // If the trait declares `type` itself (e.g. `pub const Type = type;`),
        // any type satisfies it — no need to compare type kinds.
        if (@field(Trait, name) == type)
            continue;

        const trait_member = @typeInfo(@field(Trait, name));
        const target_member = @typeInfo(@field(T, name));
        if (std.meta.activeTag(trait_member) != std.meta.activeTag(target_member))
            return reportError(
                \\Type '{any}' not satisfied by trait '{any}':
                \\  - The categories of '{s}' in '{any}' and '{s}' in '{any}' are inconsistent.
                \\  - Expected '{any}', but found '{any}'.
            ,
                .{ T, Trait, name, T, name, Trait, @tagName(trait_member), @tagName(target_member) },
            );
    }
    return true;
}

pub fn matchAssociatedFunctions(comptime Trait: type, comptime T: type) bool {
    const trait_function = comptime query.getTraitAttribute(Trait, .associated_function);
    inline for (trait_function) |func_name| {
        if (!@hasDecl(T, func_name))
            return reportError(
                \\Type '{any}' not satisfied by trait '{any}':
                \\  - '{any}' is missing the necessary associated function '{s}' by trait '{any}'.
            ,
                .{ T, Trait, T, func_name, Trait },
            );

        const trait_info = @typeInfo(@TypeOf(@field(Trait, func_name))).@"fn";
        const target_info = @typeInfo(@TypeOf(@field(T, func_name))).@"fn";

        const result = blk: {
            if (trait_info.return_type) |R| {
                const R_target = target_info.return_type orelse break :blk false;
                if (!isomorphic.isomorphic(Trait, T, R, R_target))
                    break :blk false;
            }
            if (trait_info.params.len != target_info.params.len)
                break :blk false;
            inline for (trait_info.params, target_info.params) |param, param_target| {
                if ((param.type == null) ^ (param_target.type == null))
                    break :blk false;
                if (param.type != null and
                    !isomorphic.isomorphic(Trait, T, param.type.?, param_target.type.?))
                    break :blk false;
            }
            break :blk true;
        };
        if (!result) return reportError(
            \\Type '{any}' not satisfied by trait '{any}':
            \\  - Function '{s}' in type '{any}' does not match function '{s}' in trait '{any}'.
            \\  - Their forms are inconsistent (different constructions).
        , .{ T, Trait, func_name, T, Trait, func_name, Trait });
    }
    return true;
}

pub fn matchMethods(comptime Trait: type, comptime T: type) bool {
    const trait_function = comptime query.getTraitAttribute(Trait, .method);
    inline for (trait_function) |func_name| {
        if (!@hasDecl(T, func_name))
            return reportError(
                \\Type '{any}' not satisfied by trait '{any}':
                \\  - '{any}' is missing the necessary method '{s}' by trait '{any}'.
            ,
                .{ T, Trait, T, func_name, Trait },
            );

        const trait_info = @typeInfo(@TypeOf(@field(Trait, func_name))).@"fn";
        const target_info = @typeInfo(@TypeOf(@field(T, func_name))).@"fn";

        // Validate self parameter
        const result = blk: {
            const Self = target_info.params[0].type orelse break :blk false;
            const TraitSelf = trait_info.params[0].type orelse break :blk false;
            const self_info = @typeInfo(Self);
            switch (self_info) {
                .pointer => |info| {
                    comptime var copy_info = info;
                    const trait_self_info = if (@typeInfo(TraitSelf) == .pointer)
                        @typeInfo(TraitSelf).pointer
                    else
                        break :blk false;
                    copy_info.child = trait_self_info.child;
                    if (!std.meta.eql(copy_info, trait_self_info))
                        break :blk false;
                },
                else => {
                    if (Self != T)
                        break :blk false;
                },
            }

            // Validate return type
            if (trait_info.return_type) |R| {
                const R_target = target_info.return_type orelse break :blk false;
                if (!isomorphic.isomorphic(Trait, T, R, R_target))
                    break :blk false;
            }

            // Validate remaining parameters (skip self)
            if (trait_info.params.len != target_info.params.len)
                break :blk false;
            inline for (trait_info.params[1..], target_info.params[1..]) |param, param_target| {
                if ((param.type == null) ^ (param_target.type == null))
                    break :blk false;
                if (param.type != null and
                    !isomorphic.isomorphic(Trait, T, param.type.?, param_target.type.?))
                    break :blk false;
            }
            break :blk true;
        };
        if (!result) return reportError(
            \\Type '{any}' not satisfied by trait '{any}':
            \\  - Method '{s}' in type '{any}' does not match method '{s}' in trait '{any}'.
            \\  - Their forms are inconsistent (different constructions).
        , .{ T, Trait, func_name, T, Trait, func_name, Trait });
    }
    return true;
}
