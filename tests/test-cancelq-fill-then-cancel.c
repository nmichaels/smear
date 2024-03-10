#include <stdint.h>
#include <assert.h>
#include "cancellable.h"

#define COUNT 32
#define PARANOID true

int main(void)
{
    event_queue_t *q;
    cancellable_id_t ids[COUNT];
    intptr_t e;

    q = eq_new();
    assert(eq_empty(q));
    assert(eq_validate(q));

    for (intptr_t i = 0; i < COUNT; i++)
    {
        ids[i] = eq_schedule(q, (void *)i, i*2);
        assert(ids[i] >= 0);
        if (PARANOID)
            assert(eq_validate(q));
        assert(ids[i] != NOT_CANCELLABLE);
        assert(!eq_empty(q));
        assert(eq_release(q, ids[i]) == FAIL_NOT_RUN);
        if (PARANOID)
            assert(eq_validate(q));
    }

    assert(eq_validate(q));
    for (intptr_t i = COUNT - 1; i >= 0; i--)
    {
        assert(!eq_empty(q));
        if (i & 1)
        {
            assert(eq_cancel(q, ids[i], (void **)&e) == SUCCESS);
            if (PARANOID)
                assert(eq_validate(q));
            assert(e == i);
            assert(eq_cancel_or_release(q, ids[i],(void **)&e) == FAIL_NO_SUCH_ID);
            if (PARANOID)
                assert(eq_validate(q));
            assert(e == (intptr_t)NULL);
        }
        else
        {
            assert(eq_cancel_or_release(q, ids[i], (void **)&e) == SUCCESS);
            if (PARANOID)
                assert(eq_validate(q));
            assert(e == i);
            assert(eq_cancel(q, ids[i], (void **)&e) == FAIL_NO_SUCH_ID);
            if (PARANOID)
                assert(eq_validate(q));
            assert(e == (intptr_t)NULL);
        }
    }

    assert(eq_validate(q));
    assert(eq_empty(q));
    assert(eq_next_event(q, 0) == NULL);
    assert(eq_free(q));
    q = NULL;
    return 0;
}
