const std = @import("std");
const Io = std.Io;

/// Absolute time taken according to some clock base, in ns.
pub const abs_time_t = u64;

/// Relative time between two abs_time_t, in ns.
pub const rel_time_t = i64;

pub fn time_add(t: abs_time_t, d: rel_time_t) abs_time_t {
    return t + d;
}

pub fn time_delta(t1: abs_time_t, t2: abs_time_t) rel_time_t {
    return t1 - t2;
}

pub fn time_compare(t1: abs_time_t, t2: abs_time_t) c_int {
    return if (t1 < t2) -1 else if (t1 == t2) 0 else 1;
}

pub fn get_now_ns(io: Io) abs_time_t {
    return @intCast(Io.Timestamp.now(io, .boot).nanoseconds);
}

pub fn get_now_real_ns(io: Io) void {
    return @intCast(Io.Timestamp.now(io, .real).nanoseconds);
}
