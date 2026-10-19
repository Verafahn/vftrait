const std = @import("std");
const print = std.fmt.comptimePrint;

const TraitPair = struct {
    trait: type,
    ty: type,
};

const TypePair = struct {
    a: type,
    b: type,
};

const FunctionKind = enum {
    function,
    method,
};

const Report = struct {
    ok: bool = true,
    text: []const u8 = "",

    fn fail(comptime self: Report, comptime fmt: []const u8, args: anytype) Report {
        return .{
            .ok = false,
            .text = print("{s}" ++ fmt, .{self.text} ++ args),
        };
    }

    fn merge(comptime self: Report, comptime other: Report) Report {
        if (other.ok) return self;
        if (self.ok) return other;
        return .{
            .ok = false,
            .text = print("{s}{s}", .{ self.text, other.text }),
        };
    }
};

fn failure(comptime fmt: []const u8, args: anytype) Report {
    return (Report{}).fail(fmt, args);
}

fn indent(comptime text: []const u8) []const u8 {
    var out: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        out = print("{s}    {s}\n", .{ out, line });
    }
    return out;
}

/// Returns `true` when `Type` satisfies the contract described by `Trait`.
///
/// `Trait` must be a struct and is used as a template. Every public
/// declaration of `Trait` must have a matching public declaration in `Type`:
///
/// * associated constants must have the same type,
/// * associated types must be isomorphic (structs are checked recursively),
/// * associated functions must have isomorphic parameters and return type,
/// * methods additionally map `*Self`/`*const Self` to the implementation's
///   own self type, and accept `*anyopaque` as a type-erased self parameter.
///
/// Self references inside `Trait` (references to `Trait` itself or to another
/// declaration of `Trait`) are resolved against the corresponding declaration
/// of `Type`, rather than compared literally.
///
/// When the check fails and `report` is not null, every mismatch is written to
/// `report`. Since all arguments are compile-time values, `report` must point
/// to a compile-time variable:
///
/// ```zig
/// comptime var diagnostic: []const u8 = "";
/// const ok = comptime satisfy(Trait, Type, &diagnostic);
/// ```
pub fn satisfy(comptime Trait: type, comptime Type: type, comptime report: ?*[]const u8) bool {
    const result = comptime blk: {
        if (@typeInfo(Trait) != .@"struct") {
            @compileError("Trait must be a struct, but '" ++ @typeName(Trait) ++ "' is not.");
        }
        break :blk checkTrait(Trait, Type, &.{});
    };

    if (!result.ok) {
        if (report) |out| {
            out.* = print(
                "Type '{s}' does not satisfy Trait '{s}':\n{s}",
                .{ @typeName(Type), @typeName(Trait), result.text },
            );
        }
    }
    return result.ok;
}

fn checkTrait(comptime Trait: type, comptime Type: type, comptime seen: []const TraitPair) Report {
    // Associated types may refer back to the containing type. A pair that is
    // already being checked is assumed to match, which breaks the cycle.
    for (seen) |pair| {
        if (pair.trait == Trait and pair.ty == Type) return .{};
    }

    var out = Report{};
    const decl_names = @typeInfo(Trait).@"struct".decl_names;
    if (decl_names.len == 0) return out;

    const next_seen = seen ++ &[_]TraitPair{.{ .trait = Trait, .ty = Type }};
    const type_is_container = switch (@typeInfo(Type)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => true,
        else => false,
    };

    inline for (decl_names) |name| {
        if (!type_is_container) {
            out = out.fail(
                "  - missing declaration '{s}': '{s}' cannot contain declarations\n",
                .{ name, @typeName(Type) },
            );
            continue;
        }
        if (!@hasDecl(Type, name)) {
            out = out.fail("  - missing declaration '{s}'\n", .{name});
            continue;
        }

        const value_info = @typeInfo(@TypeOf(@field(Trait, name)));
        if (value_info == .@"fn") {
            out = out.merge(checkFunction(Trait, Type, name, value_info.@"fn"));
        } else if (value_info == .type) {
            const trait_type: type = @field(Trait, name);
            out = out.merge(checkAssociatedType(Trait, Type, name, trait_type, next_seen));
        } else {
            out = out.merge(checkConstant(Trait, Type, name));
        }
    }

    return out;
}

fn checkConstant(comptime Trait: type, comptime Type: type, comptime name: [:0]const u8) Report {
    const trait_type = @TypeOf(@field(Trait, name));
    const target_type = @TypeOf(@field(Type, name));

    if (!isomorphic(Trait, Type, trait_type, target_type, &.{}, true)) {
        return failure(
            "  - associated constant '{s}': expected type '{s}', found '{s}'\n",
            .{ name, expectedTypeName(Trait, Type, trait_type, null), @typeName(target_type) },
        );
    }
    return .{};
}

fn checkAssociatedType(
    comptime Trait: type,
    comptime Type: type,
    comptime name: [:0]const u8,
    comptime trait_type: type,
    comptime seen: []const TraitPair,
) Report {
    const target_value = @field(Type, name);
    if (@TypeOf(target_value) != type) {
        return failure(
            "  - associated type '{s}': Type's declaration is not a type (found '{s}')\n",
            .{ name, @typeName(@TypeOf(target_value)) },
        );
    }

    // `pub const Name = type;` means that any type is accepted.
    if (trait_type == type) return .{};

    if (Type != Trait and target_value != Type and isTraitOwned(Trait, target_value)) {
        return failure(
            "  - associated type '{s}': Type must declare its own type instead of referring to Trait's declaration\n",
            .{name},
        );
    }

    if (@typeInfo(trait_type) == .@"struct") {
        if (@typeInfo(target_value) != .@"struct") {
            return failure(
                "  - associated type '{s}': expected a structure, found '{s}'\n",
                .{ name, @typeName(target_value) },
            );
        }
        const nested = checkTrait(trait_type, target_value, seen);
        if (!nested.ok) {
            return failure(
                "  - associated type '{s}':\n{s}",
                .{ name, indent(nested.text) },
            );
        }
        return .{};
    }

    if (!isomorphic(Trait, Type, trait_type, target_value, &.{}, false)) {
        return failure(
            "  - associated type '{s}': expected type '{s}', found '{s}'\n",
            .{ name, expectedTypeName(Trait, Type, trait_type, name), @typeName(target_value) },
        );
    }
    return .{};
}

