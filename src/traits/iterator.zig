const trait = @import("../root.zig");

/// Trait for iterators.
pub const Iterable = struct {
    pub const Item = type;

    pub fn next(self: *Iterator) ?Item {
        _ = self;
        @compileError("Not an available implementation.");
    }
};

/// `MapIterator` is an iterator that applies a function `f` to each item in `iter`.
pub fn MapIterator(comptime T: type, comptime R: type) type {
    return struct {
        const Self = @This();
        const Item = R;

        f: fn (T.Item) R,
        iter: T,

        fn next(self: *Self) ?Item {
            if (self.iter.next()) |item| {
                return self.f(item);
            }
            return null;
        }
    };
}

/// `FilterIterator` is an iterator that filters items in `iter` using a predicate `f`.
pub fn FilterIterator(comptime T: type) type {
    return struct {
        const Self = @This();
        const Item = T.Item;

        f: fn (Item) bool,
        iter: T,

        fn next(self: *Self) ?Item {
            while (self.iter.next()) |item| {
                if (self.f(item)) {
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
        pub fn foreach(self: *Self, f: fn (Item) void) void {
            while (self.next()) |item| {
                f(item);
            }
        }

        /// Maps each item in the iterator to a new value using `f`.
        pub fn map(self: *Self, comptime R: type, f: fn (Item) R) Iterator(MapIterator(Self, R)) {
            const Map = MapIterator(Self, R);
            const map_iter = Map{
                .f = f,
                .iter = self,
            };
            return .from(map_iter);
        }

        /// Filters items in the iterator using `f`.
        pub fn filter(self: *Self, f: fn (Item) bool) Iterator(FilterIterator(Self)) {
            const Filter = FilterIterator(Self);
            const filter_iter = Filter{
                .f = f,
                .iter = self,
            };
            return .from(filter_iter);
        }
    };
}
