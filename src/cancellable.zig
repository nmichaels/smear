const std = @import("std");
const builtin = @import("builtin");
const smeartime = @import("smeartime");

const Io = std.Io;
const Mutex = Io.Mutex;
const Condition = Io.Condition;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const c_allocator = std.heap.c_allocator;

const HEAP_CHECK = false;
comptime {
    if (builtin.single_threaded) {
        @compileError("Cancellable queue must run multi-threaded.");
    }
    if (!std.Thread.use_pthreads) {
        @compileError("Tests depend on pthreads.");
    }
}

pub const cancellable_id_t = isize;

pub const NOT_CANCELLABLE: cancellable_id_t = -1;
pub const SCHEDULE_FAIL: cancellable_id_t = -2;

const Event = ?*const opaque {};

const Element = struct {
    event: Event,
    id: cancellable_id_t,
    delivery_time: smeartime.abs_time_t,
};
const Heap = std.PriorityQueue(Element, void, cmp);

const IdState = enum {
    UNUSED,
    DELIVERED,
    WAITING,
};

const IdArray = ArrayList(IdState);

pub const EventQueue = struct {
    heap: Heap,
    // Array of IDs for cancellation. A given ID is an index into this
    // array.
    ids: IdArray,

    lock: Mutex,
    is_empty: Condition,
    emptied: bool,
    allocator: Allocator,
    io: Io,

    /// Return a new event queue that will schedule and deliver events
    /// with the eq functions below.
    pub fn new(allocator: Allocator, io: Io) !*EventQueue {
        const q = try allocator.create(EventQueue);

        q.heap = .empty;
        q.ids = .empty;
        q.lock = .init;
        q.is_empty = .init;
        q.emptied = true;
        q.allocator = allocator;
        q.io = io;
        return q;
    }

    /// Free an empty event queue. Fail (and return false) if the queue is
    /// not empty. If you want deallocation to never fail, make sure you
    /// empty the queue before calling this.
    pub fn free(queue: *EventQueue) bool {
        const allocator = queue.allocator;
        Io.Threaded.mutexLock(&queue.lock);
        errdefer Io.Threaded.mutexUnlock(&queue.lock);
        if (!queue.emptyLH()) {
            return false;
        }
        queue.heap.deinit(allocator);
        queue.ids.deinit(allocator);
        allocator.destroy(queue);
        return true;
    }

    fn emptyLH(queue: *EventQueue) bool {
        return queue.heap.count() == 0;
    }

    fn newId(q: *EventQueue) !usize {
        for (q.ids.items, 0..) |*id, idx| {
            if (id.* == .UNUSED) {
                id.* = .WAITING;
                return idx;
            }
        }
        try q.ids.append(q.allocator, .WAITING);
        return q.ids.items.len - 1;
    }

    fn check(q: *EventQueue) !void {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);

        // Make sure no two items in the heap have the same
        // cancellation ID (unless it's NOT_CANCELLABLE)

        var seen: []bool = try q.allocator.alloc(bool, q.ids.items.len);
        defer q.allocator.free(seen);
        for (seen) |*v| {
            v.* = false;
        }

        var elements = q.heap.iterator();
        while (elements.next()) |element| {
            if (element.id >= 0) {
                const id: usize = @intCast(element.id);
                if (seen[id])
                    return error.DuplicatedCancellationId;
                seen[id] = true;
            }
        }

        for (q.ids.items, 0..) |id, idx| {
            if (id != .WAITING)
                continue;
            if (!seen[idx])
                return error.BadCancellationId;
        }
    }

    /// Schedule a cancellable event to be delivered at the appointed
    /// time. Returns an ID that can be used to cancel the event. The ID
    /// is a limited resource that should be released when it's no longer
    /// needed by calling cancel, cancel_or_release, or release.
    pub fn schedule(
        q: *EventQueue,
        event: Event,
        time: smeartime.abs_time_t,
    ) !usize {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);

        const id = try q.newId();
        const element = Element{
            .event = event,
            .id = @intCast(id),
            .delivery_time = time,
        };

        try q.heap.push(q.allocator, element);
        q.emptied = false;

        if (HEAP_CHECK)
            std.debug.assert(q.check());
        return id;
    }

    /// Post an uncancellable event to the queue, to be delivered at time.
    pub fn post(q: *EventQueue, ev: Event, time: smeartime.abs_time_t) !void {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);

        const element = Element{
            .event = ev,
            .id = NOT_CANCELLABLE,
            .delivery_time = time,
        };

        q.emptied = false;
        try q.heap.push(q.allocator, element);
        if (HEAP_CHECK)
            std.debug.assert(q.check());
    }

    fn markEmpty(q: *EventQueue) void {
        q.emptied = true;
        q.is_empty.broadcast(q.io);
    }

    /// Call this after handling or cancelling an event.
    pub fn checkEmpty(q: *EventQueue) void {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);
        if (q.emptyLH()) q.markEmpty();
    }

    /// Remove the next scheduled event for the provided time from the
    /// queue and return it. Returns null if nothing's due.
    pub fn nextEvent(q: *EventQueue, time: smeartime.abs_time_t) Event {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);

        const next = q.heap.peek() orelse return null;
        if (smeartime.time_compare(next.delivery_time, time) > 0)
            return null;
        if (next.id != NOT_CANCELLABLE) {
            std.debug.assert(q.ids.items[@intCast(next.id)] == .WAITING);
            q.ids.items[@intCast(next.id)] = .DELIVERED;
        }
        const element = q.heap.pop().?;
        return element.event;
    }

    /// Return whether or not the queue has outstanding events.
    pub fn empty(q: *EventQueue) bool {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);
        return q.emptyLH();
    }

    /// Return the cancelled event.
    fn cancelLH(q: *EventQueue, id: usize) CancelError!Event {
        if (q.ids.items.len <= id)
            return CancelError.NoSuchId;

        switch (q.ids.items[id]) {
            .UNUSED => return CancelError.NoSuchId,
            .DELIVERED => return CancelError.AlreadyRun,
            .WAITING => {},
        }

        var iterator = q.heap.iterator();
        var idx: usize = 0;
        while (iterator.next()) |elem| : (idx += 1) {
            if (elem.id == id) {
                q.ids.items[id] = .UNUSED;
                const element = q.heap.popIndex(idx);
                return element.event;
            }
        }
        return CancelError.NoSuchId;
    }

    /// Always returns null on success, so it can be used in switches
    /// with cancel.
    fn releaseLH(q: *EventQueue, id: usize) CancelError!Event {
        if (q.ids.items.len <= id)
            return CancelError.NoSuchId;

        switch (q.ids.items[id]) {
            .UNUSED => return CancelError.NoSuchId,
            .WAITING => return CancelError.NotRun,
            .DELIVERED => {},
        }

        q.ids.items[id] = .UNUSED;
        return null;
    }

    /// Cancel the given ID. Fails if the event has already been run. On
    /// success, returns the cancelled event so that it can be
    /// freed. Releases the ID on success.
    pub fn cancel(q: *EventQueue, id: usize) CancelError!Event {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);
        defer if (q.emptyLH()) q.markEmpty();
        return q.cancelLH(id);
    }

    /// Cancel the given event ID if it's still in the
    /// queue. Otherwise release the resources associated with
    /// it. This does not fail if the event has run already. On
    /// success, e is set to the value held in the cancelled event so
    /// that it can be freed, or NULL if it's already been delivered.
    pub fn cancelOrRelease(
        q: *EventQueue,
        id: usize,
    ) CancelError!Event {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);

        if (q.ids.items.len <= id) {
            return CancelError.NoSuchId;
        }

        return switch (q.ids.items[id]) {
            .UNUSED => CancelError.NoSuchId,
            .WAITING => q.cancelLH(id),
            .DELIVERED => q.releaseLH(id),
        };
    }

    /// Return when the event queue is empty.
    pub fn waitEmpty(q: *EventQueue) void {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);
        while (!q.emptied or !q.emptyLH()) {
            q.is_empty.waitUncancelable(q.io, &q.lock);
        }
    }

    /// Release the resources associated with a cancellable event. Fails
    /// if the event has not already been run.
    pub fn release(q: *EventQueue, id: usize) CancelError!void {
        Io.Threaded.mutexLock(&q.lock);
        defer Io.Threaded.mutexUnlock(&q.lock);

        _ = try q.releaseLH(id);
    }
};

