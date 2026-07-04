#include <windows.h>
#include <Winbase.h>
#include <assert.h>
#include "smeartime.h"
#include "number.h"

#define NANOSECONDS_PER_SECOND 1000000000

abs_time_t get_now_ns(void)
{
    // Per MSDN, "[t]he frequency [...] is fixed at system boot and is
    // consistent across all processors[, so it] need only be queried
    // upon [...] initialization."  The units are counts/second, and it
    // is guaranteed non-zero on WinXP or later.
    static LARGE_INTEGER freq = { .QuadPart = 0 };
    if (freq.QuadPart == 0) {
        QueryPerformanceFrequency(&freq);
    }

    // Monotonic, <1us time stamp, units are counts
    // Guaranteed to succeed on WinXP or later.
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    uint128_t precise, ns;
    precise = mul128(now.QuadPart, NANOSECONDS_PER_SECOND);
    ns = div128(precise, freq.QuadPart);
    assert(ns.hi == 0);
    return ns.lo;
}

abs_time_t get_now_real_ns(void)
{
    // Per MSDN, "Contains a 74-bit value representing the number of
    // 100-nanosecond intervals since January 1, 1601 (UTC)."
    FILETIME now;
    GetSystemTimePreciseAsFileTime(&now);

    uint64_t highAdj = ((uint64_t)now.dwHighDateTime) <<
                       (8*sizeof(now.dwLowDateTime));
    uint128_t ns = mul128(100, highAdj + now.dwLowDateTime);
    assert(ns.hi == 0);
    return ns.lo;
}