fn checkFunction(
    comptime Trait: type,
    comptime Type: type,
    comptime name: [:0]const u8,
    comptime trait_fn: std.lang.Type.Fn,
) Report {
    const target_value = @field(Type, name);
    const target_info = @typeInfo(@TypeOf(target_value));
    if (target_info != .@"fn") {
        return failure(
            "  - '{s}': expected a function, found a declaration of type '{s}'\n",
            .{ name, @typeName(@TypeOf(target_value)) },
        );
    }
    const target_fn = target_info.@"fn";

    if (isMethod(Trait, trait_fn))
        return checkMethod(Trait, Type, name, trait_fn, target_fn);

    return checkSignature(Trait, Type, name, trait_fn, target_fn, .function, 0);
}

fn checkMethod(
    comptime Trait: type,
    comptime Type: type,
    comptime name: [:0]const u8,
    comptime trait_fn: std.lang.Type.Fn,
    comptime target_fn: std.lang.Type.Fn,
) Report {
    var out = Report{};

    const trait_self = trait_fn.param_types[0].?;
    if (target_fn.param_types.len == 0) {
        out = out.fail(
            "  - method '{s}': expected a self parameter, found none\n",
            .{name},
        );
    } else if (target_fn.param_types[0]) |target_self| {
        if (!selfCompatible(Trait, Type, trait_self, target_self)) {
            out = out.fail(
                "  - method '{s}': self parameter expected '{s}', found '{s}'\n",
                .{ name, expectedTypeName(Trait, Type, trait_self, null), @typeName(target_self) },
            );
        }
    } else {
        out = out.fail(
            "  - method '{s}': Type's self parameter is generic, expected '{s}'\n",
            .{ name, expectedTypeName(Trait, Type, trait_self, null) },
        );
    }

    return out.merge(checkSignature(Trait, Type, name, trait_fn, target_fn, .method, 1));
}

fn checkSignature(
    comptime Trait: type,
    comptime Type: type,
    comptime name: [:0]const u8,
    comptime trait_fn: std.lang.Type.Fn,
    comptime target_fn: std.lang.Type.Fn,
    comptime kind: FunctionKind,
    comptime start: usize,
) Report {
    var out = Report{};

    if (!std.meta.eql(trait_fn.attrs.@"callconv", target_fn.attrs.@"callconv")) {
        out = out.fail(
            "  - {s} '{s}': calling convention differs\n",
            .{ @tagName(kind), name },
        );
    }
    if (trait_fn.attrs.varargs != target_fn.attrs.varargs) {
        out = out.fail("  - {s} '{s}': variadic-ness differs\n", .{ @tagName(kind), name });
    }

    if (trait_fn.param_types.len != target_fn.param_types.len) {
        out = out.fail(
            "  - {s} '{s}': expected {d} parameter(s), found {d}\n",
            .{ @tagName(kind), name, trait_fn.param_types.len, target_fn.param_types.len },
        );
    } else {
        out = out.merge(checkParamTypes(
            Trait,
            Type,
            name,
            kind,
            trait_fn.param_types[start..],
            target_fn.param_types[start..],
            start,
        ));
    }

    if ((trait_fn.return_type == null) != (target_fn.return_type == null)) {
        out = out.fail(
            "  - {s} '{s}': return type is generic in Trait but not in Type (or vice versa)\n",
            .{ @tagName(kind), name },
        );
    } else if (trait_fn.return_type) |trait_return| {
        if (!isomorphic(Trait, Type, trait_return, target_fn.return_type.?, &.{}, true)) {
            out = out.fail(
                "  - {s} '{s}': return type expected '{s}', found '{s}'\n",
                .{ @tagName(kind), name, expectedTypeName(Trait, Type, trait_return, null), @typeName(target_fn.return_type.?) },
            );
        }
    }

    return out;
}

fn checkParamTypes(
    comptime Trait: type,
    comptime Type: type,
    comptime name: [:0]const u8,
    comptime kind: FunctionKind,
    comptime trait_params: []const ?type,
    comptime target_params: []const ?type,
    comptime offset: usize,
) Report {
    var out = Report{};

    inline for (trait_params, target_params, 0..) |trait_param, target_param, i| {
        const position = offset + i + 1;
        if ((trait_param == null) != (target_param == null)) {
            out = out.fail(
                "  - {s} '{s}': parameter {d} is generic in Trait but not in Type (or vice versa)\n",
                .{ @tagName(kind), name, position },
            );
            continue;
        }
        if (trait_param) |trait_type| {
            if (!isomorphic(Trait, Type, trait_type, target_param.?, &.{}, true)) {
                out = out.fail(
                    "  - {s} '{s}': parameter {d} expected '{s}', found '{s}'\n",
                    .{ @tagName(kind), name, position, expectedTypeName(Trait, Type, trait_type, null), @typeName(target_param.?) },
                );
            }
        }
    }

    return out;
}