pub const cancellation_status_t = enum(c_int) {
    SUCCESS = 0,
    FAIL_NO_SUCH_ID,
    FAIL_ALREADY_CANCELLED,
    FAIL_ALREADY_RUN,
    FAIL_NOT_RUN,
    FAIL_LOCKING,
};

pub const CancelError = error{
    NoSuchId,
    AlreadyCancelled,
    AlreadyRun,
    NotRun,
    Locking,
};

/// Compare events to make this a minheap with respect to delivery
/// time.
fn cmp(ctxt: void, a: Element, b: Element) std.math.Order {
    _ = ctxt;
    return std.math.order(a.delivery_time, b.delivery_time);
}

const testing = std.testing;
test "fill-then-cancel" {
    const COUNT = 32;
    var q = try EventQueue.new(testing.allocator, testing.io);
    var ids: [COUNT]usize = undefined;

    try testing.expect(q.empty());
    try q.check();

    // First, fill the queue with events.
    for (&ids, 0..) |*id, num| {
        const ev: Event = @ptrFromInt(num);
        id.* = try q.schedule(ev, @intCast(num * 2));
        try q.check();
        try testing.expect(id.* >= 0);
        try testing.expectError(CancelError.NotRun, q.release(id.*));
        try q.check();
    }

    try q.check();

    var reversed = std.mem.reverseIterator(&ids);
    var idx: usize = COUNT;
    // Then cancel all the events.
    while (reversed.next()) |id| : (idx -= 1) {
        const expected: Event = @ptrFromInt(idx - 1);
        try testing.expect(!q.empty());

        if (idx & 1 != 0) {
            const e = try q.cancel(id);
            try q.check();
            try testing.expectEqual(expected, e);
            // Odd ones get cancelOrRelease'd
            const no_such_id = q.cancelOrRelease(id);
            try testing.expectError(CancelError.NoSuchId, no_such_id);
            try q.check();
        } else {
            const e = try q.cancelOrRelease(id);
            try q.check();
            try testing.expectEqual(expected, e);
            // Evens just get cancel'd
            const no_such_id = q.cancel(id);
            try testing.expectError(CancelError.NoSuchId, no_such_id);
            try q.check();
        }
    }

    try q.check();
    try testing.expect(q.empty());
    try testing.expectEqual(q.nextEvent(0), null);
    try testing.expect(q.free());
}

