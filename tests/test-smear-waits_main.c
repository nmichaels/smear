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
    name = test_Current_state_name();
    assert(strcmp(name, "that") == 0);
    test_event(NULL);
    SRT_wait_for_empty();
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
