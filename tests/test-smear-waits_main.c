#include <stdio.h>
#include <assert.h>
#include <smear/smear.h>
#include "test-smear-waits_ext.h"
#include "test-smear-waits.h"

#define ITERATIONS 10000

static void body(void)
{
    const char *volatile name;
    SRT_init();
    SRT_run();

    name = test_Current_state_name();
    assert(strcmp(name, "this") == 0);
    test_event(NULL);
    SRT_wait_for_empty();
    // There's a race here, where SRT_wait_for_empty() can return
    // before the event is actually handled. To get around this, we
    // just wait an extra millisecond. This would tie us to POSIX if I
    // didn't stick a sleep function in smear.zig, but I did. It slows
    // the test down by a lot, since we're running 10,000 iterations
    // and 2ms * 10,000 is 20 seconds, but at least now it passes.
    SRT_nap();
    name = test_Current_state_name();
    assert(strcmp(name, "that") == 0);
    test_event(NULL);
    SRT_wait_for_empty();
    SRT_nap();
    name = test_Current_state_name();
    assert(strcmp(name, "this") == 0);
    SRT_stop();
}

int main(void)
{
    for (int i = 0; i < ITERATIONS; i++)
    {
        if ((i & 0xFF) == 0)
        {
            printf("Tick %d\n", i);
            fflush(0);
        }
        body();
    }

    return 0;
}