test "fill-then-drain-all" {
    // Fill the queue with events, last to first.
    const COUNT = 32;
    var q = try EventQueue.new(testing.allocator, testing.io);
    var cancelIds: [COUNT]usize = undefined;

    for (1..COUNT + 1) |idx| {
        const i: usize = COUNT - idx;
        const ev: Event = @ptrFromInt(i);
        const id = try q.schedule(ev, @intCast(i * 2));
        cancelIds[i] = id;

        try testing.expect(!q.empty());
        try testing.expectError(CancelError.NotRun, q.release(id));
        try q.check();
    }

    for (0..COUNT) |i| {
        // One of these is 0, which translates to null, so we can't
        // `.?` the result. Maybe passing a null pointer in the test
        // is a bad idea.
        const e = q.nextEvent(1000);
        const expected: Event = @ptrFromInt(i);
        try testing.expectEqual(expected, e);
        const already_run = q.cancel(cancelIds[i]);
        try testing.expectError(CancelError.AlreadyRun, already_run);
        try q.release(cancelIds[i]);
    }

    try testing.expectEqual(null, q.nextEvent(1000));

    try testing.expect(q.empty());
    try q.check();

    try testing.expect(q.free());
}

const THREAD_TEST_COUNT = 3200;
/// Schedule a bunch of events with even numbers.
fn insert1(q: *EventQueue) ![]cancellable_id_t {
    // Half of these will be empty. That's ok.
    var ids = try testing.allocator.alloc(
        cancellable_id_t,
        THREAD_TEST_COUNT,
    );
    for (ids) |*id| {
        id.* = NOT_CANCELLABLE;
    }

    // Start at 2 because if i == 0, then the event will be NULL and
    // it will cause an infinite loop later...
    var i: usize = 2;
    while (i < THREAD_TEST_COUNT) : (i += 2) {
        const ev: Event = @ptrFromInt(i);
        ids[i] = @intCast(try q.schedule(ev, @intCast(i)));
        try testing.expect(ids[i] > NOT_CANCELLABLE);
    }

    return ids;
}