fn isMethod(comptime Trait: type, comptime f: std.lang.Type.Fn) bool {
    if (f.param_types.len == 0) return false;
    const self_type = f.param_types[0] orelse return false;
    if (self_type == Trait) return true;

    const info = @typeInfo(self_type);
    if (info != .pointer) return false;
    const ptr = info.pointer;
    if (ptr.size != .one) return false;
    return ptr.child == Trait or ptr.child == anyopaque;
}

fn selfCompatible(comptime Trait: type, comptime Type: type, comptime trait_self: type, comptime target_self: type) bool {
    const trait_erased = isErasedPointer(trait_self);
    const target_erased = isErasedPointer(target_self);

    if (trait_erased or target_erased) {
        if (trait_erased and (target_erased or isPointerTo(Type, target_self))) return true;
        if (target_erased and isPointerTo(Trait, trait_self)) return true;
        return false;
    }

    return isomorphic(Trait, Type, trait_self, target_self, &.{}, true);
}

fn isErasedPointer(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    return info.pointer.size == .one and info.pointer.child == anyopaque;
}

fn isPointerTo(comptime Child: type, comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    return info.pointer.size == .one and info.pointer.child == Child;
}

/// Returns the name of the declaration of `Trait` that `T` corresponds to.
/// The empty string denotes `Trait` itself.
fn traitDeclOf(comptime Trait: type, comptime T: type) ?[]const u8 {
    if (T == Trait) return "";

    switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => {},
        else => return null,
    }

    const trait_name = @typeName(Trait);
    const type_name = @typeName(T);
    if (type_name.len <= trait_name.len + 1) return null;
    if (!std.mem.startsWith(u8, type_name, trait_name)) return null;
    if (type_name[trait_name.len] != '.') return null;

    const decl_name = type_name[trait_name.len + 1 ..];
    if (std.mem.indexOfScalar(u8, decl_name, '.') != null) return null;

    inline for (@typeInfo(Trait).@"struct".decl_names) |name| {
        if (std.mem.eql(u8, decl_name, name)) return decl_name;
    }
    return null;
}

fn isTraitOwned(comptime Trait: type, comptime T: type) bool {
    return traitDeclOf(Trait, T) != null;
}

