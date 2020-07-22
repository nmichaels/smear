const std = @import("std");
const assert = std.debug.assert;
const Mutex = std.Mutex;
const Allocator = std.mem.Allocator;
const PriorityQueue = std.PriorityQueue;
const ArrayList = std.ArrayList;
const ResetEvent = std.ResetEvent;
const c = @cImport({
    @cInclude("smeartime.h");
    @cInclude("cancellable.h");
});

const NOT_CANCELLABLE = @as(c.cancellable_id_t, -1);
const SCHEDULE_FAIL = @as(c.cancellable_id_t, -2);

const abs_time_t = c.abs_time_t;
const cancellable_id_t = c.cancellable_id_t;
const cancellation_status_t = c.cancellation_status_t;

const CancelError = error{
    NoSuchId,
    AlreadyCancelled,
    AlreadyRun,
    NotRun,
    Locking,
};

const id_state_t = enum {
    ID_UNUSED = 0,
    ID_DELIVERED,
    ID_WAITING,
};

const Event = struct {
    event: *const c_void,
};

const Cancellable = struct {
    event: Event,
    id: ?usize,
    delivery_time: abs_time_t,
};

fn compare(a: Cancellable, b: Cancellable) bool {
    return a.delivery_time < b.delivery_time;
}

const CancelHeap = PriorityQueue(Cancellable);

const EventQueue = struct {
    const Self = @This();

    mutex: Mutex,
    allocator: *Allocator,
    events: CancelHeap,
    ids: ArrayList(id_state_t),
    empty: ResetEvent,

    fn newId(self: *Self) !usize {
        for (self.ids.items) |*id, idx| {
            if (id.* == .ID_UNUSED) {
                id.* = .ID_WAITING;
                return idx;
            }
        }
        try self.ids.append(.ID_WAITING);
        return self.ids.items.len - 1;
    }

    fn isEmptyLH(self: *Self) bool {
        return self.events.count() == 0;
    }

    pub fn create(allocator: *Allocator) ?*Self {
        var q: *Self = allocator.create(Self) catch return null;
        q.mutex = Mutex.init();
        q.allocator = allocator;
        q.events = CancelHeap.init(allocator, compare);
        q.ids = ArrayList(id_state_t).init(allocator);
        q.empty = ResetEvent.init();
        return q;
    }

    pub fn destroy(self: *Self) !void {
        if (self.mutex.tryAcquire()) |held| {
            defer held.release();
            if (self.events.len != 0) {
                return error.NotEmpty;
            } else {
                self.events.deinit();
                self.ids.deinit();
            }
        } else {
            unreachable; // Attempted to free queue while mutex held.
        }
        self.empty.deinit();
        self.mutex.deinit();
        self.allocator.destroy(self);
    }

    /// Schedule a cancellable event to be delivered at the appointed
    /// time. Returns an ID that can be used to cancel the event. The
    /// ID is a limited resource that should be released when it's no
    /// longer needed.
    pub fn schedule(
        self: *Self,
        event: *const c_void,
        time: abs_time_t,
    ) !?usize {
        const lock = self.mutex.acquire();
        defer lock.release();
        const id = self.newId() catch |err| switch (err) {
            Allocator.Error.OutOfMemory => null,
        };
        const cancellable = Cancellable{
            .event = Event{ .event = event },
            .id = id,
            .delivery_time = time,
        };
        try self.events.add(cancellable);
        self.empty.reset();
        return id;
    }

    pub fn post(self: *Self, event: *const c_void, time: abs_time_t) !void {
        const lock = self.mutex.acquire();
        defer lock.release();

        const id = null;
        const cancellable = Cancellable{
            .event = Event{ .event = event },
            .id = id,
            .delivery_time = time,
        };
        try self.events.add(cancellable);
        self.empty.reset();
    }

    pub fn next(self: *Self, time: abs_time_t) ?*const c_void {
        const lock = self.mutex.acquire();
        defer lock.release();

        const candidate = self.events.peek() orelse return null;
        if (candidate.delivery_time > time)
            return null;

        const nxt = self.events.remove();
        const event = nxt.event.event;
        if (nxt.id) |id| {
            assert(self.ids.items[@intCast(usize, id)] == .ID_WAITING);
            self.ids.items[id] = .ID_DELIVERED;
        }

        if (self.isEmptyLH()) {
            self.empty.set();
        }
        return nxt.event.event;
    }

    pub fn isEmpty(self: *Self) bool {
        const lock = self.mutex.acquire();
        defer lock.release();
        return self.isEmptyLH();
    }

    fn cancelLH(
        self: *Self,
        id: usize,
        event: *?*const c_void,
    ) CancelError!void {
        // Loop through the heap looking for a matching id.
        var iterator = self.events.iterator();
        var idx: usize = 0;
        while (iterator.next()) |elem| {
            if (elem.id) |unpacked| {
                if (unpacked == id)
                    break;
            }
            idx += 1;
        } else {
            return CancelError.NoSuchId;
        }

        if (self.events.items.len <= idx) {
            return CancelError.NoSuchId;
        }
        const item = self.events.removeIndex(idx);
        self.ids.items[id] = .ID_UNUSED;
        event.* = item.event.event;
    }

    fn releaseLH(self: *Self, id: usize) CancelError!void {
        self.ids.items[id] = .ID_UNUSED;
    }

    pub fn cancel(
        self: *Self,
        id: ?usize,
        event: *?*const c_void,
    ) CancelError!void {
        event.* = null;
        const lock = self.mutex.acquire();
        defer lock.release();
        const cid = id orelse return CancelError.NoSuchId;
        if (self.ids.items.len <= cid) {
            return CancelError.NoSuchId;
        }
        return switch (self.ids.items[cid]) {
            .ID_UNUSED => CancelError.NoSuchId,
            .ID_DELIVERED => CancelError.AlreadyRun,
            .ID_WAITING => self.cancelLH(cid, event),
        };
    }

    pub fn cancelOrRelease(
        self: *Self,
        id: ?usize,
        event: *?*const c_void,
    ) CancelError!void {
        event.* = null;
        const cid = id orelse return CancelError.NoSuchId;

        const lock = self.mutex.acquire();
        defer lock.release();

        if (self.ids.items.len <= cid)
            return CancelError.NoSuchId;

        return switch (self.ids.items[cid]) {
            .ID_UNUSED => CancelError.NoSuchId,
            .ID_WAITING => self.cancelLH(cid, event),
            .ID_DELIVERED => self.releaseLH(cid),
        };
    }

    pub fn release(self: *Self, id: ?usize) CancelError!void {
        const cid = id orelse return CancelError.NoSuchId;

        const lock = self.mutex.acquire();
        defer lock.release();

        if (self.ids.items.len <= cid)
            return CancelError.NoSuchId;

        return switch (self.ids.items[cid]) {
            .ID_UNUSED => CancelError.NoSuchId,
            .ID_DELIVERED => self.releaseLH(cid),
            .ID_WAITING => CancelError.NotRun,
        };
    }
};

