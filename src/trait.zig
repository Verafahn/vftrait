/// Represents a trait that can be satisfied by a type.
const VfTrait = @This();

const std = @import("std");

const TraitAttribute = enum {
    associated_type,
    associated_constant,
    associated_function,
    method,
    other,

    fn isMethod(comptime Trait: type, comptime decl: [:0]const u8) bool {
        const info = @typeInfo(@TypeOf(@field(Trait, decl))).@"fn";
        if (info.params.len == 0) return false;
        const Self = info.params[0].type orelse return false;
        if (Self == Trait) return true;
        switch (@typeInfo(Self)) {
            .pointer => |p| {
                if (p.size != .one) return false;
                if (p.child != Trait) return false;
                return true;
            },
            else => return false,
        }
    }

    pub fn satisfy(comptime self: TraitAttribute, comptime Trait: type, comptime decl: [:0]const u8) bool {
        const member = @field(Trait, decl);
        // @compileLog(member);
        switch (@typeInfo(if (@typeInfo(@TypeOf(member)) == .type) member else @TypeOf(member))) {
            .type => return self == .associated_type,
            .void => return self == .other,
            .bool => return self == .associated_constant,
            .noreturn => return self == .other,
            .int => return self == .associated_constant,
            .float => return self == .associated_constant,
            .pointer => return self == .associated_constant,
            .array => return self == .associated_constant,
            .@"struct" => return self == .associated_type,
            .comptime_float => return self == .associated_constant,
            .comptime_int => return self == .associated_constant,
            .undefined => return self == .other,
            .null => return self == .other,
            .optional => return self == .associated_constant,
            .error_union => return self == .associated_type,
            .error_set => return self == .associated_type,
            .@"enum" => return self == .associated_type,
            .@"union" => return self == .associated_type,
            .@"fn" => return self == (if (isMethod(Trait, decl)) .method else .associated_function),
            .@"opaque" => return self == .associated_type,
            .frame => return self == .other,
            .@"anyframe" => return self == .other,
            .vector => return self == .associated_constant,
            .enum_literal => return self == .other,
        }
    }
};

fn getTraitAttribute(comptime Trait: type, comptime attr: TraitAttribute) [getTraitAttrobuteCount(Trait, attr)][:0]const u8 {
    const trait_decls = @typeInfo(Trait).@"struct".decls;
    comptime var types: [getTraitAttrobuteCount(Trait, attr)][:0]const u8 = undefined;
    comptime var i: usize = 0;
    inline for (trait_decls) |decl| {
        if (comptime attr.satisfy(Trait, decl.name)) {
            types[i] = decl.name;
            i += 1;
        }
    }
    return types;
}

fn getTraitAttrobuteCount(comptime Trait: type, comptime attr: TraitAttribute) usize {
    const trait_decls = @typeInfo(Trait).@"struct".decls;
    comptime var count: usize = 0;
    inline for (trait_decls) |decl| {
        if (attr.satisfy(Trait, decl.name))
            count += 1;
    }
    return count;
}

