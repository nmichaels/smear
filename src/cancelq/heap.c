#include "platform.h"
// Include this .c file after defining heap_data_t.

// Note that the heap_data_t must be a struct with an abs_time_t field
// called delivery_time.

typedef struct
{
    // Size includes the 1 empty slot at the beginning.
    size_t memsize;

    // Index of the next element to be added to the heap.
    size_t nextidx;

    // A pointer to the storage for the heap itself.
    heap_data_t *data;
} heap_t;

static size_t parent(size_t idx)
{
    return idx / 2; // floor division on purpose!
}

static size_t left(size_t idx)
{
    return idx * 2;
}

static size_t right(size_t idx)
{
    return idx * 2 + 1;
}

static void swap(heap_t *heap, size_t a, size_t b)
{
    heap_data_t temp;
    heap_data_t *data;

    data = heap->data;
    memcpy(&temp, &data[a], sizeof(temp));
    memcpy(&data[a], &data[b], sizeof(temp));
    memcpy(&data[b], &temp, sizeof(temp));
}

UNUSED static bool is_pwr_of_2(size_t num)
{
    if (num == 0)
        return false;

    while (num % 2 == 0)
    {
        num /= 2;
    }
    return num == 1;
}

UNUSED static void print_heap(heap_t *heap)
{
    size_t size;

    size = heap->nextidx;
    for (size_t idx = 1; idx < size; idx++)
    {
        if (is_pwr_of_2(idx))
            printf("\n");
        printf(" %"PRIu64" ", heap->data[idx].delivery_time);
    }
    printf("\n");
}

static bool check_heap(const heap_t *heap)
{
    size_t size;
    heap_data_t *data;

    size = heap->nextidx;
    data = heap->data;
    if (data == NULL)
        return false;

    for (size_t i = 1; i < size; i++)
    {
        if (left(i) >= size)
            continue;
        if (data[i].delivery_time > data[left(i)].delivery_time)
            return false;
        if (right(i) >= size)
            continue;
        if (data[i].delivery_time > data[right(i)].delivery_time)
            return false;
    }
    return true;
}

static void postins_reheap(heap_t *heap, size_t idx)
{
    if (idx <= 1)
        return;
    if (heap->data[idx].delivery_time < heap->data[parent(idx)].delivery_time)
    {
        swap(heap, idx, parent(idx));
        postins_reheap(heap, parent(idx));
    }
}

static void reheap(heap_t *heap)
{
    heap_data_t *data;
    size_t last_idx;

    last_idx = heap->nextidx;
    data = heap->data;

    // Think about making this O(log n).
    for (size_t idx = 1; idx < last_idx; idx++)
    {
        if (left(idx) < last_idx &&
            data[idx].delivery_time > data[left(idx)].delivery_time)
        {
            swap(heap, idx, left(idx));
        }
        if (right(idx) < last_idx &&
            data[idx].delivery_time > data[right(idx)].delivery_time)
        {
            swap(heap, idx, right(idx));
        }
    }
}

static void heap_rm(heap_t *heap, size_t idx)
{
    heap_data_t *data;
    size_t last;

    data = heap->data;
    last = heap->nextidx - 1;
    swap(heap, last, idx);
    heap->nextidx--;
    reheap(heap);
    if (HEAP_CHECK)
        assert(check_heap(heap));
    memset(&data[last], 0, sizeof(data[last]));
}

static void newheap(heap_t *storage, size_t size)
{
    heap_data_t *heap;

    heap = calloc(size, sizeof(*heap));
    storage->memsize = size;
    storage->nextidx = 1;
    storage->data = heap;
}

static bool heap_empty(const heap_t *heap)
{
    return heap->nextidx == 1;
}

static bool heap_grow(heap_t *heap)
{
    heap_data_t *new_heap;
    size_t new_size;

    new_size = heap->memsize * 2;
    new_heap = realloc(heap->data, new_size * sizeof(heap_data_t));
    if (new_heap == NULL)
        return false;
    heap->data = new_heap;
    heap->memsize = new_size;
    return true;
}

// Doesn't free the pointer to the heap, just frees the data pointer.
static void heap_free(heap_t *heap)
{
    free(heap->data);
    heap->data = NULL;
}

static bool heap_insert(heap_t *heap, heap_data_t *data)
{
    heap_data_t *dest;

    if (heap->nextidx == heap->memsize && !heap_grow(heap))
        return false;

    dest = &heap->data[heap->nextidx];
    memcpy(dest, data, sizeof(*data));
    postins_reheap(heap, heap->nextidx);
    heap->nextidx++;
    return true;
}

static heap_data_t *heap_peek(heap_t *heap, abs_time_t time)
{
    heap_data_t *next;

    if (heap_empty(heap))
        return NULL;

    next = &heap->data[1];
    if (time_compare(next->delivery_time, time) > 0)
        return NULL;

    return next;
}
