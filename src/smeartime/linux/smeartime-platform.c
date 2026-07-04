#include <time.h>
#include <assert.h>
#include "smeartime.h"
#include "number.h"

#define NANOSECONDS_PER_SECOND 1000000000

static abs_time_t get_clock_ns(clockid_t clock)
{
    struct timespec ts;
    clock_gettime(clock, &ts);

    uint128_t now = add128(mul128(ts.tv_sec, NANOSECONDS_PER_SECOND),
                           cast128(ts.tv_nsec));
    assert(now.hi == 0);
    return now.lo;
}

abs_time_t get_now_ns(void)
{
    return get_clock_ns(CLOCK_MONOTONIC_RAW);
}

abs_time_t get_now_real_ns(void)
{
    return get_clock_ns(CLOCK_REALTIME);
}