fn matchTraitAssociatedConstant(comptime Trait: type, comptime T: type) bool {
    const trait_constant = comptime getTraitAttribute(Trait, .associated_constant);
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

fn matchTraitAssociatedType(comptime Trait: type, comptime T: type) bool {
    const trait_type = comptime getTraitAttribute(Trait, .associated_type);
    inline for (trait_type) |name| {
        if (!@hasDecl(T, name))
            return false;

        const trait_member = @typeInfo(@field(Trait, name));
        const target_member = @typeInfo(@field(T, name));
        if (std.meta.activeTag(trait_member) != std.meta.activeTag(target_member))
            return false;
    }
    return true;
}

fn findTraitAssociatedType(comptime Trait: type, comptime T: type) ?[:0]const u8 {
    const trait_type = comptime getTraitAttribute(Trait, .associated_type);
    inline for (trait_type) |name| {
        if (T == @field(Trait, name)) {
            return name;
        }
    }
    return null;
}

fn isomorphic(comptime Trait: type, comptime T: type, comptime Traits: type, comptime Ts: type) bool {
    if (comptime findTraitAssociatedType(Trait, Traits)) |name| {
        if (Ts != @field(T, name)) return false;
    }
    const trait_info = @typeInfo(Traits);
    const target_info = @typeInfo(Ts);
    switch (trait_info) {
        .type,
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
        => {
            return std.meta.eql(trait_info, target_info);
        },
        .pointer => |p| {
            var copy_p = p;
            copy_p.child = void;
            const target_p = if (target_info == .pointer) target_info.pointer else return false;
            var copy_target_p = target_p;
            copy_target_p.child = void;
            return std.meta.eql(copy_p, copy_target_p) and isomorphic(
                Trait,
                T,
                p.child,
                target_p.child,
            );
        },
        .array => |a| {
            var copy_a = a;
            copy_a.child = void;
            const target_a = if (target_info == .array) target_info.array else return false;
            var copy_target_a = target_a;
            copy_target_a.child = void;
            return std.meta.eql(copy_a, copy_target_a) and isomorphic(
                Trait,
                T,
                a.child,
                target_a.child,
            );
        },
        .@"struct",
        .error_set,
        .@"enum",
        .@"union",
        .@"opaque",
        => {
            return std.meta.activeTag(trait_info) == std.meta.activeTag(target_info);
        },
        .optional => |o| {
            const to = if (target_info == .optional) target_info.optional else return false;
            return isomorphic(Trait, T, o.child, to.child);
        },
        .error_union => |eu| {
            const teu = if (target_info == .error_union) target_info.error_union else return false;
            return isomorphic(Trait, T, eu.error_set, teu.error_set) and isomorphic(Trait, T, eu.payload, teu.payload);
        },
        .@"fn" => |f| {
            var copy_f = f;
            copy_f.return_type = null;
            copy_f.params = &.{};

            const target_f = if (target_info == .@"fn") target_info.@"fn" else return false;
            var copy_target_f = target_f;
            copy_target_f.return_type = null;
            copy_target_f.params = &.{};

            if (!std.meta.eql(copy_f, copy_target_f)) return false;
            if (f.params.len != target_f.params.len) return false;
            inline for (f.params, target_f.params) |param, target_param| {
                var copy_param = param;
                copy_param.type = null;

                var copy_target_param = target_param;
                copy_target_param.type = null;

                if (!std.meta.eql(copy_param, copy_target_param)) return false;
                if ((param.type == null) ^ (target_param.type == null)) return false;
                if (param.type != null and !isomorphic(Trait, T, param.type.?, target_param.type.?)) return false;
            }
            if ((f.return_type == null) ^ (target_f.return_type == null)) return false;
            if (f.return_type != null and !isomorphic(Trait, T, f.return_type.?, target_f.return_type.?)) return false;
            return true;
        },
        .@"anyframe" => |af| {
            const taf = if (target_info == .@"anyframe") target_info.@"anyframe" else return false;
            return isomorphic(Trait, T, af.child, taf.child);
        },
        .vector => |v| {
            var copy_v = v;
            copy_v.child = void;
            const target_v = if (target_info == .vector) target_info.vector else return false;
            var copy_target_v = target_v;
            copy_target_v.child = void;
            return std.meta.eql(copy_v, copy_target_v) and isomorphic(Trait, T, v.child, target_v.child);
        },
    }
}

fn matchTraitAssociatedFunction(comptime Trait: type, comptime T: type) bool {
    const trait_function = comptime getTraitAttribute(Trait, .associated_function);
    inline for (trait_function) |func_name| {
        if (!@hasDecl(T, func_name))
            return false;

        const trait_info = @typeInfo(@TypeOf(@field(Trait, func_name))).@"fn";
        const target_info = @typeInfo(@TypeOf(@field(T, func_name))).@"fn";

        if (trait_info.return_type) |R| {
            const R_target = target_info.return_type orelse return false;
            if (!isomorphic(Trait, T, R, R_target))
                return false;
        }
        if (trait_info.params.len != target_info.params.len)
            return false;
        inline for (trait_info.params, target_info.params) |param, param_target| {
            if ((param.type == null) ^ (param_target.type == null))
                return false;
            if (param.type != null and !isomorphic(Trait, T, param.type.?, param_target.type.?))
                return false;
        }
    }
    return true;
}

fn matchTraitMethod(comptime Trait: type, comptime T: type) bool {
    const trait_function = comptime getTraitAttribute(Trait, .method);
    inline for (trait_function) |func_name| {
        if (!@hasDecl(T, func_name))
            return false;

        const trait_info = @typeInfo(@TypeOf(@field(Trait, func_name))).@"fn";
        const target_info = @typeInfo(@TypeOf(@field(T, func_name))).@"fn";

        const Self = target_info.params[0].type orelse return false;
        const TraitSelf = trait_info.params[0].type orelse return false;
        const self_info = @typeInfo(Self);
        switch (self_info) {
            .pointer => |info| {
                comptime var copy_info = info;
                const trait_self_info = if (@typeInfo(TraitSelf) == .pointer) @typeInfo(TraitSelf).pointer else return false;
                copy_info.child = trait_self_info.child;
                if (!std.meta.eql(copy_info, trait_self_info))
                    return false;
            },
            else => {
                if (Self != T)
                    return false;
            },
        }

        if (trait_info.return_type) |R| {
            const R_target = target_info.return_type orelse return false;
            if (!isomorphic(Trait, T, R, R_target))
                return false;
        }
        if (trait_info.params.len != target_info.params.len)
            return false;
        inline for (trait_info.params[1..], target_info.params[1..]) |param, param_target| {
            if ((param.type == null) ^ (param_target.type == null))
                return false;
            if (param.type != null and !isomorphic(Trait, T, param.type.?, param_target.type.?))
                return false;
        }
    }
    return true;
}

/// Returns true if `Trait` is satisfied by `T`.
pub fn satisfyTrait(comptime Trait: type, comptime T: type) R: {
    if (@typeInfo(Trait) != .@"struct")
        @compileError("Trait must be a struct");
    if (@typeInfo(Trait).@"struct".is_tuple)
        @compileError("Trait must be not a tuple");
    break :R bool;
} {
    return matchTraitAssociatedConstant(Trait, T) and
        matchTraitAssociatedType(Trait, T) and
        matchTraitMethod(Trait, T) and
        matchTraitAssociatedFunction(Trait, T);
}

//-------------------------------------TEST-------------------------------------

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

test "satisfyTrait: tarit with type" {
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

test "satisfyTrait: trait with type&function" {
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

test "satisfyTrait: trait with type&method" {
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

test "satisfyTrait: All in" {
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
