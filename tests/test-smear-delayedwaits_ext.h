/* This file is generated by Smudge. Do not edit it. */
#ifndef __test_smear_delayedwaits_ext_h__
#define __test_smear_delayedwaits_ext_h__
#include "test-smear-delayedwaits.h"
extern void test_Send_Message(test_Event_Wrapper);

extern void SMUDGE_debug_print(const char *, const char *, const char *);

extern void SMUDGE_free(const void *);

extern void SMUDGE_panic(void);

extern void SMUDGE_panic_print(const char *, const char *, const char *);

extern void send_delayed(const test_event_t *);
#endif
