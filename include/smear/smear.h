#ifndef __SMEAR_H__
#define __SMEAR_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <string.h>
#include <stdlib.h>
#include <stdint.h>

#include <smear/version.h>

const char *SRT_get_version(void);

#define CAT(a, b) a ## b
#define CAT3(a, b, c) a ## b ## c
#define CAT4(a, b, c, d) a ## b ## c ## d

/* For each state machine, instantiate this macro once with the
 * mangled name of the state machine as its argument. */
#define SRT_HANDLERS(m)                                                \
    static void CAT(m, _handler) (const void *msg)                     \
    {                                                                  \
        CAT(m, _Handle_Message) (*( CAT(m, _Event_Wrapper) *)msg);     \
        CAT(m, _Free_Message) (*( CAT(m, _Event_Wrapper) *)msg);       \
        free((void *)msg);                                             \
    }                                                                  \
    void CAT(m, _Send_Message) ( CAT(m, _Event_Wrapper e) )            \
    {                                                                  \
        void *msg;                                                     \
        msg = malloc(sizeof(e));                                       \
        if (msg == NULL) SMUDGE_panic();                               \
        memcpy(msg, &e, sizeof(e));                                    \
        SRT_send_message(msg, CAT(m, _handler));                       \
    }

/* cancel_token_t SRT_delayed_send(<machine name>, <event name>, void *msg,
                                   uint64_t delay_ms); */
/* Send an event with a delay in milliseconds. Returns a
 * cancel_token_t that should be given back with a call to SRT_cancel
 * later. This is a limited resource, so failure to release it will
 * result in a resource leak.
 * 
 * When calling this, machine and event_name are the mangled parts of
 * the event function you want invoked. For example, if you've got a
 * state machine called `TURNSTILE` with an event called `timeout` and
 * you want to send TURNSTILE_timeout(NULL) after 3 seconds, you would
 * write
 *
 * timer_token = SRT_delayed_send(TURNSTILE, timeout, NULL, 3000);
 *
 * then, later, call
 *
 * SRT_cancel(timer_token);
 */
typedef void *(callback_t)(const void *);
#define SRT_delayed_send(machine, event_name, msg, delay_ms)            \
({                                                                      \
    CAT(machine, _Event_Wrapper) *wrapper;                              \
    wrapper = malloc(sizeof(CAT(machine, _Event_Wrapper)));             \
    if (wrapper == NULL) SMUDGE_panic();                                \
    wrapper->id = CAT4(EVID_, machine, _, event_name);                  \
    CAT(wrapper->event.e_, event_name) = msg;                           \
    SRT_send_later(wrapper,                                             \
                   (void (*)(const void *))CAT3(machine, _, event_name), \
                   delay_ms);                                           \
    })

typedef size_t cancel_token_t;
typedef uint64_t time_delta_t;

/* Call SRT_init before sending any events to any state machines. */
void SRT_init(void);

/* SRT_run starts a thread that will run state machines. Events will
 * be processed after this function is called, whether they were sent
 * before or after. Events are guaranteed to be processed in the order
 * they're received. */
void SRT_run(void);

/* SRT_stop ends execution of the runtime and frees associated
 * resources. */
void SRT_stop(void);

/* Block until there are no pending events, then return. Do not call
 * this from within an event handler. It will deadlock. */
void SRT_wait_for_idle(void);

/* Block until there are no events left in the queue, including
 * delayed events, then return. Do not call this from within an event
 * handler. It will deadlock. */
void SRT_wait_for_empty(void);

/* Don't call this directly. */
void SRT_send_message(const void *msg, void (handler)(const void *));

cancel_token_t SRT_send_later(const void *msg, void (handler)(const void *),
                              uint64_t delay_ms);

/* Cancel an event sent with SRT_delayed_send. Also releases resources
 * held by the cancellable event. If this is called after the event is
 * delivered, it only releases the resources. */
void SRT_cancel(cancel_token_t id);

#ifdef __cplusplus
}
#endif

#endif
