#include <assert.h>
#include "queue.h"

int main(void)
{
    struct queue *q;
    void *val;

    q = newq();
    assert(enqueue(q, (void *)0x1111111100000000)); // 1
    assert(enqueue(q, (void *)0x2222222211111111)); // 2
    assert(dequeue(q, &val));                             // 1
    assert(val == (void *)0x1111111100000000);
    assert(enqueue(q, (void *)0x3333333322222222)); // 2
    assert(dequeue(q, &val));                             // 1
    assert(val == (void *)0x2222222211111111);
    assert(enqueue(q, (void *)0x4444444433333333)); // 2
    assert(enqueue(q, (void *)0x5555555544444444)); // 3
    assert(enqueue(q, (void *)0x6666666655555555)); // 4
    assert(enqueue(q, (void *)0x7777777766666666)); // 5
    assert(enqueue(q, (void *)0x8888888877777777)); // 6
    assert(enqueue(q, (void *)0x9999999988888888)); // 7
    assert(dequeue(q, &val)); // 6
    assert(val == (void *)0x3333333322222222);
    assert(dequeue(q, &val)); // 5
    assert(val == (void *)0x4444444433333333);
    assert(dequeue(q, &val)); // 4
    assert(val == (void *)0x5555555544444444);
    assert(dequeue(q, &val)); // 3
    assert(val == (void *)0x6666666655555555);
    assert(dequeue(q, &val)); // 2
    assert(val == (void *)0x7777777766666666);
    assert(dequeue(q, &val)); // 1
    assert(val == (void *)0x8888888877777777);
    assert(dequeue(q, &val)); // 0
    assert(val == (void *)0x9999999988888888);
}
