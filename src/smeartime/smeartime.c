#include "smeartime.h"

abs_time_t time_add(abs_time_t t, rel_time_t d)
{
    return t + d;
}

rel_time_t time_delta(abs_time_t t1, abs_time_t t2)
{
    return t1 - t2;
}

int time_compare(abs_time_t t1, abs_time_t t2)
{
    return t1 < t2 ? -1 : t1 == t2 ? 0 : 1;
}