/// Returns true when `T` is `Trait`'s declaration or contains one through a
/// type constructor such as a pointer, array, optional, error union, vector,
/// anyframe or function signature. Named containers are treated as leaves so
/// that unrelated implementation types are never inspected recursively.
fn containsTraitOwned(comptime Trait: type, comptime implementation: type, comptime T: type) bool {
    // Referring to the implementation itself is exactly what the rules ask
    // for, even when the implementation happens to be declared by `Trait`.
    if (T == implementation) return false;
    if (isTraitOwned(Trait, T)) return true;

    return switch (@typeInfo(T)) {
        .pointer => |p| containsTraitOwned(Trait, implementation, p.child),
        .array => |a| containsTraitOwned(Trait, implementation, a.child),
        .optional => |o| containsTraitOwned(Trait, implementation, o.child),
        .error_union => |e| containsTraitOwned(Trait, implementation, e.error_set) or
            containsTraitOwned(Trait, implementation, e.payload),
        .vector => |v| containsTraitOwned(Trait, implementation, v.child),
        .@"anyframe" => |a| if (a.child) |child| containsTraitOwned(Trait, implementation, child) else false,
        .@"fn" => |f| blk: {
            inline for (f.param_types) |param| {
                if (param) |param_type| {
                    if (containsTraitOwned(Trait, implementation, param_type)) break :blk true;
                }
            }
            if (f.return_type) |return_type| {
                if (containsTraitOwned(Trait, implementation, return_type)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

/// Maps a type that refers to a declaration of `Trait` to the corresponding
/// declaration of `Type`.
fn resolve(comptime Trait: type, comptime Type: type, comptime T: type) type {
    if (T == Trait) return Type;

    if (traitDeclOf(Trait, T)) |decl_name| {
        inline for (@typeInfo(Trait).@"struct".decl_names) |name| {
            if (std.mem.eql(u8, decl_name, name)) {
                if (@hasDecl(Type, name) and @TypeOf(@field(Type, name)) == type)
                    return @field(Type, name);
            }
        }
    }

    // `type` is the placeholder used by `pub const Name = type;`.
    if (T == type) {
        inline for (@typeInfo(Trait).@"struct".decl_names) |name| {
            if (@TypeOf(@field(Trait, name)) == type and @field(Trait, name) == type) {
                if (@hasDecl(Type, name) and @TypeOf(@field(Type, name)) == type)
                    return @field(Type, name);
            }
        }
    }

    // A declaration whose value is exactly `T` also maps to the corresponding
    // declaration of `Type`, even when the type itself is not declared inside
    // `Trait` (for example an imported type). Only unambiguous matches are
    // resolved.
    comptime var matched_name: ?[]const u8 = null;
    comptime var matched_count: usize = 0;
    inline for (@typeInfo(Trait).@"struct".decl_names) |name| {
        if (@TypeOf(@field(Trait, name)) == type and @field(Trait, name) == T) {
            matched_count += 1;
            if (matched_name == null) matched_name = name;
        }
    }
    if (matched_count == 1) {
        const name = matched_name.?;
        if (@hasDecl(Type, name) and @TypeOf(@field(Type, name)) == type)
            return @field(Type, name);
    }

    return T;
}

fn isomorphic(
    comptime Trait: type,
    comptime Type: type,
    comptime a_in: type,
    comptime b: type,
    comptime seen: []const TypePair,
    comptime resolve_root: bool,
) bool {
    const a = if (resolve_root) resolve(Trait, Type, a_in) else a_in;

    // `Type` must never refer back to a declaration of `Trait` instead of
    // using its own corresponding declaration. Only type constructors are
    // inspected here; named containers are leaves (their own declarations are
    // checked separately).
    if (Type != Trait and containsTraitOwned(Trait, Type, b)) return false;
    if (a == b) return true;

    for (seen) |pair| {
        if (pair.a == a and pair.b == b) return true;
    }
    const next_seen = seen ++ &[_]TypePair{.{ .a = a, .b = b }};

    switch (@typeInfo(a)) {
        .type => return false,
        .void, .bool, .noreturn, .comptime_float, .comptime_int, .undefined, .null, .enum_literal => {
            // These types are singletons; `a == b` was already checked above.
            return false;
        },
        .int => |a_int| return switch (@typeInfo(b)) {
            .int => |b_int| a_int.bits == b_int.bits and a_int.signedness == b_int.signedness,
            else => false,
        },
        .float => |a_float| return switch (@typeInfo(b)) {
            .float => |b_float| a_float.bits == b_float.bits,
            else => false,
        },
        .pointer => |a_ptr| return switch (@typeInfo(b)) {
            .pointer => |b_ptr| isomorphicPointer(Trait, Type, a_ptr, b_ptr, next_seen),
            else => false,
        },
        .array => |a_arr| return switch (@typeInfo(b)) {
            .array => |b_arr| isomorphicArray(Trait, Type, a_arr, b_arr, next_seen),
            else => false,
        },
        .@"struct" => |a_struct| return switch (@typeInfo(b)) {
            .@"struct" => |b_struct| isomorphicStruct(Trait, Type, a_struct, b_struct, next_seen),
            else => false,
        },
        .optional => |a_opt| return switch (@typeInfo(b)) {
            .optional => |b_opt| isomorphic(Trait, Type, a_opt.child, b_opt.child, next_seen, true),
            else => false,
        },
        .error_union => |a_eu| return switch (@typeInfo(b)) {
            .error_union => |b_eu| isomorphic(Trait, Type, a_eu.error_set, b_eu.error_set, next_seen, true) and
                isomorphic(Trait, Type, a_eu.payload, b_eu.payload, next_seen, true),
            else => false,
        },
        .error_set => return switch (@typeInfo(b)) {
            .error_set => true,
            else => false,
        },
        .@"enum" => |a_enum| return switch (@typeInfo(b)) {
            .@"enum" => |b_enum| isomorphicEnum(Trait, Type, a_enum, b_enum, next_seen),
            else => false,
        },
        .@"union" => |a_union| return switch (@typeInfo(b)) {
            .@"union" => |b_union| isomorphicUnion(Trait, Type, a_union, b_union, next_seen),
            else => false,
        },
        .@"fn" => |a_fn| return switch (@typeInfo(b)) {
            .@"fn" => |b_fn| isomorphicFn(Trait, Type, a_fn, b_fn, next_seen),
            else => false,
        },
        .@"opaque" => return switch (@typeInfo(b)) {
            .@"opaque" => true,
            else => false,
        },
        .frame => return switch (@typeInfo(b)) {
            .frame => true,
            else => false,
        },
        .@"anyframe" => |a_af| return switch (@typeInfo(b)) {
            .@"anyframe" => |b_af| isomorphicAnyframe(Trait, Type, a_af, b_af, next_seen),
            else => false,
        },
        .vector => |a_vec| return switch (@typeInfo(b)) {
            .vector => |b_vec| a_vec.len == b_vec.len and
                isomorphic(Trait, Type, a_vec.child, b_vec.child, next_seen, true),
            else => false,
        },
        .spirv => |a_spirv| return switch (@typeInfo(b)) {
            .spirv => |b_spirv| std.meta.eql(a_spirv, b_spirv),
            else => false,
        },
    }
}

fn isomorphicPointer(
    comptime Trait: type,
    comptime Type: type,
    comptime a: std.lang.Type.Pointer,
    comptime b: std.lang.Type.Pointer,
    comptime seen: []const TypePair,
) bool {
    if (a.size != b.size) return false;
    if (a.attrs.@"const" != b.attrs.@"const") return false;
    if (a.attrs.@"volatile" != b.attrs.@"volatile") return false;
    if (a.attrs.@"allowzero" != b.attrs.@"allowzero") return false;
    if (a.attrs.@"addrspace" != b.attrs.@"addrspace") return false;

    const a_align = pointerAlignment(a);
    const b_align = pointerAlignment(b);
    if ((a_align == null) != (b_align == null)) return false;
    if (a_align) |alignment| {
        if (alignment != b_align.?) return false;
    }

    if ((a.sentinel_ptr == null) != (b.sentinel_ptr == null)) return false;

    return isomorphic(Trait, Type, a.child, b.child, seen, true);
}

/// Returns the pointee alignment of a pointer type, or null when the pointee
/// is an uninstantiable type (for example `opaque`) for which Zig has no
/// alignment value.
fn pointerAlignment(comptime p: std.lang.Type.Pointer) ?usize {
    if (p.attrs.@"align") |alignment| return alignment;
    return naturalAlignment(p.child);
}

fn naturalAlignment(comptime T: type) ?usize {
    return switch (@typeInfo(T)) {
        .type,
        .noreturn,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .@"fn",
        .@"opaque",
        .frame,
        .@"anyframe",
        .enum_literal,
        .spirv,
        => null,
        else => @alignOf(T),
    };
}

fn isomorphicArray(
    comptime Trait: type,
    comptime Type: type,
    comptime a: std.lang.Type.Array,
    comptime b: std.lang.Type.Array,
    comptime seen: []const TypePair,
) bool {
    if (a.len != b.len) return false;
    if ((a.sentinel_ptr == null) != (b.sentinel_ptr == null)) return false;
    return isomorphic(Trait, Type, a.child, b.child, seen, true);
}

fn isomorphicStruct(
    comptime Trait: type,
    comptime Type: type,
    comptime a: std.lang.Type.Struct,
    comptime b: std.lang.Type.Struct,
    comptime seen: []const TypePair,
) bool {
    if (a.is_tuple != b.is_tuple) return false;
    if (a.layout != b.layout) return false;
    if (a.field_names.len != b.field_names.len) return false;

    inline for (a.field_names, b.field_names, a.field_types, b.field_types) |a_name, b_name, a_type, b_type| {
        if (!std.mem.eql(u8, a_name, b_name)) return false;
        if (!isomorphic(Trait, Type, a_type, b_type, seen, true)) return false;
    }

    return true;
}

fn isomorphicEnum(
    comptime Trait: type,
    comptime Type: type,
    comptime a: std.lang.Type.Enum,
    comptime b: std.lang.Type.Enum,
    comptime seen: []const TypePair,
) bool {
    _ = Trait;
    _ = Type;
    _ = seen;

    if (a.mode != b.mode) return false;
    if (a.tag_type != b.tag_type) return false;
    if (a.field_names.len != b.field_names.len) return false;

    inline for (a.field_names, b.field_names, a.field_values, b.field_values) |a_name, b_name, a_value, b_value| {
        if (!std.mem.eql(u8, a_name, b_name)) return false;
        if (a_value != b_value) return false;
    }

    return true;
}

fn isomorphicUnion(
    comptime Trait: type,
    comptime Type: type,
    comptime a: std.lang.Type.Union,
    comptime b: std.lang.Type.Union,
    comptime seen: []const TypePair,
) bool {
    if (a.layout != b.layout) return false;
    if ((a.tag_type == null) != (b.tag_type == null)) return false;
    if (a.field_names.len != b.field_names.len) return false;

    inline for (a.field_names, b.field_names, a.field_types, b.field_types) |a_name, b_name, a_type, b_type| {
        if (!std.mem.eql(u8, a_name, b_name)) return false;
        if (!isomorphic(Trait, Type, a_type, b_type, seen, true)) return false;
    }

    if (a.tag_type) |a_tag| {
        if (!isomorphic(Trait, Type, a_tag, b.tag_type.?, seen, true)) return false;
    }

    return true;
}

fn isomorphicFn(
    comptime Trait: type,
    comptime Type: type,
    comptime a: std.lang.Type.Fn,
    comptime b: std.lang.Type.Fn,
    comptime seen: []const TypePair,
) bool {
    if (!std.meta.eql(a.attrs.@"callconv", b.attrs.@"callconv")) return false;
    if (a.attrs.varargs != b.attrs.varargs) return false;
    if (a.param_types.len != b.param_types.len) return false;

    inline for (a.param_types, b.param_types) |a_param, b_param| {
        if ((a_param == null) != (b_param == null)) return false;
        if (a_param) |a_type| {
            if (!isomorphic(Trait, Type, a_type, b_param.?, seen, true)) return false;
        }
    }

    if ((a.return_type == null) != (b.return_type == null)) return false;
    if (a.return_type) |a_return| {
        if (!isomorphic(Trait, Type, a_return, b.return_type.?, seen, true)) return false;
    }

    return true;
}

fn isomorphicAnyframe(
    comptime Trait: type,
    comptime Type: type,
    comptime a: std.lang.Type.AnyFrame,
    comptime b: std.lang.Type.AnyFrame,
    comptime seen: []const TypePair,
) bool {
    if ((a.child == null) != (b.child == null)) return false;
    if (a.child) |child| {
        return isomorphic(Trait, Type, child, b.child.?, seen, true);
    }
    return true;
}

/// Renders the type that `Type` is expected to have for a Trait-side type
/// `T`. References to `Trait` and its declarations are replaced with the
/// corresponding declarations of `Type`.
///
/// `own_name` is non-null only while rendering the value of an associated type
/// declaration. The declaration's own value is not substituted with `Type`'s
/// declaration; only references nested inside it are.
fn expectedTypeName(
    comptime Trait: type,
    comptime Type: type,
    comptime T: type,
    comptime own_name: ?[]const u8,
) []const u8 {
    if (own_name) |name| {
        if (@hasDecl(Trait, name)) {
            const named_decl = traitDeclOf(Trait, T);
            const refers_to_another = if (named_decl) |decl_name|
                !std.mem.eql(u8, decl_name, name)
            else
                false;

            if (!refers_to_another) {
                const own_value = @field(Trait, name);
                if (@TypeOf(own_value) == type and own_value == T) {
                    return renderType(Trait, Type, T);
                }
            }
        }
    }

    return renderResolvedType(Trait, Type, T);
}

fn renderResolvedType(comptime Trait: type, comptime Type: type, comptime T: type) []const u8 {
    const resolved = resolve(Trait, Type, T);
    if (resolved != T) return @typeName(resolved);
    return renderType(Trait, Type, T);
}

fn renderType(comptime Trait: type, comptime Type: type, comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .pointer => |p| print("{s}{s}", .{ pointerPrefix(p), renderResolvedType(Trait, Type, p.child) }),
        .array => |a| print("[{d}]{s}", .{ a.len, renderResolvedType(Trait, Type, a.child) }),
        .optional => |o| print("?{s}", .{renderResolvedType(Trait, Type, o.child)}),
        .error_union => |e| print("{s}!{s}", .{
            renderResolvedType(Trait, Type, e.error_set),
            renderResolvedType(Trait, Type, e.payload),
        }),
        .vector => |v| print("@Vector({d}, {s})", .{ v.len, renderResolvedType(Trait, Type, v.child) }),
        .@"anyframe" => |a| if (a.child) |child|
            print("anyframe->{s}", .{renderResolvedType(Trait, Type, child)})
        else
            "anyframe",
        .@"fn" => |f| renderFnType(Trait, Type, f),
        else => @typeName(T),
    };
}

fn renderFnType(comptime Trait: type, comptime Type: type, comptime f: std.lang.Type.Fn) []const u8 {
    var out: []const u8 = "fn (";
    inline for (f.param_types, 0..) |param, i| {
        if (i != 0) out = print("{s}, ", .{out});
        if (param) |param_type| {
            out = print("{s}{s}", .{ out, renderResolvedType(Trait, Type, param_type) });
        } else {
            out = print("{s}anytype", .{out});
        }
    }
    out = print("{s}) ", .{out});
    if (f.return_type) |return_type| {
        out = print("{s}{s}", .{ out, renderResolvedType(Trait, Type, return_type) });
    } else {
        out = print("{s}anytype", .{out});
    }
    return out;
}

fn pointerPrefix(comptime p: std.lang.Type.Pointer) []const u8 {
    var out: []const u8 = switch (p.size) {
        .one => "*",
        .many => "[*]",
        .slice => "[]",
        .c => "[*c]",
    };

    if (p.attrs.@"allowzero") out = print("{s}allowzero ", .{out});
    if (p.attrs.@"align") |alignment| out = print("{s}align({d}) ", .{ out, alignment });
    if (p.attrs.@"volatile") out = print("{s}volatile ", .{out});
    if (p.attrs.@"const") out = print("{s}const ", .{out});

    return out;
}

// ===================================== TESTS =====================================

test "satisfy: empty trait accepts any type" {
    const Trait = struct {};

    try std.testing.expect(comptime satisfy(Trait, struct {}, null));
    try std.testing.expect(comptime satisfy(Trait, u32, null));
    try std.testing.expect(comptime satisfy(Trait, *anyopaque, null));
}

test "satisfy: missing declarations are reported" {
    const Trait = struct {
        pub fn foo() void {}
    };
    const Type = struct {};

    try std.testing.expect(!comptime satisfy(Trait, Type, null));

    comptime var diagnostic: []const u8 = "";
    try std.testing.expect(!comptime satisfy(Trait, Type, &diagnostic));
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "foo") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "missing declaration") != null);
}

test "satisfy: private trait declarations are ignored" {
    const Trait = struct {
        pub fn visible() void {}
        fn hidden() void {}
    };
    const Type = struct {
        pub fn visible() void {}
    };

    try std.testing.expect(comptime satisfy(Trait, Type, null));
}

test "satisfy: associated constants" {
    const Trait = struct {
        pub const count: usize = undefined;
        pub const flag: bool = undefined;
    };

    const Good = struct {
        pub const count: usize = 42;
        pub const flag: bool = true;
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const WrongType = struct {
        pub const count: u32 = 42;
        pub const flag: bool = true;
    };
    try std.testing.expect(!comptime satisfy(Trait, WrongType, null));

    const Missing = struct {
        pub const count: usize = 0;
    };
    try std.testing.expect(!comptime satisfy(Trait, Missing, null));
}

test "satisfy: associated type placeholder accepts any type" {
    const Trait = struct {
        pub const Item = type;
    };

    const WithInt = struct {
        pub const Item = u32;
    };
    try std.testing.expect(comptime satisfy(Trait, WithInt, null));

    const WithPointer = struct {
        pub const Item = *const u8;
    };
    try std.testing.expect(comptime satisfy(Trait, WithPointer, null));

    // The declaration has to exist and has to be a type.
    const Missing = struct {};
    try std.testing.expect(!comptime satisfy(Trait, Missing, null));

    const NotAType = struct {
        pub const Item: u32 = 1;
    };
    try std.testing.expect(!comptime satisfy(Trait, NotAType, null));
}

test "satisfy: concrete associated types" {
    const Trait = struct {
        pub const Item = u32;
    };

    const Good = struct {
        pub const Item = u32;
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const Bad = struct {
        pub const Item = u64;
    };
    try std.testing.expect(!comptime satisfy(Trait, Bad, null));
}

test "satisfy: associated types are checked recursively" {
    const Trait = struct {
        pub const Item = struct {
            pub fn describe() []const u8 {
                unreachable;
            }
        };
    };

    const Good = struct {
        pub const Item = struct {
            pub fn describe() []const u8 {
                return "good";
            }
        };
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const MissingDecl = struct {
        pub const Item = struct {};
    };
    try std.testing.expect(!comptime satisfy(Trait, MissingDecl, null));

    const WrongKind = struct {
        pub const Item = u32;
    };
    try std.testing.expect(!comptime satisfy(Trait, WrongKind, null));
}

test "satisfy: nested associated types" {
    const Trait = struct {
        pub const Outer = struct {
            pub const Inner = struct {
                pub fn foo() void {}
            };
        };
    };

    const Good = struct {
        pub const Outer = struct {
            pub const Inner = struct {
                pub fn foo() void {}
            };
        };
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const Bad = struct {
        pub const Outer = struct {
            pub const Inner = struct {};
        };
    };
    try std.testing.expect(!comptime satisfy(Trait, Bad, null));
}

test "satisfy: associated enum types and unrelated error sets" {
    const Trait = struct {
        pub const Color = enum { red, green };
        pub const Failure = error{OutOfMemory};
    };

    const Good = struct {
        pub const Color = enum { red, green };
        pub const Failure = error{OutOfMemory};
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const BadColor = struct {
        pub const Color = enum { red, blue };
        pub const Failure = error{OutOfMemory};
    };
    try std.testing.expect(!comptime satisfy(Trait, BadColor, null));

    // Error sets are not required to be isomorphic.
    const OtherError = struct {
        pub const Color = enum { red, green };
        pub const Failure = error{InvalidArgument};
    };
    try std.testing.expect(comptime satisfy(Trait, OtherError, null));
}

test "satisfy: associated functions" {
    const Trait = struct {
        pub fn foo(a: i32, b: ?[]const u8) !void {
            _ = a;
            _ = b;
            unreachable;
        }
    };

    const Good = struct {
        pub fn foo(a: i32, b: ?[]const u8) !void {
            _ = a;
            _ = b;
            unreachable;
        }
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const BadParam = struct {
        pub fn foo(a: u32, b: ?[]const u8) !void {
            _ = a;
            _ = b;
            unreachable;
        }
    };
    try std.testing.expect(!comptime satisfy(Trait, BadParam, null));

    const BadReturn = struct {
        pub fn foo(a: i32, b: ?[]const u8) void {
            _ = a;
            _ = b;
        }
    };
    try std.testing.expect(!comptime satisfy(Trait, BadReturn, null));

    const BadCount = struct {
        pub fn foo(a: i32) !void {
            _ = a;
            unreachable;
        }
    };
    try std.testing.expect(!comptime satisfy(Trait, BadCount, null));
}

test "satisfy: generic parameters" {
    const Trait = struct {
        pub fn call(value: anytype) void {
            _ = value;
        }
    };

    const Good = struct {
        pub fn call(value: anytype) void {
            _ = value;
        }
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const Bad = struct {
        pub fn call(value: u32) void {
            _ = value;
        }
    };
    try std.testing.expect(!comptime satisfy(Trait, Bad, null));
}

test "satisfy: methods" {
    const Trait = struct {
        pub fn init(self: *@This()) void {
            _ = self;
        }
        pub fn value(self: *const @This()) u32 {
            _ = self;
            unreachable;
        }
    };

    const Good = struct {
        pub fn init(self: *@This()) void {
            _ = self;
        }
        pub fn value(self: *const @This()) u32 {
            _ = self;
            return 0;
        }
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const BadConst = struct {
        pub fn init(self: *const @This()) void {
            _ = self;
        }
        pub fn value(self: *const @This()) u32 {
            _ = self;
            return 0;
        }
    };
    try std.testing.expect(!comptime satisfy(Trait, BadConst, null));

    const BadReturn = struct {
        pub fn init(self: *@This()) void {
            _ = self;
        }
        pub fn value(self: *const @This()) u64 {
            _ = self;
            return 0;
        }
    };
    try std.testing.expect(!comptime satisfy(Trait, BadReturn, null));
}

test "satisfy: associated type in a method signature" {
    const Trait = struct {
        pub const Item = type;
        pub fn get(self: *@This(), index: usize) Item {
            _ = self;
            _ = index;
            unreachable;
        }
    };

    const Good = struct {
        pub const Item = u32;
        pub fn get(self: *@This(), index: usize) u32 {
            _ = self;
            _ = index;
            return 0;
        }
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const Bad = struct {
        pub const Item = u32;
        pub fn get(self: *@This(), index: usize) u64 {
            _ = self;
            _ = index;
            return 0;
        }
    };
    try std.testing.expect(!comptime satisfy(Trait, Bad, null));
}

test "satisfy: self references map to Type's declarations" {
    const Trait = struct {
        pub const Self = @This();
        pub fn clone(self: *Self) Self {
            _ = self;
            unreachable;
        }
    };

    const Good = struct {
        pub const Self = @This();
        pub fn clone(self: *Self) Self {
            _ = self;
            return .{};
        }
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    // This implementation refers to Trait instead of its own type.
    const Bad = struct {
        pub const Self = @This();
        pub fn clone(self: *Trait) Trait {
            _ = self;
            unreachable;
        }
    };
    try std.testing.expect(!comptime satisfy(Trait, Bad, null));
}

test "satisfy: self-referencing constant types" {
    const Trait = struct {
        pub const Node = struct {
            pub const tag = 1;
        };
        pub const callback: *const Node = undefined;
    };

    const Good = struct {
        pub const Node = struct {
            pub const tag = 2;
        };
        pub const callback: *const Node = undefined;
    };
    try std.testing.expect(comptime satisfy(Trait, Good, null));

    const Bad = struct {
        pub const Node = struct {
            pub const tag = 2;
        };
        pub const callback: *const Trait.Node = undefined;
    };
    try std.testing.expect(!comptime satisfy(Trait, Bad, null));
}

test "satisfy: type-erased self parameter" {
    const Trait = struct {
        pub fn run(self: *anyopaque) void {
            _ = self;
        }
    };

    const Mutable = struct {
        pub fn run(self: *@This()) void {
            _ = self;
        }
    };
    try std.testing.expect(comptime satisfy(Trait, Mutable, null));

    const Const = struct {
        pub fn run(self: *const @This()) void {
            _ = self;
        }
    };
    try std.testing.expect(comptime satisfy(Trait, Const, null));

    const ByValue = struct {
        pub fn run(self: @This()) void {
            _ = self;
        }
    };
    try std.testing.expect(!comptime satisfy(Trait, ByValue, null));
}

test "satisfy: report collects every mismatch" {
    const Trait = struct {
        pub const a: i32 = 0;
        pub const b: u32 = 0;
        pub fn c(x: bool) void {
            _ = x;
        }
        pub fn d(self: *@This()) void {
            _ = self;
        }
    };

    const Type = struct {
        pub const a: u64 = 0;
        pub fn c(x: u8) void {
            _ = x;
        }
        pub fn d(self: *@This(), extra: u8) void {
            _ = self;
            _ = extra;
        }
    };

    comptime var diagnostic: []const u8 = "";
    try std.testing.expect(!comptime satisfy(Trait, Type, &diagnostic));

    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "'a'") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "'b'") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "'c'") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "'d'") != null);
}

test "satisfy: imported associated types are mapped" {
    const Imported = struct {
        pub const marker = 1;
    };

    const Trait = struct {
        pub const ImportedType = Imported;
        pub fn take(value: ImportedType) void {
            _ = value;
        }
    };

    const Type = struct {
        pub const ImportedType = struct {
            pub const marker = 2;
        };
        pub fn take(value: ImportedType) void {
            _ = value;
        }
    };

    try std.testing.expect(comptime satisfy(Trait, Type, null));
}

test "satisfy: Type's associated type must not alias Trait's" {
    const Trait = struct {
        pub const Node = struct {
            pub const tag = 1;
        };
    };

    const Bad = struct {
        pub const Node = Trait.Node;
    };

    try std.testing.expect(!comptime satisfy(Trait, Bad, null));
}

test "satisfy: a trait satisfies itself" {
    const Trait = struct {
        pub const Self = @This();
        pub const Item = type;
        pub fn take(self: *Self, value: Item) void {
            _ = self;
            _ = value;
        }
    };

    try std.testing.expect(comptime satisfy(Trait, Trait, null));
}

test "satisfy: type-erased self works in both directions" {
    const Trait = struct {
        pub fn run(self: *@This()) void {
            _ = self;
        }
    };

    const Erased = struct {
        pub fn run(self: *anyopaque) void {
            _ = self;
        }
    };

    try std.testing.expect(comptime satisfy(Trait, Erased, null));
}

test "satisfy: usable in a runtime expression" {
    const Trait = struct {
        pub const Item = u32;
    };
    const Type = struct {
        pub const Item = u32;
    };

    if (!satisfy(Trait, Type, null)) return error.Unexpected;
}

test "satisfy: report describes nested associated type failures" {
    const Trait = struct {
        pub const Item = struct {
            pub fn missing() void {}
        };
    };
    const Type = struct {
        pub const Item = struct {};
    };

    comptime var diagnostic: []const u8 = "";
    try std.testing.expect(!comptime satisfy(Trait, Type, &diagnostic));
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "associated type 'Item'") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "missing declaration 'missing'") != null);
}

test "satisfy: non-struct types cannot provide declarations" {
    const Trait = struct {
        pub fn foo() void {}
    };

    try std.testing.expect(!comptime satisfy(Trait, u32, null));

    comptime var diagnostic: []const u8 = "";
    try std.testing.expect(!comptime satisfy(Trait, u32, &diagnostic));
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "foo") != null);
}

test "satisfy: report substitutes the implementation's self type" {
    const Trait = struct {
        pub const Self = @This();
        pub fn value(self: *Self) void {
            _ = self;
        }
    };
    const Type = struct {
        pub const Self = @This();
        pub fn value(self: *const Self) void {
            _ = self;
        }
    };

    comptime var diagnostic: []const u8 = "";
    try std.testing.expect(!comptime satisfy(Trait, Type, &diagnostic));

    const expected = std.fmt.comptimePrint("expected '*{s}'", .{@typeName(Type)});
    const wrong = std.fmt.comptimePrint("expected '*{s}'", .{@typeName(Trait)});
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, expected) != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, wrong) == null);
}

