# vftrait

Compile-time structural trait checking for Zig.

`vftrait` verifies at compile time whether a type matches a trait template. The
idea is similar to C++ `concepts`/`requires` and Rust traits. Zig's `anytype`
together with compiler errors already covers many use cases; this project
focuses on:

- letting static and dynamic dispatch coexist;
- giving ZLS more useful completion and type information;
- validating a type once and reporting every mismatch at the same time.

Requires Zig 0.17.0 or later.

## Installation

```sh
zig fetch --save git+https://github.com/Verafahn/vftrait
```

Then add the module in your `build.zig`:

```zig
const vftrait = b.dependency("vftrait", .{
    .target = target,
    .optimize = optimize,
});

// `exe` is the executable or library that should use the module.
exe.root_module.addImport("vftrait", vftrait.module("vftrait"));
```

## Usage

```zig
const vftrait = @import("vftrait");

const Iterator = struct {
    pub const Item = type;

    pub fn next(self: *@This()) ?Item {
        _ = self;
        unreachable;
    }
};

const Counter = struct {
    pub const Item = u32;
    remaining: u32 = 3,

    pub fn next(self: *@This()) ?u32 {
        if (self.remaining == 0) return null;
        self.remaining -= 1;
        return self.remaining;
    }
};

comptime {
    vftrait.requires(Iterator, Counter);
}
```

`requires` emits a compile error containing the full diagnostic when `Counter`
does not satisfy `Iterator`. Use `satisfy` when a boolean result is needed.

## API

```zig
pub fn satisfy(comptime Trait: type, comptime Type: type, comptime report: ?*[]const u8) bool {...}
pub fn requires(comptime Trait: type, comptime Type: type) void {...}
```

`satisfy` returns whether `Type` satisfies `Trait`. When it returns `false` and
`report` is non-null, every mismatch is written through `report`. Since the
whole check is evaluated at compile time, `report` must point to a compile-time
variable:

```zig
comptime var diagnostic: []const u8 = "";
const ok = comptime vftrait.satisfy(Iterator, Counter, &diagnostic);
if (!ok) {
    @compileError(diagnostic);
}
```

When `report` is `null`, the result is still compile-time known and can be used
in an ordinary expression.

## Matching rules

Let `Trait` be the template type and `Type` the type being checked.

1. `Trait` must be a `struct`.
2. Every public declaration of `Trait` must have a corresponding public
   declaration in `Type`.
3. Self references in `Trait` are resolved against `Type`. If a `Trait`
   declaration refers to `Trait` itself or to another declaration of `Trait`,
   the matching declaration in `Type` must refer to `Type`'s own declaration,
   not to `Trait`'s.
4. Declarations are classified into four kinds:

### Associated constants

Both declarations must have the same name and isomorphic types. The values are
not compared. Types that refer to other declarations are resolved as described
above.

```zig
const Trait = struct {
    pub const count: usize = undefined;
};
```

### Associated types

Both declarations must have the same name, and both values must be types.

- If the value in `Trait` is `type`, any type is accepted:

  ```zig
  pub const Item = type;
  ```

- If the value in `Trait` is a `struct`, it is treated as a nested trait and
  checked recursively with the same rules.
- Other values are compared structurally. Error sets are intentionally exempt:
  any error set is compatible with any other error set. Opaque types only need
  to both be opaque.

### Associated functions

Both declarations must have the same name, and all parameter types and the
return type must be isomorphic. Generic parameters (`anytype`, parameter types
that depend on another parameter, and generic return types) must match as
generic.

### Methods

Methods follow the same rules as associated functions, with the first
parameter treated as `self`. `Self`, `*Self`, and `*const Self` in `Trait`
correspond to `Type`'s own self forms.

As a special case, `*anyopaque` is treated as a type-erased self parameter and
is compatible with `*Self` and `*const Self`:

```zig
const Trait = struct {
    pub fn deinit(self: *anyopaque) void {
        _ = self;
    }
};

const Impl = struct {
    pub fn deinit(self: *@This()) void {
        _ = self;
    }
};
```

Method detection is based on the type of the first parameter, not its name.

## Diagnostics

All mismatches are collected in a single report, and expected types are derived
from `Type`'s own declarations, so self references are shown after substitution:

```text
Type 'app.Counter' does not satisfy Trait 'app.Iterator':
  - associated type 'Item': expected type 'u32', found 'u64'
  - method 'next': return type expected '?u32', found '?u64'
```

## Notes

- Everything is checked at compile time; there is no runtime cost.
- Private declarations of `Trait` are ignored.
- `Type` may have additional declarations beyond those required by `Trait`.
- A method's first parameter must be compatible with `Trait` itself (or be
  `*anyopaque`). Other functions are treated as associated functions.
- If a trait declares multiple `pub const X = type;` placeholders, occurrences
  of `type` inside a single signature cannot be distinguished by reflection;
  avoid relying on more than one such placeholder in the same signature.

## License

MIT. See [LICENSE](LICENSE).
