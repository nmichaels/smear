#include <stdio.h>
#include <assert.h>
#include <smear/smear.h>
#include "test-smear-waits_ext.h"
#include "test-smear-waits.h"

#define ITERATIONS 10000

static void body(void)
{
    SRT_init();
    SRT_run();
    assert(strcmp(test_Current_state_name(), "this") == 0);
    test_event(NULL);
    SRT_wait_for_empty();
    assert(strcmp(test_Current_state_name(), "that") == 0);
    test_event(NULL);
    SRT_wait_for_empty();
    assert(strcmp(test_Current_state_name(), "this") == 0);
    SRT_stop();
}

int main(void)
{
    for (int i = 0; i < ITERATIONS; i++)
        body();
    return 0;
}
