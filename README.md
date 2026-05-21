# vftrait

A library for duck type checking during compilation. It provides the `satisfyTrait` function to verify at compile time whether a type satisfies the contract defined by a trait. 

Similar concepts in other languages:
| **Language** | **Concept** | **Keyword** |
|---|---|---|
| Rust | Trait | `trait` / `impl` |
| C++ | Concept | `concept` / `requires` |
| Haskell | Typeclass | `class` / `instance` |
| Swift | Protocol | `protocol` |
| Go | Interface (structural) | `interface` |
| Java | Interface (nominal) | `interface` / `implements` |


## Installation

Run the following command to add vftrait to your project:

```sh
zig fetch --save git+https://github.com/Verafahn/vftrait#master
```

Then add the module in your `build.zig`:

```zig
const vftrait = b.dependency("vftrait", .{}).module("vftrait");
exe.root_module.addImport("vftrait", vftrait);
```

## Quick Start

Define a trait as a struct whose declarations describe the contract.  
Then call `satisfyTrait` to check whether a type implements the trait.

```zig
const vftrait = @import("vftrait");

// 1. Define the trait
const Printable = struct {
    pub fn format(self: *const @This(), writer: anytype) !void {
        _ = self;
        _ = writer;
    }
};

// 2. Implement the trait implicitly (no `impl` keyword required)
const Point = struct {
    x: f32,
    y: f32,

    pub fn format(self: *const @This(), writer: anytype) !void {
        try writer.print("Point({{.x = {d}, .y = {d}}})", .{ self.x, self.y });
    }
};

// 3. Check at compile time
comptime {
    if (!vftrait.satisfyTrait(Printable, Point)) {
        @compileError("Point must implement Printable");
    }
}
```

For example, a specific usage example:

```zig
const vftrait = @import("vftrait");
const std = @import("std");

pub const Drawable = struct {
    pub fn draw(self: *const @This()) void {
        _ = self;
    }
};

pub const Circle = struct {
    radius: f32,

    pub fn draw(self: *const @This()) void {
        std.debug.print("Circle(radius={})", .{self.radius});
    }
};

pub const Point = struct {
    x: f32,
    y: f32,

    pub fn draw(self: *const @This()) void {
        std.debug.print("Point(x={}, y={})", .{ self.x, self.y });
    }
};

pub fn draw(shape: anytype) void {
    vftrait.assertSatisfyTrait(Drawable, @TypeOf(shape));
    shape.draw();
    return;
}

pub fn main(init: std.process.Init) !void {
    _ = init;

    const circle = Circle{ .radius = 5.0 };
    draw(circle);
    const point = Point{ .x = 1.0, .y = 2.0 };
    draw(point);

    // draw(10); // Error: @TypeOf(10) does not satisfy Drawable
}
```

## Trait Contract Elements

The trait struct can contain four kinds of declarations:

| Category                | Zig Declaration                         | Example                                    |
| ----------------------- | --------------------------------------- | ------------------------------------------ |
| **Associated constant** | `pub const name: T = ...;`              | `pub const max_size: usize = 1024;`        |
| **Associated type**     | `pub const Name = some_type;`           | `pub const Item = struct {};`              |
| **Associated function** | `pub fn name(...) ... { }`              | `pub fn fromInt(n: i32) Self { }`          |
| **Method**              | `pub fn name(self: *Self, ...) ... { }` | `pub fn clone(self: *const Self) Self { }` |

## Matching Rules

- **Constants**: Must have exactly the same type.
- **Types**: Must be of the same kind (e.g., `struct` vs `struct`, `error` vs `error`).  
  Nested types are **not** recursively checked – only the top‑level kind is compared.
- **Functions and methods**: Must have the same calling convention and arity, and each parameter type and return type must be **isomorphic** (structurally equivalent) to the corresponding associated type in the trait.

## Special Feature: `anytype` with `type`

When an associated type in the trait is set to the built‑in `type`, that position accepts any type:

```zig
const vftrait = @import("vftrait");

const Trait = struct {
    pub const Value = type; // Accepts any type
    pub fn get(self: *const @This()) Value {
        _ = self;
    }
};

const IntHolder = struct {
    pub const Value = i32;
    pub fn get(self: *const @This()) i32 {
        _ = self;
        return 42;
    }
};

const StrHolder = struct {
    pub const Value = []const u8;
    pub fn get(self: *const @This()) []const u8 {
        _ = self;
        return "hi";
    }
};

comptime {
    @compileLog(vftrait.satisfyTrait(Trait, IntHolder)); // true
    @compileLog(vftrait.satisfyTrait(Trait, StrHolder)); // true
}
```

This also works for `u32`, `struct`, `union`, `error`, `enum`, pointers, optionals, and any other type.

## Requirements

- Zig ≥ 0.16.0

## License

MIT
