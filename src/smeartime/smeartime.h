#ifndef SMEARTIME_H
#define SMEARTIME_H

#include <stdint.h>

// Absolute time taken according to some clock base, in ns.
typedef uint64_t abs_time_t;

// Relative time between two abs_time_t, in ns.
typedef int64_t rel_time_t;

// These are only used from Zig code.
abs_time_t get_now_ns(void);

abs_time_t get_now_real_ns(void);

abs_time_t time_add(abs_time_t, rel_time_t);

rel_time_t time_delta(abs_time_t, abs_time_t);

int time_compare(abs_time_t, abs_time_t);

#endif
