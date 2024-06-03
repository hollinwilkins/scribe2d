const std = @import("std");
const atomic = std.atomic;

pub fn Sequence(comptime T: type) type {
    return struct {
        const Self = @This();
        const Value = atomic.Value(T);

        next_value: Value,

        pub fn init() Self {
            return initValue(0);
        }

        pub fn initValue(value: T) Self {
            return Self{ .next_value = Value.init(value) };
        }

        pub fn setValue(self: *Self, value: T) void {
            self.next_value.store(value, .Release);
        }

        pub fn getValue(self: *const Self) T {
            return self.next_value.load(.Acquire);
        }

        pub fn next(self: *Self) T {
            return self.next_value.fetchAdd(1, .acq_rel);
        }
    };
}
