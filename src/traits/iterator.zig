const trait = @import("../root.zig");
const std = @import("std");

/// Trait for iterators.
pub const Iterable = struct {
    pub const Item = type;

    pub fn next(self: *@This()) ?Item {
        _ = self;
        @compileError("Not an available implementation.");
    }
};

pub fn Range(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Item = T;

        start: T,
        end: T,
        step: T,

        pub fn next(self: *Self) ?Item {
            if (self.start >= self.end) return null;
            const result = self.start;
            self.start += self.step;
            return result;
        }
    };
}

/// `range` returns an iterator that yields a sequence of integers from `start` to `end` (exclusive).
pub fn range(comptime T: type, start: T, end: T, step: T) Range(T) {
    return .{ .start = start, .end = end, .step = step };
}

/// `MapIterator` is an iterator that applies a function `f` to each item in `iter`.
pub fn MapIterator(comptime T: type, comptime R: type, comptime f: fn (T.Item) R) type {
    return struct {
        const Self = @This();
        pub const Item = R;

        iter: *T,

        pub fn next(self: *Self) ?Item {
            if (self.iter.next()) |item| {
                return f(item);
            }
            return null;
        }
    };
}

/// `FilterIterator` is an iterator that filters items in `iter` using a predicate `f`.
pub fn FilterIterator(comptime T: type, comptime f: fn (T.Item) bool) type {
    return struct {
        const Self = @This();
        pub const Item = T.Item;

        iter: *T,

        pub fn next(self: *Self) ?Item {
            while (self.iter.next()) |item| {
                if (f(item)) {
                    return item;
                }
            }
            return null;
        }
    };
}

/// Returns the iterator type for a given iterable type `T`.
pub fn Iterator(comptime T: type) R: {
    trait.assertSatisfyTrait(Iterable, T);
    break :R type;
} {
    return struct {
        const Self = @This();
        const Item = T.Item;

        fn next(self: *Self) ?Item {
            return self.iter.next();
        }

        iter: T,

        /// Creates an iterator from an iterable `iter`.
        pub fn from(iter: T) Self {
            return .{ .iter = iter };
        }

        /// Iterates over the items in the iterator, calling `f` for each item.
        pub fn foreach(self: *Self, comptime f: fn (Item) void) void {
            while (self.next()) |item| {
                f(item);
            }
        }

        /// Maps each item in the iterator to a new value using `f`.
        pub fn map(self: *Self, comptime R: type, comptime f: fn (Item) R) Iterator(MapIterator(Self, R, f)) {
            const Map = MapIterator(Self, R, f);
            const map_iter = Map{
                .iter = self,
            };
            return .from(map_iter);
        }

        /// Filters items in the iterator using `f`.
        pub fn filter(self: *Self, comptime f: fn (Item) bool) Iterator(FilterIterator(Self, f)) {
            const Filter = FilterIterator(Self, f);
            const filter_iter = Filter{
                .iter = self,
            };
            return .from(filter_iter);
        }
    };
}

test "range" {
    var range_iter = range(usize, 0, 5, 1);

    try std.testing.expectEqual(0, range_iter.next() orelse unreachable);
    try std.testing.expectEqual(1, range_iter.next() orelse unreachable);
    try std.testing.expectEqual(2, range_iter.next() orelse unreachable);
    try std.testing.expectEqual(3, range_iter.next() orelse unreachable);
    try std.testing.expectEqual(4, range_iter.next() orelse unreachable);
    try std.testing.expectEqual(null, range_iter.next());
}

test "map" {
    const range_iter = range(usize, 0, 5, 1);
    var iter: Iterator(Range(usize)) = .from(range_iter);
    var map_iter = iter.map(usize, struct {
        pub fn lambda(x: usize) usize {
            return x * 2;
        }
    }.lambda);

    try std.testing.expectEqual(0, map_iter.next() orelse unreachable);
    try std.testing.expectEqual(2, map_iter.next() orelse unreachable);
    try std.testing.expectEqual(4, map_iter.next() orelse unreachable);
    try std.testing.expectEqual(6, map_iter.next() orelse unreachable);
    try std.testing.expectEqual(8, map_iter.next() orelse unreachable);
    try std.testing.expectEqual(null, map_iter.next());
}

test "filter" {
    const range_iter = range(usize, 0, 5, 1);
    var iter: Iterator(Range(usize)) = .from(range_iter);
    var filter_iter = iter.filter(struct {
        pub fn lambda(x: usize) bool {
            return x % 2 == 0;
        }
    }.lambda);

    try std.testing.expectEqual(0, filter_iter.next() orelse unreachable);
    try std.testing.expectEqual(2, filter_iter.next() orelse unreachable);
    try std.testing.expectEqual(4, filter_iter.next() orelse unreachable);
    try std.testing.expectEqual(null, filter_iter.next());
}