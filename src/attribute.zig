const std = @import("std");

pub const TraitAttribute = enum {
    associated_type,
    associated_constant,
    associated_function,
    method,
    other,

    /// Returns true if the given declaration in `Trait` is a method (takes self as first param).
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

    /// Returns true if the given declaration in `Trait` matches this attribute kind.
    pub fn satisfy(comptime self: TraitAttribute, comptime Trait: type, comptime decl: [:0]const u8) bool {
        const member = @field(Trait, decl);
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
