OS ?= linux
SRC += smear.zig smeartime.c
LIBS += -pthread
VPATH := $(VPATH) src/smear/$(OS)/
CFLAGS += -D_POSIX_C_SOURCE=199309L
SRC += smeartime-platform.c

obj/smear.o: src/smear/smear.zig
	zig build

obj/smear.d: # No .d files for zig
	touch obj/smear.d
