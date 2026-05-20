const std = @import("std");
const query = @import("query.zig");

/// Returns true if two types are "isomorphic" with respect to a trait,
/// meaning they have the same structure, with associated types resolved through `Trait`/`T`.
pub fn isomorphic(comptime Trait: type, comptime T: type, comptime Traits: type, comptime Ts: type) bool {
    // Resolve associated types: if Traits is an associated type of Trait,
    // substitute it with the concrete type from T.
    if (comptime query.findTraitAssociatedType(Trait, Traits)) |name| {
        if (Ts != @field(T, name)) return false;
    }

    const trait_info = @typeInfo(Traits);
    const target_info = @typeInfo(Ts);

    switch (trait_info) {
        .type => return true,

        // Simple types: compare the type info directly
        .void,
        .bool,
        .noreturn,
        .int,
        .float,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .enum_literal,
        .frame,
        => return std.meta.eql(trait_info, target_info),

        // Structural types: compare recursively
        .pointer => return isomorphicPointer(Trait, T, trait_info.pointer, target_info),
        .array => return isomorphicArray(Trait, T, trait_info.array, target_info),
        .optional => return isomorphicOptional(Trait, T, trait_info.optional, target_info),
        .error_union => return isomorphicErrorUnion(Trait, T, trait_info.error_union, target_info),
        .@"fn" => return isomorphicFn(Trait, T, trait_info.@"fn", target_info),
        .@"anyframe" => return isomorphicAnyframe(Trait, T, trait_info.@"anyframe", target_info),
        .vector => return isomorphicVector(Trait, T, trait_info.vector, target_info),

        // Tag-only comparison: same type kind is sufficient
        .@"struct",
        .error_set,
        .@"enum",
        .@"union",
        .@"opaque",
        => return std.meta.activeTag(trait_info) == std.meta.activeTag(target_info),
    }
}

fn isomorphicPointer(
    comptime Trait: type,
    comptime T: type,
    p: std.builtin.Type.Pointer,
    target_info: std.builtin.Type,
) bool {
    if (target_info != .pointer) return false;
    const target_p = target_info.pointer;

    var copy_p = p;
    copy_p.child = void;
    var copy_target_p = target_p;
    copy_target_p.child = void;

    return std.meta.eql(copy_p, copy_target_p) and
        isomorphic(Trait, T, p.child, target_p.child);
}

fn isomorphicArray(
    comptime Trait: type,
    comptime T: type,
    a: std.builtin.Type.Array,
    target_info: std.builtin.Type,
) bool {
    if (target_info != .array) return false;
    const target_a = target_info.array;

    var copy_a = a;
    copy_a.child = void;
    var copy_target_a = target_a;
    copy_target_a.child = void;

    return std.meta.eql(copy_a, copy_target_a) and
        isomorphic(Trait, T, a.child, target_a.child);
}

fn isomorphicOptional(
    comptime Trait: type,
    comptime T: type,
    o: std.builtin.Type.Optional,
    target_info: std.builtin.Type,
) bool {
    if (target_info != .optional) return false;
    const to = target_info.optional;
    return isomorphic(Trait, T, o.child, to.child);
}

fn isomorphicErrorUnion(
    comptime Trait: type,
    comptime T: type,
    eu: std.builtin.Type.ErrorUnion,
    target_info: std.builtin.Type,
) bool {
    if (target_info != .error_union) return false;
    const teu = target_info.error_union;
    return isomorphic(Trait, T, eu.error_set, teu.error_set) and
        isomorphic(Trait, T, eu.payload, teu.payload);
}

fn isomorphicFn(
    comptime Trait: type,
    comptime T: type,
    f: std.builtin.Type.Fn,
    target_info: std.builtin.Type,
) bool {
    if (target_info != .@"fn") return false;
    const target_f = target_info.@"fn";

    // Compare calling conventions (without params/return type)
    {
        var copy_f = f;
        copy_f.return_type = null;
        copy_f.params = &.{};

        var copy_target_f = target_f;
        copy_target_f.return_type = null;
        copy_target_f.params = &.{};

        if (!std.meta.eql(copy_f, copy_target_f)) return false;
    }

    // Compare parameter counts
    if (f.params.len != target_f.params.len) return false;

    // Compare each parameter
    inline for (f.params, target_f.params) |param, target_param| {
        var copy_param = param;
        copy_param.type = null;

        var copy_target_param = target_param;
        copy_target_param.type = null;

        if (!std.meta.eql(copy_param, copy_target_param)) return false;
        if ((param.type == null) ^ (target_param.type == null)) return false;
        if (param.type != null and
            !isomorphic(Trait, T, param.type.?, target_param.type.?)) return false;
    }

    // Compare return type
    if ((f.return_type == null) ^ (target_f.return_type == null)) return false;
    if (f.return_type != null and
        !isomorphic(Trait, T, f.return_type.?, target_f.return_type.?)) return false;

    return true;
}

fn isomorphicAnyframe(
    comptime Trait: type,
    comptime T: type,
    af: std.builtin.Type.Anyframe,
    target_info: std.builtin.Type,
) bool {
    if (target_info != .@"anyframe") return false;
    const taf = target_info.@"anyframe";
    return isomorphic(Trait, T, af.child, taf.child);
}

fn isomorphicVector(
    comptime Trait: type,
    comptime T: type,
    v: std.builtin.Type.Vector,
    target_info: std.builtin.Type,
) bool {
    if (target_info != .vector) return false;
    const target_v = target_info.vector;

    var copy_v = v;
    copy_v.child = void;
    var copy_target_v = target_v;
    copy_target_v.child = void;

    return std.meta.eql(copy_v, copy_target_v) and
        isomorphic(Trait, T, v.child, target_v.child);
}