/// Schedule a bunch of events with odd numbers.
fn insert2(q: *EventQueue) ![]cancellable_id_t {
    var ids = try testing.allocator.alloc(
        cancellable_id_t,
        THREAD_TEST_COUNT,
    );
    for (ids) |*id| {
        id.* = NOT_CANCELLABLE;
    }

    var i: usize = 1;
    while (i < THREAD_TEST_COUNT) : (i += 2) {
        const ev: Event = @ptrFromInt(i);
        ids[i] = @intCast(try q.schedule(ev, @intCast(i)));
        try testing.expect(ids[i] > NOT_CANCELLABLE);
    }

    return ids;
}

fn releaseIds(q: *EventQueue, ids: []cancellable_id_t) !void {
    for (ids) |id| {
        if (id == NOT_CANCELLABLE)
            continue;
        try testing.expect(id > NOT_CANCELLABLE);
        try q.release(@intCast(id));
    }
}

test "threads" {
    const io = testing.io;
    // Make Q
    var q = try EventQueue.new(testing.allocator, io);

    // These two threads fill the queue with THREAD_TEST_COUNT (a
    // large number) events.
    var in1 = try Io.concurrent(io, insert1, .{q});
    var in2 = try Io.concurrent(io, insert2, .{q});

    while (q.empty()) {
        // Give time for the other threads to start before creating
        // the waiter.
    }
    var waiter = try Io.concurrent(io, EventQueue.waitEmpty, .{q});

    // Now start popping events off.
    for (1..THREAD_TEST_COUNT) |i| {
        const expected: Event = @ptrFromInt(i);
        while (q.empty()) {
            // this would be a good place to yield
        }
        try q.check();
        const e = result: while (true) {
            // The first event is not necessarily at time i, since
            // it's possible the odd thread put events in the queue
            // and we're waiting for an even one.
            if (q.nextEvent(i)) |ev| break :result ev;
            // If there were a way to yield, it would go here.
        };
        try testing.expectEqual(expected, e);
    }
    q.checkEmpty();

    // The queue should be empty.
    waiter.await(io);

    var ids: []cancellable_id_t = undefined;
    ids = try in1.await(io);
    try releaseIds(q, ids);
    testing.allocator.free(ids);
    ids = try in2.await(io);
    try releaseIds(q, ids);
    testing.allocator.free(ids);

    try testing.expect(q.free());
}

test "cancel-some-drain-some" {
    const COUNT = 32;
    var q = try EventQueue.new(testing.allocator, testing.io);
    var cancelIds: [COUNT]usize = undefined;

    for (1..COUNT + 1) |idx| {
        const i: usize = COUNT - idx;
        const ev: Event = @ptrFromInt(i);
        const id = try q.schedule(ev, @intCast(i * 2));
        cancelIds[i] = id;
        try testing.expect(!q.empty());
    }
    try q.check();

    for (0..COUNT) |idx| {
        const expected: Event = @ptrFromInt(idx);
        const id = cancelIds[idx];

        if ((id & 1) == 0) {
            try testing.expect(!q.empty());
            const e = q.nextEvent(1000);
            try testing.expectEqual(expected, e);
            try testing.expectError(CancelError.AlreadyRun, q.cancel(id));
            try q.release(id);
        } else {
            try testing.expect(!q.empty());
            const e = try q.cancel(id);
            try testing.expectEqual(expected, e);
            try testing.expectError(CancelError.NoSuchId, q.cancel(id));
            try testing.expectError(
                CancelError.NoSuchId,
                q.cancelOrRelease(id),
            );
        }
    }
    try q.check();
    try testing.expect(q.empty());
    try testing.expect(q.free());
}

test "not-cancellable" {
    var q = try EventQueue.new(testing.allocator, testing.io);
    try testing.expect(q.empty());
    try q.check();
    for (0..0x1000) |i| {
        const e: Event = @ptrFromInt(i);
        try q.post(e, i);
    }
    try q.check();
    for (0..0x1000) |i| {
        const expected: Event = @ptrFromInt(i);
        const e = q.nextEvent(0xffffffff);
        try testing.expectEqual(expected, e);
    }
    try testing.expect(q.empty());
    try q.check();
    try testing.expect(q.free());
}
