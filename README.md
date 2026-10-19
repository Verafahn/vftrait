# vftrait

这是一个用于检查鸭子类型的库。它提供了一个`satisfyTrait`函数，用于检查两个类型是否满足“形如”关系。

## 安装

运行下面这条命令以将它添加到你的项目中：

```sh
zig fetch --save git+https://github.com/Verafahn/vftrait#master
```

然后你就可以在你的项目中使用

```zig
const vftrait = b.dependency("vftrait", .{}).module("vftrait");
const vftrait_mod = vftrait.module("vftrait");

// 之后就像一个普通的依赖项使用
```

## “形如”关系

如果一个类型能够满足另一个鸭子类型约定，那么它们就被视为“形如”关系。举一个具体的例子：
```zig
pub const A = struct {
    pub fn func() void {}
};

pub const B = struct {
    pub fn func() void {}
};

pub const C = struct {
    pub fn func() void {}
    pub fn foo() void {}
};

pub const D = struct {
    pub fn foo() void {}
}
```
对于以上四个类型，`A`和`B`同构，也相当于互相“形如”；`C`形如`A`（或`B`），因为它的子集中包含与`A`（或`B`）同构的内容，`C`同时也形如`D`；`D`与`A`、`B`和`C`均不成“形如”或同构关系。

这些概念的引入是为了让鸭子类型相关的报错由被视为使用错误转变为类型错误，以改善错误的清晰度。

```zig
const std = @import("std");

pub const A = struct {
    pub fn func() void {
        std.debug.print("Called {s}", .{"A: func"});
    }
};

pub const B = struct {
    pub fn foo() void {
        std.debug.print("Called {s}", .{"B: foo"});
    }
};

pub const C = struct {
    pub fn func() void {
        std.debug.print("Called {s}", .{"C: func"});
    }
};

pub fn call(v: anytype) void {
    @TypeOf(v).func();
}

pub fn main() !void {
    call(B{});
}
```

```
a.zig:22:15: error: struct 'a.B' has no member named 'func'
    @TypeOf(v).func();
    ~~~~~~~~~~^~~~~
a.zig:9:15: note: struct declared here
pub const B = struct {
              ^~~~~~
referenced by:
```