OS ?= linux
SRC += smeartime.zig
VPATH := $(VPATH) src/smeartime/$(OS)/
CFLAGS += -D_POSIX_C_SOURCE=199309L
SRC += smeartime-platform.c
INCLUDE += -Isrc/smeartime

obj/smeartime.o: src/smeartime/smeartime.zig
	zig build

obj/smeartime.d: # No .d files for zig
	touch obj/smeartime.d
