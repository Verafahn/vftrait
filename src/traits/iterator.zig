const trait = @import("../root.zig");
const std = @import("std");

/// Trait for iterators.
pub const Iterable = struct {
    /// The type of items yielded by the iterator.
    pub const Item = type;

    /// Returns the next item from the iterator, or `null` if there are no more items.
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
pub fn MapIterator(comptime Iter: type, comptime R: type, comptime f: fn (Iter.Item) R) type {
    return struct {
        const Self = @This();
        pub const Item = R;

        iter: Iter,

        pub fn next(self: *Self) ?Item {
            if (self.iter.next()) |item| {
                return f(item);
            }
            return null;
        }
    };
}

/// `FilterIterator` is an iterator that filters items in `iter` using a predicate `f`.
pub fn FilterIterator(comptime Iter: type, comptime f: fn (Iter.Item) bool) type {
    return struct {
        const Self = @This();
        pub const Item = Iter.Item;

        iter: Iter,

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

/// `EnumerateIterator` is an iterator that enumerates items in `iter` with their index.
pub fn EnumerateIterator(comptime Iter: type) type {
    return struct {
        const Self = @This();
        pub const Item = struct {
            usize,
            Iter.Item,
        };

        count: usize = 0,
        iter: Iter,

        pub fn next(self: *Self) ?Item {
            if (self.iter.next()) |item| {
                const count = self.count;
                self.count += 1;
                return .{ count, item };
            }
            return null;
        }
    };
}

/// Returns the iterator type for a given iterable type `T`.
/// 
/// # Requirements
/// 
/// - `T` must satisfy the `Iterable` trait.
pub fn Iterator(comptime Iter: type) type {
    trait.assertSatisfyTrait(Iterable, Iter);

    return struct {
        const Self = @This();
        const Item = Iter.Item;

        fn next(self: *Self) ?Item {
            return self.iter.next();
        }

        iter: Iter,

        /// Creates an iterator from an iterable `iter`.
        pub fn from(iter: Iter) Self {
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
                .iter = self.*,
            };
            return .from(map_iter);
        }

        /// Filters items in the iterator using `f`.
        pub fn filter(self: *Self, comptime f: fn (Item) bool) Iterator(FilterIterator(Self, f)) {
            const Filter = FilterIterator(Self, f);
            const filter_iter = Filter{
                .iter = self.*,
            };
            return .from(filter_iter);
        }

        /// Folds the items in the iterator using `f` and an initial value `init`.
        pub fn fold(self: *Self, comptime R: type, init: R, comptime f: fn (R, Item) R) R {
            var result: R = init;
            while (self.next()) |item| {
                result = f(result, item);
            }
            return result;
        }

        pub fn enumerate(self: *Self) Iterator(EnumerateIterator(Self)) {
            const Enumerate = EnumerateIterator(Self);
            const enumerate_iter = Enumerate{
                .iter = self.*,
            };
            return .from(enumerate_iter);
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

test "fold" {
    const range_iter = range(usize, 0, 5, 1);
    var iter: Iterator(Range(usize)) = .from(range_iter);
    const result = iter.fold(usize, 0, struct {
        pub fn lambda(x: usize, y: usize) usize {
            return x + y;
        }
    }.lambda);
    try std.testing.expectEqual(10, result);
}

test "enumerate" {
    const range_iter = range(usize, 5, 10, 2);
    var iter: Iterator(Range(usize)) = .from(range_iter);
    var enumerate_iter = iter.enumerate();

    const index1, const value1 = enumerate_iter.next() orelse unreachable;
    try std.testing.expectEqual(0, index1);
    try std.testing.expectEqual(5, value1);
    const index2, const value2 = enumerate_iter.next() orelse unreachable;
    try std.testing.expectEqual(1, index2);
    try std.testing.expectEqual(7, value2);
    const index3, const value3 = enumerate_iter.next() orelse unreachable;
    try std.testing.expectEqual(2, index3);
    try std.testing.expectEqual(9, value3);
    const index4 = enumerate_iter.next();
    try std.testing.expectEqual(null, index4);
}
