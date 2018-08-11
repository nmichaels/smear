#define _GNU_SOURCE
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <pthread.h>
#include "smeartime.h"
#include "cancellable.h"
#include "smear.h"

#define EXPORT_SYMBOL __attribute__((visibility ("default")))
#define ERROR_MSG(msg) fprintf(stderr, "%s - %s\n", __FUNCTION__, msg)

#define NS_PER_MS 1000000

typedef void (*handler_t)(const void *);

typedef struct
{
    const void *wrapper;
    handler_t handler;
} mq_msg_t;

static event_queue_t *q;
static pthread_t tid;

/* The plan:
 *
 * Put messages received onto a queue inside the _Send_Message
 * function; pop messages off the queue and send them on using the
 * _Handle_Message function. Messages sent come with pointers to
 * wrappers (cast to void) and pointers to the appropriate
 * _Handle_Message function. This can all just use the queue
 * implementation from queue.c.
 */

static void flushEventQueue(void)
{
    mq_msg_t *qmsg;

    while(!eq_empty(q))
    {
        qmsg = eq_next_event(q, get_now_ns());
        if (qmsg == NULL)
            continue;
        qmsg->handler(qmsg->wrapper);
        free(qmsg);
    }
}

static void *mainloop(void *unused)
{
    while (true)
    {
        flushEventQueue();
        sleep(0);
    }
    return NULL;
}

static void SRT_join(void)
{
    void *rv;
    pthread_join(tid, &rv);
}

static mq_msg_t *getQMsg(const void *msg, void (handler)(const void *))
{
    mq_msg_t *qmsg;

    if (msg == NULL)
    {
        ERROR_MSG("Null message sent.");
        exit(-3);
    }
    qmsg = malloc(sizeof(mq_msg_t));
    if (qmsg == NULL)
    {
        ERROR_MSG("Failed to allocate wrapper memory.");
        exit(-2);
    }
    qmsg->wrapper = msg;
    qmsg->handler = handler;

    return qmsg;
}

EXPORT_SYMBOL void SMUDGE_debug_print(const char *fmt, const char *a1,
                                      const char *a2)
{
    fprintf(stderr, fmt, a1, a2);
}

EXPORT_SYMBOL void SMUDGE_free(const void *a1)
{
    free((void *)a1);
}

EXPORT_SYMBOL void SMUDGE_panic(void)
{
    exit(-1);
}

EXPORT_SYMBOL void SMUDGE_panic_print(const char *fmt, const char *a1,
                                      const char *a2)
{
    SMUDGE_debug_print(fmt, a1, a2);
    SMUDGE_panic();
}

EXPORT_SYMBOL void SRT_send_message(const void *msg,
                                    void (handler)(const void *))
{
    mq_msg_t *qmsg;

    qmsg = getQMsg(msg, handler);
    if (!eq_post(q, qmsg, get_now_ns()))
    {
        ERROR_MSG("Failed to enqueue message.");
        exit(-2);
    }
}

EXPORT_SYMBOL cancel_token_t SRT_send_later(const void *msg,
                                            void (handler)(const void *),
                                            uint64_t delay_ms)
{
    mq_msg_t *qmsg;
    cancellable_id_t id;

    qmsg = getQMsg(msg, handler);
    id = eq_schedule(q, qmsg, get_now_ns() + delay_ms * NS_PER_MS);
    if (id == NOT_CANCELLABLE || id == SCHEDULE_FAIL)
    {
        ERROR_MSG("Failed to schedule message.");
        exit(-2);
    }
    return id;
}

EXPORT_SYMBOL void SRT_cancel(cancel_token_t id)
{
    mq_msg_t *qmsg;

    if (eq_cancel_or_release(q, id, (void **)&qmsg) != SUCCESS)
    {
        ERROR_MSG("Failed to release event.");
        exit(-4);
    }
    if (qmsg != NULL)
        SMUDGE_free(qmsg);
}

EXPORT_SYMBOL void SRT_init(void)
{
    q = eq_new();
}

EXPORT_SYMBOL void SRT_run(void)
{
    pthread_attr_t attr;

    pthread_attr_init(&attr);
    pthread_create(&tid, &attr, mainloop, NULL);
    pthread_attr_destroy(&attr);
}

EXPORT_SYMBOL void SRT_wait_for_idle(void)
{
    return eq_wait_empty(q);
}

EXPORT_SYMBOL void SRT_stop(void)
{
    void *rv;
    pthread_cancel(tid);
    pthread_join(tid, &rv);
    eq_free(q);
}
