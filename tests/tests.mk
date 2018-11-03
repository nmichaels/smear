VPATH += tests

# Memcheck and helgrind add significant amounts of overhead to
# tests. If a test takes too long to run under one or both of those
# tools, we can exclude it from them by not including it in the
# appropriate list.
TESTS = test-cancelq-fill-then-cancel test-cancelq-fill-then-drain-all \
        test-cancelq-cancel-some-drain-some test-cancelq-not-cancellable \
        test-cancelq-threads test-number test-smear-waits

MEMCHECK_TESTS = \
        test-cancelq-fill-then-cancel test-cancelq-fill-then-drain-all \
        test-cancelq-cancel-some-drain-some test-cancelq-not-cancellable \
        test-cancelq-threads test-number

HELGRIND_TESTS =  \
        test-cancelq-fill-then-cancel test-cancelq-fill-then-drain-all \
        test-cancelq-cancel-some-drain-some test-cancelq-not-cancellable \
        test-cancelq-threads test-number

test-cancelq-%: test-cancelq-%.c obj/cancellable.o
	$(CC) $(CFLAGS) $(INCLUDE) -o $@ $^ $(LIBS)

test-queue: test-queue.c obj/queue.o
	$(CC) $(CFLAGS) $(INCLUDE) -o $@ $^

test-smear-%.o: test-smear-%.c
	$(CC) $(CFLAGS) $(INCLUDE) -c -o $@ $<

test-smear-%: test-smear-%.o test-smear-%_main.o libsmear.a 
	$(CC) $(CFLAGS) $(INCLUDE) -o $@ $^ -pthread

test-number: test-number.c obj/number.o
	$(CC) $(CFLAGS) $(INCLUDE) -o $@ $^

.PHONY: runtests testclean

%.fifo:
	mkfifo $@

%.memcheck.log: % %-mc.fifo
	tee -a $@ < $<-mc.fifo &
	valgrind --tool=memcheck --leak-check=full --error-exitcode=1 ./$< 2>&1 > $<-mc.fifo

%.helgrind.log: % %-hg.fifo
	tee -a $@ < $<-hg.fifo &
	valgrind --tool=helgrind --error-exitcode=1 ./$< 2>&1 > $<-hg.fifo

%.log: % %.fifo
	rm -f $@
	tee -a $@ < $<.fifo &
	./$< 2>&1 > $<.fifo

runtests: $(foreach t, $(TESTS), $(t).log) \
          $(foreach t, $(MEMCHECK_TESTS), $(t).memcheck.log) \
          $(foreach t, $(HELGRIND_TESTS), $(t).helgrind.log)

clean: testclean

testclean:
	rm -f $(TESTS) *.log *.fifo
