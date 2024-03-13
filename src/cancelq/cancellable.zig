const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("smeartime.h");
});

const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const c_allocator = std.heap.c_allocator;

const HEAP_CHECK = true;
comptime {
    if (builtin.single_threaded) {
        @compileError("Cancellable queue must run multi-threaded.");
    }
    if (!std.Thread.use_pthreads) {
        @compileError("Tests depend on pthreads.");
    }
}

/// I know it's a faux pas in some C circles to typedef a pointer, and
/// I'd rather avoid it here, but the alternative is to stick the
/// alignment info everywhere the pointer type is used. This seems
/// less bad.
pub const event_queue_ptr_t = ?*align(@alignOf(EventQueue)) opaque {};
pub const cancellable_id_t = isize;

pub const NOT_CANCELLABLE: cancellable_id_t = -1;
pub const SCHEDULE_FAIL: cancellable_id_t = -2;

const Event = ?*const opaque {};

const Element = struct {
    event: Event,
    id: cancellable_id_t,
    delivery_time: c.abs_time_t,
};
const Heap = std.PriorityQueue(Element, void, cmp);

const IdState = enum {
    UNUSED,
    DELIVERED,
    WAITING,
};

const IdArray = ArrayList(IdState);

// While event_queue_ptr_t is a pointer to this, nobody but this module
// should be able to mess with these, so they don't need to be C ABI
// compatible.
pub const EventQueue = struct {
    heap: Heap,
    // Array of IDs for cancellation. A given ID is an index into this
    // array.
    ids: IdArray,

    lock: Mutex,
    is_empty: Condition,

    /// Return a new event queue that will schedule and deliver events
    /// with the eq functions below.
    pub fn new(allocator: Allocator) !*EventQueue {
        const q = try allocator.create(EventQueue);

        q.heap = Heap.init(allocator, {});
        q.ids = IdArray.init(allocator);
        q.lock = .{};
        q.is_empty = .{};
        return q;
    }

    /// Free an empty event queue. Fail (and return false) if the queue is
    /// not empty. If you want deallocation to never fail, make sure you
    /// empty the queue before calling this.
    pub fn free(queue: *EventQueue, allocator: Allocator) bool {
        queue.lock.lock();
        errdefer queue.lock.unlock();
        if (!queue.emptyLH()) {
            return false;
        }
        queue.heap.deinit();
        queue.ids.deinit();
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
        try q.ids.append(.WAITING);
        return q.ids.items.len - 1;
    }

    fn check(q: *EventQueue) bool {
        _ = q;
        return true;
    }

    /// Schedule a cancellable event to be delivered at the appointed
    /// time. Returns an ID that can be used to cancel the event. The ID
    /// is a limited resource that should be released when it's no longer
    /// needed by calling cancel, cancel_or_release, or release.
    pub fn schedule(
        q: *EventQueue,
        event: Event,
        time: c.abs_time_t,
    ) !usize {
        q.lock.lock();
        defer q.lock.unlock();

        const id = try q.newId();
        const element = Element{
            .event = event,
            .id = @intCast(id),
            .delivery_time = time,
        };

        try q.heap.add(element);

        if (HEAP_CHECK)
            std.debug.assert(q.check());
        return id;
    }

    /// Post an uncancellable event to the queue, to be delivered at time.
    pub fn post(q: *EventQueue, ev: Event, time: c.abs_time_t) !void {
        q.lock.lock();
        defer q.lock.unlock();

        const element = Element{
            .event = ev,
            .id = NOT_CANCELLABLE,
            .delivery_time = time,
        };

        try q.heap.add(element);
        if (HEAP_CHECK)
            std.debug.assert(q.check());
    }
    /// Remove the next scheduled event for the provided time from the
    /// queue and return it. Returns null if nothing's due.
    pub fn nextEvent(queue: *EventQueue, time: c.abs_time_t) Event {
        queue.lock.lock();
        defer queue.lock.unlock();
        defer if (queue.emptyLH()) queue.is_empty.broadcast();

        const next = queue.heap.peek() orelse return null;
        if (c.time_compare(next.delivery_time, time) > 0)
            return null;
        if (next.id != NOT_CANCELLABLE) {
            std.debug.assert(queue.ids.items[@intCast(next.id)] == .WAITING);
            queue.ids.items[@intCast(next.id)] = .DELIVERED;
        }
        const element = queue.heap.remove();
        return element.event;
    }

    /// Return whether or not the queue has outstanding events.
    pub fn empty(queue: *EventQueue) bool {
        queue.lock.lock();
        defer queue.lock.unlock();
        return queue.emptyLH();
    }

    /// Return the cancelled event.
    fn cancelLH(queue: *EventQueue, id: usize) CancelError!Event {
        if (queue.ids.items.len <= id)
            return CancelError.NoSuchId;

        switch (queue.ids.items[id]) {
            .UNUSED => return CancelError.NoSuchId,
            .DELIVERED => return CancelError.AlreadyRun,
            .WAITING => {},
        }

        var iterator = queue.heap.iterator();
        var idx: usize = 0;
        while (iterator.next()) |elem| : (idx += 1) {
            if (elem.id == id) {
                queue.ids.items[id] = .UNUSED;
                const element = queue.heap.removeIndex(idx);
                return element.event;
            }
        }
        return CancelError.NoSuchId;
    }

    /// Always returns null on success, so it can be used in switches
    /// with cancel.
    fn releaseLH(queue: *EventQueue, id: usize) CancelError!Event {
        if (queue.ids.items.len <= id)
            return CancelError.NoSuchId;

        switch (queue.ids.items[id]) {
            .UNUSED => return CancelError.NoSuchId,
            .WAITING => return CancelError.NotRun,
            .DELIVERED => {},
        }

        queue.ids.items[id] = .UNUSED;
        return null;
    }

    /// Cancel the given ID. Fails if the event has already been run. On
    /// success, returns the cancelled event so that it can be
    /// freed. Releases the ID on success.
    pub fn qCancel(queue: *EventQueue, id: usize) CancelError!Event {
        queue.lock.lock();
        defer queue.lock.unlock();

        return queue.cancelLH(id);
    }

    /// Cancel the given event ID if it's still in the
    /// queue. Otherwise release the resources associated with
    /// it. This does not fail if the event has run already. On
    /// success, e is set to the value held in the cancelled event so
    /// that it can be freed, or NULL if it's already been delivered.
    pub fn cancelOrRelease(
        queue: *EventQueue,
        id: usize,
    ) CancelError!Event {
        queue.lock.lock();
        defer queue.lock.unlock();

        if (queue.ids.items.len <= id) {
            return CancelError.NoSuchId;
        }

        return switch (queue.ids.items[id]) {
            .UNUSED => CancelError.NoSuchId,
            .WAITING => queue.cancelLH(id),
            .DELIVERED => queue.releaseLH(id),
        };
    }

    /// Return when the event queue is empty.
    pub fn waitEmpty(queue: *EventQueue) void {
        queue.lock.lock();
        defer queue.lock.unlock();
        while (!queue.emptyLH()) {
            queue.is_empty.wait(&queue.lock);
        }
    }

    /// Release the resources associated with a cancellable event. Fails
    /// if the event has not already been run.
    pub fn release(queue: *EventQueue, id: usize) CancelError!Event {
        queue.lock.lock();
        defer queue.lock.unlock();

        return queue.releaseLH(id);
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

export fn eq_new() event_queue_ptr_t {
    const result = EventQueue.new(c_allocator) catch null;
    return @ptrCast(result);
}

export fn eq_free(queue: event_queue_ptr_t) bool {
    const q: *EventQueue = @ptrCast(queue orelse return false);
    return q.free(c_allocator);
}

export fn eq_schedule(
    queue: event_queue_ptr_t,
    event: ?*const anyopaque,
    time: c.abs_time_t,
) cancellable_id_t {
    const q: *EventQueue = @ptrCast(queue orelse return SCHEDULE_FAIL);
    const result = q.schedule(@ptrCast(event), time) catch return SCHEDULE_FAIL;
    return @intCast(result);
}

export fn eq_post(
    queue: event_queue_ptr_t,
    event: Event,
    time: c.abs_time_t,
) bool {
    const q: *EventQueue = @ptrCast(queue orelse return false);
    q.post(event, time) catch return false;
    return true;
}

export fn eq_next_event(
    queue: event_queue_ptr_t,
    time: c.abs_time_t,
) ?*const anyopaque {
    const q: *EventQueue = @ptrCast(queue orelse return null);
    return @ptrCast(q.nextEvent(time));
}

export fn eq_empty(queue: event_queue_ptr_t) bool {
    const q: *EventQueue = @ptrCast(queue orelse return false);
    return q.empty();
}

export fn eq_cancel(
    queue: event_queue_ptr_t,
    id: cancellable_id_t,
    event: ?*Event,
) cancellation_status_t {
    const q: *EventQueue = @ptrCast(queue orelse return .FAIL_NO_SUCH_ID);
    const e: *Event = @ptrCast(event orelse return .FAIL_NO_SUCH_ID);
    e.* = null;
    e.* = q.qCancel(@intCast(id)) catch |err| {
        return switch (err) {
            error.NoSuchId => .FAIL_NO_SUCH_ID,
            error.AlreadyCancelled => .FAIL_ALREADY_CANCELLED,
            error.AlreadyRun => .FAIL_ALREADY_RUN,
            error.NotRun => .FAIL_NOT_RUN,
            error.Locking => .FAIL_LOCKING,
        };
    };
    return .SUCCESS;
}

export fn eq_cancel_or_release(
    queue: event_queue_ptr_t,
    id: cancellable_id_t,
    event: ?*Event,
) cancellation_status_t {
    const q: *EventQueue = @ptrCast(queue orelse return .FAIL_NO_SUCH_ID);
    const e: *Event = @ptrCast(event orelse return .FAIL_NO_SUCH_ID);
    e.* = null;
    e.* = q.cancelOrRelease(@intCast(id)) catch |err| {
        return switch (err) {
            error.NoSuchId => .FAIL_NO_SUCH_ID,
            error.AlreadyCancelled => .FAIL_ALREADY_CANCELLED,
            error.AlreadyRun => .FAIL_ALREADY_RUN,
            error.NotRun => .FAIL_NOT_RUN,
            error.Locking => .FAIL_LOCKING,
        };
    };
    return .SUCCESS;
}

export fn eq_release(
    queue: event_queue_ptr_t,
    id: cancellable_id_t,
) cancellation_status_t {
    const q: *EventQueue = @ptrCast(queue orelse return .FAIL_NO_SUCH_ID);
    _ = q.release(@intCast(id)) catch |err| {
        return switch (err) {
            error.NoSuchId => .FAIL_NO_SUCH_ID,
            error.AlreadyCancelled => .FAIL_ALREADY_CANCELLED,
            error.AlreadyRun => .FAIL_ALREADY_RUN,
            error.NotRun => .FAIL_NOT_RUN,
            error.Locking => .FAIL_LOCKING,
        };
    };
    return .SUCCESS;
}

/// Check that the internal data structure is consistent. There should
/// be nothing you can do to make this return anything but true.
export fn eq_validate(queue: event_queue_ptr_t) bool {
    const q: *EventQueue = @ptrCast(queue orelse return false);
    return q.check();
}

export fn eq_wait_empty(queue: event_queue_ptr_t) void {
    const q: *EventQueue = @ptrCast(queue orelse unreachable);
    return q.waitEmpty();
}

/// Compare events to make this a minheap with respect to delivery
/// time.
fn cmp(ctxt: void, a: Element, b: Element) std.math.Order {
    _ = ctxt;
    return std.math.order(a.delivery_time, b.delivery_time);
}
