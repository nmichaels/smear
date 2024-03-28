const std = @import("std");
const cancelq = @import("cancelq");

const c = @cImport({
    @cInclude("smear/version.h");
    @cInclude("smeartime.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
});

const Thread = std.Thread;
const Semaphore = Thread.Semaphore;
const Allocator = std.mem.Allocator;

var q: *cancelq.EventQueue = undefined;
var thread: Thread = undefined;
var idle_sem = Semaphore{};
var done = Semaphore{};
var wake = Semaphore{};
const c_allocator = std.heap.c_allocator;

const Handler = *const fn (*const anyopaque) callconv(.C) void;

const Msg = struct {
    wrapper: *const anyopaque,
    handler: Handler,
};

pub fn getVersion() [:0]const u8 {
    return c.SMEAR_VERSION;
}

export fn SRT_get_version() [*c]const u8 {
    return getVersion();
}

pub fn init(allocator: Allocator) !void {
    q = try cancelq.EventQueue.new(allocator);
    // Pthread sem_init would happen here.
}

export fn SRT_init() void {
    init(c_allocator) catch unreachable;
}

/// Sleep for 1 ms.
fn wait_wake() void {
    wake.timedWait(std.time.ns_per_ms) catch {};
}

fn flushEventQueue(allocator: Allocator) void {
    while (true) {
        const qmsg: ?*const Msg = @alignCast(@ptrCast(
            q.nextEvent(c.get_now_ns()),
        ));
        if (qmsg) |msg| {
            msg.handler(msg.wrapper);
            allocator.destroy(msg);
        } else {
            break;
        }
    }
}

fn mainloop(allocator: Allocator) void {
    while (true) {
        flushEventQueue(allocator);
        idle_sem.post();
        checkDone: { // If waiting on the done semaphore succeeds, return.
            done.timedWait(0) catch break :checkDone;
            return;
        }
        wait_wake();
        idle_sem.wait();
    }
}

pub fn run(allocator: Allocator) !void {
    thread = try Thread.spawn(.{}, mainloop, .{allocator});
}

export fn SRT_run() void {
    run(c_allocator) catch unreachable;
}

pub fn stop(allocator: Allocator) void {
    done.post();
    thread.join();
    std.debug.assert(q.free(allocator));
    // Pthread sem_destroy would happen here.
}

export fn SRT_stop() void {
    stop(c_allocator);
}

pub fn waitForIdle() void {
    idle_sem.wait();
    idle_sem.post();
}

export fn SRT_wait_for_idle() void {
    waitForIdle();
}

pub fn waitForEmpty() void {
    var loop: bool = true;
    while (loop) {
        q.waitEmpty();
        idle_sem.wait();
        if (q.empty()) {
            loop = false;
        }
        idle_sem.post();
    }
}

pub fn errorMsg(str: []const u8) void {
    std.debug.print("{s}\n", .{str});
}

export fn SRT_wait_for_empty() void {
    waitForEmpty();
}

/// Return a new message for the queue that wraps up msg and handler.
fn getQMsg(msg: *const anyopaque, handler: Handler, alloc: Allocator) !*Msg {
    const qmsg = try alloc.create(Msg);
    qmsg.wrapper = msg;
    qmsg.handler = handler;
    return qmsg;
}

pub fn sendMessage(
    msg: *anyopaque,
    handler: Handler,
    allocator: Allocator,
) !void {
    const qmsg: *Msg = getQMsg(msg, handler, allocator) catch
        return error.AllocationError;
    q.post(@ptrCast(qmsg), c.get_now_ns()) catch return error.EnqueueError;
    wake.post();
}

export fn SRT_send_message(msg: ?*anyopaque, handler: Handler) void {
    const m = msg orelse {
        errorMsg("Null message sent.");
        std.process.exit(0xfd);
    };

    sendMessage(m, handler, c_allocator) catch |err| {
        switch (err) {
            error.AllocationError => errorMsg(
                "Failed to allocate wrapper memory.",
            ),
            error.EnqueueError => errorMsg("Failed to enqueue message."),
        }
        std.process.exit(0xfd);
    };
}

export fn SRT_send_later(
    msg: ?*anyopaque,
    handler: Handler,
    delay_ms: u64,
) usize {
    const m = msg orelse {
        errorMsg("Null message sent.");
        std.process.exit(0xfd);
    };
    const qmsg = getQMsg(m, handler, c_allocator) catch {
        errorMsg("Failed to allocate wrapper memory.");
        std.process.exit(0xfe);
    };
    const id: usize = q.schedule(
        @ptrCast(qmsg),
        c.get_now_ns() + delay_ms * std.time.ns_per_ms,
    ) catch {
        errorMsg("Failed to schedule message.");
        std.process.exit(0xfe);
    };
    return id;
}

export fn SRT_cancel(id: usize) void {
    const qmsg: ?*const Msg = @alignCast(@ptrCast(q.cancelOrRelease(id) catch {
        errorMsg("Failed to release event.");
        std.process.exit(0x100 - 4);
    }));
    if (qmsg) |msg| {
        c_allocator.destroy(msg);
    }
}

/// Sleep for 1 millisecond.
export fn SRT_nap() void {
    std.time.sleep(std.time.ns_per_ms);
}

export fn SMUDGE_debug_print(fmt: [*c]u8, a1: [*c]u8, a2: [*c]u8) void {
    _ = c.fprintf(c.stderr, fmt, a1, a2);
}

export fn SMUDGE_free(ptr: [*]u8) void {
    c.free(ptr);
}

export fn SMUDGE_panic() void {
    std.debug.assert(false);
}

export fn SMUDGE_panic_print(fmt: [*c]u8, a1: [*c]u8, a2: [*c]u8) void {
    SMUDGE_debug_print(fmt, a1, a2);
    std.debug.assert(false);
}