// C interface

const event_queue = @OpaqueType();

fn toEq(q: *event_queue) *EventQueue {
    return @ptrCast(*EventQueue, @alignCast(@alignOf(*EventQueue), q));
}

export fn eq_new() ?*event_queue {
    const allocator = std.heap.c_allocator;
    var eq: *EventQueue = EventQueue.create(allocator) orelse return null;
    return @ptrCast(?*event_queue, eq);
}

export fn eq_free(queue: *event_queue) bool {
    var eq = toEq(queue);
    eq.destroy() catch return false;
    return true;
}

export fn eq_schedule(
    queue: *event_queue,
    event: *const c_void,
    time: abs_time_t,
) cancellable_id_t {
    const eq = toEq(queue);
    const opt_id = eq.schedule(event, time) catch return SCHEDULE_FAIL;
    if (opt_id) |id| {
        // Whoops, cancellable should have been size_t.
        return @intCast(cancellable_id_t, id);
    } else {
        return NOT_CANCELLABLE;
    }
}

export fn eq_post(
    queue: *event_queue,
    event: *const c_void,
    time: abs_time_t,
) bool {
    const eq = toEq(queue);
    eq.post(event, time) catch return false;
    return true;
}

export fn eq_next_event(queue: *event_queue, time: abs_time_t) ?*const c_void {
    const eq = toEq(queue);
    return eq.next(time);
}

export fn eq_empty(queue: *event_queue) bool {
    const eq = toEq(queue);
    return eq.isEmpty();
}

fn errToStatus(err: CancelError) cancellation_status_t {
    return switch (err) {
        CancelError.NoSuchId => .FAIL_NO_SUCH_ID,
        CancelError.AlreadyCancelled => .FAIL_ALREADY_CANCELLED,
        CancelError.AlreadyRun => .FAIL_ALREADY_RUN,
        CancelError.NotRun => .FAIL_NOT_RUN,
        CancelError.Locking => .FAIL_LOCKING,
    };
}

export fn eq_cancel(
    queue: *event_queue,
    id: cancellable_id_t,
    event: *?*c_void,
) cancellation_status_t {
    const eq = toEq(queue);
    const idx = if (id == NOT_CANCELLABLE) null else @intCast(usize, id);
    eq.cancel(idx, event) catch |err| return errToStatus(err);
    return .SUCCESS;
}

export fn eq_cancel_or_release(
    queue: *event_queue,
    id: cancellable_id_t,
    e: *?*const c_void,
) cancellation_status_t {
    const eq = toEq(queue);
    const ev_id = if (id == NOT_CANCELLABLE) null else @intCast(usize, id);
    eq.cancelOrRelease(ev_id, e) catch |err| return errToStatus(err);
    return .SUCCESS;
}

export fn eq_release(
    queue: *event_queue,
    id: cancellable_id_t,
) cancellation_status_t {
    const eq = toEq(queue);
    const ev_id = if (id == NOT_CANCELLABLE) null else @intCast(usize, id);
    eq.release(ev_id) catch |err| return errToStatus(err);
    return .SUCCESS;
}

export fn eq_validate(q: *event_queue) bool {
    return true; // We're assuming the priority queue is sound.
}

export fn eq_wait_empty(queue: *event_queue) void {
    const eq = toEq(queue);
    while (!eq.isEmpty()) {
        eq.empty.timedWait(100_000) catch continue;
        break;
    }
}

fn lessThan(a: u32, b: u32) bool {
    return a < b;
}

test "queue insert/remove" {
    var q = eq_new().?;
    defer std.testing.expectEqual(eq_free(q), true);
    const id8 = eq_schedule(q, @intToPtr(*c_void, 7), 8);
    const id3 = eq_schedule(q, @intToPtr(*c_void, 33), 3);
    std.testing.expectEqual(eq_next_event(q, 0), null);
    std.testing.expectEqual(eq_next_event(q, 4).?, @intToPtr(*c_void, 33));
    std.testing.expectEqual(eq_next_event(q, 9).?, @intToPtr(*c_void, 7));
    std.testing.expectEqual(eq_next_event(q, 1000), null);
}
