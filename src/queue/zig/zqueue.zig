const std = @import("std");
const Mutex = std.Mutex;
const VoidList = std.ArrayList(*c_void);
const Allocator = std.mem.Allocator;

const Queue = struct {
    const Self = @This();
    list: VoidList,
    mutex: Mutex,
    allocator: *Allocator,

    pub fn new(allocator: *Allocator) ?*Self {
        var q: *Self = allocator.create(Self) catch return null;
        q.list = VoidList.init(allocator);
        q.allocator = allocator;
        q.mutex = Mutex.init();
        return q;
    }

    pub fn free(self: *Self) void {
        if (self.mutex.tryAcquire()) |held| {
            held.release();
        } else {
            unreachable; // Attempted to free queue while mutex held.
        }
        self.list.deinit();
        self.mutex.deinit();
        self.allocator.destroy(self);
    }

    pub fn enqueue(self: *Self, value: *c_void) bool {
        const held = self.mutex.acquire();
        defer held.release();
        self.list.append(value) catch return false;
        return true;
    }

    pub fn dequeue(self: *Self, value: **c_void) ?void {
        const held = self.mutex.acquire();
        defer held.release();
        if (self.list.len == 0) {
            return null;
        } else {
            value.* = self.list.orderedRemove(0);
        }
    }
};

const queue = @OpaqueType();

fn unpack(q: *queue) *Queue {
    return @ptrCast(*Queue, @alignCast(@alignOf(*Queue), q));
}

/// Return a new queue.
export fn newq() ?*queue {
    const allocator = std.heap.c_allocator; // Change for more targets!
    var q: *Queue = Queue.new(allocator) orelse return null;
    return @ptrCast(?*queue, q);
}

/// Free the queue.
export fn freeq(q: *queue) void  {
    var qq = unpack(q);
    qq.free();
}

/// Insert a new value into the queue, return true on success,
/// false on failure.
export fn enqueue(q: *queue, value: *c_void) bool {
    var qq = unpack(q);
    return qq.enqueue(value);
}

/// Pop an element off the queue. Return true on success, false on
/// failure.
export fn dequeue(q: *queue, value: **c_void) bool {
    var qq = unpack(q);
    _ = qq.dequeue(value) orelse return false;
    return true;
}

/// Return queue's length.
export fn size(q: *queue) usize {
    var qq = unpack(q);
    return qq.list.len;
}

/// Block until the queue is empty.
fn wait_empty(queue: *queue_t) void {
    // TODO: mutexes.
}

test "queue" {
    const testing = std.testing;

    var q = newq().?;
    var val: *c_void = undefined;
    testing.expect(enqueue(q, @intToPtr(*c_void, 0x1111111100000000))); // 1
    testing.expect(enqueue(q, @intToPtr(*c_void, 0x2222222211111111))); // 2
    testing.expect(dequeue(q, &val));                             // 1
    testing.expectEqual(val, @intToPtr(*c_void, 0x1111111100000000));
    testing.expect(enqueue(q, @intToPtr(*c_void, 0x3333333322222222))); // 2
    testing.expect(dequeue(q, &val));                             // 1
    testing.expectEqual(val, @intToPtr(*c_void, 0x2222222211111111));
    testing.expect(enqueue(q, @intToPtr(*c_void, 0x4444444433333333))); // 2
    testing.expect(enqueue(q, @intToPtr(*c_void, 0x5555555544444444))); // 3
    testing.expect(enqueue(q, @intToPtr(*c_void, 0x6666666655555555))); // 4
    testing.expect(enqueue(q, @intToPtr(*c_void, 0x7777777766666666))); // 5
    testing.expect(enqueue(q, @intToPtr(*c_void, 0x8888888877777777))); // 6
    testing.expect(enqueue(q, @intToPtr(*c_void, 0x9999999988888888))); // 7
    testing.expect(dequeue(q, &val)); // 6
    testing.expectEqual(val, @intToPtr(*c_void, 0x3333333322222222));
    testing.expect(dequeue(q, &val)); // 5
    testing.expectEqual(val, @intToPtr(*c_void, 0x4444444433333333));
    testing.expect(dequeue(q, &val)); // 4
    testing.expectEqual(val, @intToPtr(*c_void, 0x5555555544444444));
    testing.expect(dequeue(q, &val)); // 3
    testing.expectEqual(val, @intToPtr(*c_void, 0x6666666655555555));
    testing.expect(dequeue(q, &val)); // 2
    testing.expectEqual(val, @intToPtr(*c_void, 0x7777777766666666));
    testing.expect(dequeue(q, &val)); // 1
    testing.expectEqual(val, @intToPtr(*c_void, 0x8888888877777777));
    testing.expect(dequeue(q, &val)); // 0
    testing.expectEqual(val, @intToPtr(*c_void, 0x9999999988888888));
}
