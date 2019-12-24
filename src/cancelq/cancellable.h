#ifndef CANCELLABLE_H
#define CANCELLABLE_H

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include "smeartime.h"

#define NOT_CANCELLABLE ((cancellable_id_t)-1)
#define SCHEDULE_FAIL ((cancellable_id_t)-2)

// The event queue that holds all these events
typedef struct event_queue_s event_queue_t;

// ID used to cancel cancellable_t
typedef int cancellable_id_t;

// Return a new event queue that will schedule and deliver events with
// the eq functions below.
event_queue_t *eq_new(void);

// Frees an empty event queue. Fails if the queue is not empty.
bool eq_free(event_queue_t *queue);

// Schedule a cancellable event to be delivered at the appointed
// time. Returns an ID that can be used to cancel the event. The ID is
// a limited resource that should be released when it's no longer
// needed.
cancellable_id_t eq_schedule(event_queue_t *queue, const void *event,
                             abs_time_t time);

// Post an uncancellable event to the queue, to be delivered at time.
bool eq_post(event_queue_t *queue, const void *event, abs_time_t time);

// Returns the next scheduled event for the provided time.
void *eq_next_event(event_queue_t *queue, abs_time_t time);

// Returns whether or not the queue has outstanding events.
bool eq_empty(event_queue_t *queue);

typedef enum
{
    SUCCESS = 0,
    FAIL_NO_SUCH_ID,
    FAIL_ALREADY_CANCELLED,
    FAIL_ALREADY_RUN,
    FAIL_NOT_RUN,
    FAIL_LOCKING
} cancellation_status_t;

// Using one of these functions that operate on cancellable_id_t after
// calling one of them is an error. All of these functions release the
// id they're given unless they return a failure condition. Upon
// failure, the id will not be released.

// Cancel the given event ID. Fails if the event has already been
// run. On success, e points to the cancelled event so that it can be
// freed.
cancellation_status_t eq_cancel(event_queue_t *queue, cancellable_id_t id,
                                void **e);

// Cancel the given event ID if it's still in the queue. Otherwise
// release the resources associated with it. This does not fail if the
// event has run already. On success, e is set to the value held in
// the cancelled event so that it can be freed, or NULL if it's
// already been delivered.
cancellation_status_t eq_cancel_or_release(event_queue_t *queue,
                                           cancellable_id_t id, void **e);

// Release the resources associated with a cancellable event. Fails if
// the event has not already been run.
cancellation_status_t eq_release(event_queue_t *queue, cancellable_id_t id);

// Check that the internal data structure is consistent. There should
// be nothing you can do to make this return anything but true.
bool eq_validate(event_queue_t *q);

// Return when the event queue is empty.
void eq_wait_empty(event_queue_t *q);
#endif