test "satisfy: report substitutes container declarations" {
    const Trait = struct {
        pub const Node = struct {
            pub const tag = 1;
        };
        pub const current: *const Node = undefined;
    };
    const Type = struct {
        pub const Node = struct {
            pub const tag = 2;
        };
        pub const current: *const u8 = undefined;
    };

    comptime var diagnostic: []const u8 = "";
    try std.testing.expect(!comptime satisfy(Trait, Type, &diagnostic));

    const expected = std.fmt.comptimePrint("expected type '*const {s}'", .{@typeName(Type.Node)});
    const wrong = std.fmt.comptimePrint("expected type '*const {s}'", .{@typeName(Trait.Node)});
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, expected) != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, wrong) == null);
}

test "satisfy: report maps an alias of another declaration" {
    const Trait = struct {
        pub const Color = enum { red, green };
        pub const Alias = Color;
    };
    const Type = struct {
        pub const Color = enum { red, green };
        pub const Alias = u32;
    };

    comptime var diagnostic: []const u8 = "";
    try std.testing.expect(!comptime satisfy(Trait, Type, &diagnostic));

    const expected = std.fmt.comptimePrint("expected type '{s}'", .{@typeName(Type.Color)});
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, expected) != null);
}

test "satisfy: report keeps an associated type's own value" {
    const Trait = struct {
        pub const Item = u32;
    };
    const Type = struct {
        pub const Item = u64;
    };

    comptime var diagnostic: []const u8 = "";
    try std.testing.expect(!comptime satisfy(Trait, Type, &diagnostic));
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "expected type 'u32'") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic, "expected type 'u64'") == null);
}

test "satisfy: pointers to opaque types" {
    const Trait = struct {
        pub const Handle = opaque {};
        pub fn get() *Handle {
            unreachable;
        }
    };
    const Type = struct {
        pub const Handle = opaque {};
        pub fn get() *Handle {
            unreachable;
        }
    };

    try std.testing.expect(comptime satisfy(Trait, Type, null));
}

test "satisfy: function pointer types" {
    const Trait = struct {
        pub const Callback = *const fn (u32) void;
        pub fn callback() Callback {
            unreachable;
        }
    };
    const Type = struct {
        pub const Callback = *const fn (u32) void;
        pub fn callback() Callback {
            unreachable;
        }
    };

    try std.testing.expect(comptime satisfy(Trait, Type, null));
}
