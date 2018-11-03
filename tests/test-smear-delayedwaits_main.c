#include <stdio.h>
#include <assert.h>
#include <smear/smear.h>
#include "test-smear-waits_ext.h"
#include "test-smear-waits.h"

void send_delayed(const test_event_t *ignored)
{
    SRT_delayed_send(test, event, NULL, 100);
}

static void body(void)
{
    SRT_init();
    SRT_run();
    assert(strcmp(test_Current_state_name(), "this") == 0);
    test_event(NULL);
    SRT_wait_for_empty();
    assert(strcmp(test_Current_state_name(), "done") == 0);
    SRT_stop();
}

int main(void)
{
    body();
    return 0;
}
