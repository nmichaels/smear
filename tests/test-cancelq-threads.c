#include <stdlib.h>
#include <pthread.h>
#include <sched.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <inttypes.h>
#include "cancellable.h"

#define COUNT 3200
#define PARANOID false

static void *insert1(void *q)
{
    intptr_t i;
    cancellable_id_t *ids;

    ids = calloc(COUNT, sizeof(ids[0]));
    assert(ids != NULL);
    for (i = 0; i < COUNT; i++)
        ids[i] = NOT_CANCELLABLE;

    // Start at 2 because if i == 0, then the event will be NULL and
    // it will cause an infinite loop later...
    for (i = 2; i < COUNT; i+= 2)
    {
        ids[i] = eq_schedule(q, (void *)i, i);
        assert(ids[i] > NOT_CANCELLABLE);
    }
    return ids;
}

static void *insert2(void *q)
{
    intptr_t i;
    cancellable_id_t *ids;

    ids = calloc(COUNT, sizeof(ids[0]));
    assert(ids != NULL);
    for (i = 0; i < COUNT; i++)
        ids[i] = NOT_CANCELLABLE;

    for (i = 1; i < COUNT; i+= 2)
    {
        ids[i] = eq_schedule(q, (void *)i, i);
        assert(ids[i] > NOT_CANCELLABLE);
    }
    return ids;
}

static void *wait_for_empty(void *q)
{
    eq_wait_empty(q);
    return NULL;
}

static void test_threads(void)
{
    event_queue_t *q;
    pthread_attr_t attr;
    pthread_t t1, t2, waiter;
    intptr_t i;
    void *rv;
    cancellable_id_t *ids;
    void *e;

    q = eq_new();
    assert(q != NULL);
    assert(eq_empty(q));
    pthread_attr_init(&attr);
    pthread_create(&t1, &attr, insert1, q);
    pthread_create(&t2, &attr, insert2, q);
    pthread_create(&waiter, &attr, wait_for_empty, q);
    pthread_attr_destroy(&attr);

    for (i = 1; i < COUNT; i++)
    {
        do
        {
            while (eq_empty(q))
                sched_yield();
            if (PARANOID)
                assert(eq_validate(q));
            e = eq_next_event(q, i);
        } while (e == NULL);

        if ((i & 0xff) == 0)
            printf("Tick %" PRIdPTR "\n", i);
        assert(e == (void *)i);
    }

    pthread_join(waiter, &rv);
    assert(rv == NULL);
    
    pthread_join(t1, (void **)&ids);
    assert(ids != NULL);
    for (i = 0; i < COUNT; i++)
    {
        if (ids[i] == NOT_CANCELLABLE)
            continue;
        assert(eq_release(q, ids[i]) == SUCCESS);
    }
    free(ids);
    ids = NULL;

    pthread_join(t2, (void **)&ids);
    assert(ids != NULL);
    for (i = 0; i < COUNT; i++)
    {
        if (ids[i] == NOT_CANCELLABLE)
            continue;
        assert(eq_cancel_or_release(q, ids[i], &e) == SUCCESS);
        assert(e == NULL);
    }
    free(ids);
    ids = NULL;
    assert(eq_free(q));
}

int main(void)
{
    test_threads();
    return 0;
}
