const std = @import("std");
const cancelq = @import("cancelq");

const version = @import("version");
const smeartime = @import("smeartime");
const c = std.c;

const Thread = std.Thread;
const Io = std.Io;
const Semaphore = Io.Semaphore;
const Allocator = std.mem.Allocator;

var q: *cancelq.EventQueue = undefined;
var thread: Thread = undefined;
var idle_sem = Semaphore{};
var done = Semaphore{};
var wake = Semaphore{};
const c_allocator = std.heap.c_allocator;
var threaded: Io.Threaded = undefined;

const Handler = *const fn (*const anyopaque) callconv(.c) void;

const Msg = struct {
    wrapper: *const anyopaque,
    handler: Handler,
};

pub fn getVersion() [:0]const u8 {
    return version.SMEAR_VERSION;
}

export fn SRT_get_version() [*c]const u8 {
    return getVersion();
}

pub fn init(allocator: Allocator, io: Io) !void {
    q = try cancelq.EventQueue.new(allocator, io);
    // Pthread sem_init would happen here.
}

export fn SRT_init() void {
    threaded = Io.Threaded.init(c_allocator, .{});
    init(c_allocator, threaded.io()) catch unreachable;
}

/// Sleep for 1 ms.
fn wait_wake(io: Io) void {
    const ms = Io.Timeout{
        .duration = .{ .raw = .fromMilliseconds(1), .clock = .cpu_thread },
    };
    wake.waitTimeout(io, ms) catch {};
}

fn flushEventQueue(allocator: Allocator, io: Io) void {
    while (true) {
        const qmsg: ?*const Msg = @ptrCast(@alignCast(
            q.nextEvent(smeartime.get_now_ns(io)),
        ));
        if (qmsg) |msg| {
            msg.handler(msg.wrapper);
            allocator.destroy(msg);
        } else {
            break;
        }
    }
}

fn mainloop(allocator: Allocator, io: Io) void {
    while (true) {
        flushEventQueue(allocator, io);
        idle_sem.post(io);
        checkDone: { // If waiting on the done semaphore succeeds, return.
            const zero = Io.Timeout{
                .duration = .{ .raw = Io.Duration.zero, .clock = .cpu_thread },
            };
            done.waitTimeout(io, zero) catch break :checkDone;
            return;
        }
        wait_wake(io);
        idle_sem.waitUncancelable(io);
    }
}

pub fn run(allocator: Allocator, io: Io) !void {
    thread = try Thread.spawn(.{}, mainloop, .{ allocator, io });
}

export fn SRT_run() void {
    run(c_allocator, threaded.io()) catch unreachable;
}

pub fn stop(io: Io) void {
    done.post(io);
    thread.join();
    std.debug.assert(q.free());
    // Pthread sem_destroy would happen here.
}

export fn SRT_stop() void {
    stop(threaded.io());
}

pub fn waitForIdle(io: Io) void {
    idle_sem.waitUncancelable(io);
    idle_sem.post(io);
}

export fn SRT_wait_for_idle() void {
    waitForIdle(threaded.io());
}

pub fn waitForEmpty(io: Io) void {
    var loop: bool = true;
    while (loop) {
        q.waitEmpty();
        idle_sem.waitUncancelable(io);
        if (q.empty()) {
            loop = false;
        }
        idle_sem.post(io);
    }
}

pub fn errorMsg(str: []const u8) void {
    std.debug.print("{s}\n", .{str});
}

export fn SRT_wait_for_empty() void {
    waitForEmpty(threaded.io());
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
    io: Io,
) !void {
    const qmsg: *Msg = getQMsg(msg, handler, allocator) catch
        return error.AllocationError;
    q.post(@ptrCast(qmsg), smeartime.get_now_ns(io)) catch
        return error.EnqueueError;
    wake.post(io);
}

export fn SRT_send_message(msg: ?*anyopaque, handler: Handler) void {
    const m = msg orelse {
        errorMsg("Null message sent.");
        std.process.exit(0xfd);
    };

    sendMessage(m, handler, c_allocator, threaded.io()) catch |err| {
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
        smeartime.get_now_ns(threaded.io()) + delay_ms * std.time.ns_per_ms,
    ) catch {
        errorMsg("Failed to schedule message.");
        std.process.exit(0xfe);
    };
    return id;
}

export fn SRT_cancel(id: usize) void {
    const qmsg: ?*const Msg = @ptrCast(@alignCast(q.cancelOrRelease(id) catch {
        errorMsg("Failed to release event.");
        std.process.exit(0x100 - 4);
    }));
    if (qmsg) |msg| {
        c_allocator.destroy(msg);
    }
}

/// Sleep for 1 millisecond.
export fn SRT_nap() void {
    const io = threaded.io();
    const ms = Io.Clock.Duration{
        .raw = .fromMilliseconds(1),
        .clock = .awake,
    };
    ms.sleep(io) catch {};
}

pub extern "c" fn fprintf(fid: c_int, format: [*:0]const u8, ...) c_int;
export fn SMUDGE_debug_print(fmt: [*c]u8, a1: [*c]u8, a2: [*c]u8) void {
    _ = fprintf(c.STDERR_FILENO, fmt, a1, a2);
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
